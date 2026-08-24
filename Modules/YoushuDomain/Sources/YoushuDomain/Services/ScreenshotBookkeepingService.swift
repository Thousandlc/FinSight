import Foundation

/// 截图 AI 记账编排：识别 → 校验 DTO →（用户确认后）创建 Transaction。
/// AI 不直接写库；余额由 AccountBalanceEngine 从 Transaction 派生。
public struct ScreenshotBookkeepingService: Sendable {
    private let extractor: any TransactionExtracting
    private let transactionService: any TransactionManaging
    private let accounts: any AccountRepository
    private let transactions: (any TransactionRepository)?
    private let confirmedImportProvenances: (any ConfirmedImportProvenanceRepository)?
    private let consentService: AIDataConsentService?
    private let media: MediaLifecycleService?
    private let recognitionRecords: (any AIRecognitionRecordRepository)?

    public init(
        extractor: any TransactionExtracting,
        transactionService: any TransactionManaging,
        accounts: any AccountRepository,
        transactions: (any TransactionRepository)? = nil,
        confirmedImportProvenances: (any ConfirmedImportProvenanceRepository)? = nil,
        consentService: AIDataConsentService? = nil,
        media: MediaLifecycleService? = nil,
        recognitionRecords: (any AIRecognitionRecordRepository)? = nil
    ) {
        self.extractor = extractor
        self.transactionService = transactionService
        self.accounts = accounts
        self.transactions = transactions
        self.confirmedImportProvenances = confirmedImportProvenances
        self.consentService = consentService
        self.media = media
        self.recognitionRecords = recognitionRecords
    }

    /// Local exact-source duplicate check before Provider recognition (ADR-036 Step D).
    /// Does not require AI consent and does not persist provenance.
    public func checkPriorImport(
        imageData: Data,
        userId: UUID
    ) async throws -> ScreenshotPriorImportWarning? {
        guard !imageData.isEmpty else { return nil }
        let importIdentity = TransactionScreenshotImportIdentity.from(imageData: imageData)
        guard let confirmedImportProvenances else { return nil }

        guard let provenance = try await confirmedImportProvenances.find(
            userId: userId,
            capability: .transactionScreenshot,
            operationFingerprint: importIdentity.operationFingerprint
        ) else {
            return nil
        }

        var summaries: [PriorImportedTransactionSummary] = []
        if let transactions {
            for reference in provenance.confirmedEntityReferences {
                guard case .transaction(let transactionId) = reference else { continue }
                guard let transaction = try await transactions.fetch(id: transactionId),
                      transaction.userId == userId else {
                    continue
                }
                summaries.append(
                    PriorImportedTransactionSummary(
                        id: transaction.id,
                        merchant: transaction.merchant,
                        amountText: "\(transaction.amount.amount)",
                        date: transaction.date
                    )
                )
            }
        }

        guard !summaries.isEmpty else { return nil }
        return ScreenshotPriorImportWarning(
            importIdentity: importIdentity,
            existingTransactions: summaries
        )
    }

    /// Phase 1：Provider 识别与 DTO 校验。不创建 Transaction，不持久化识别/媒体元数据。
    public func recognize(
        imageData: Data,
        userId: UUID,
        importIdentity: TransactionScreenshotImportIdentity
    ) async throws -> PendingScreenshotRecognition {
        guard !imageData.isEmpty else {
            throw AIRecognitionError.imageUnreadable
        }

        if let consentService {
            _ = try await consentService.requireScreenshotImage(userId: userId)
        }

        let draft: TransactionDraft
        do {
            draft = try await extractor.extractTransactionDraft(fromImageData: imageData)
        } catch let error as AIRecognitionError {
            throw error
        } catch let error as PrivacyError {
            throw error
        } catch {
            throw AIRecognitionError.requestFailed(PrivacySafeErrorMapper.userMessage(for: error))
        }

        let warnings = try TransactionDraftValidator.validateRecognition(draft)
        return PendingScreenshotRecognition(
            aiDraft: draft,
            warnings: warnings,
            imageData: imageData,
            importIdentity: importIdentity
        )
    }

    /// Phase 2：Application 确认当前操作后，持久化 eligible 媒体与识别审计元数据。
    public func acceptRecognition(
        _ pending: PendingScreenshotRecognition,
        userId: UUID
    ) async throws -> ScreenshotRecognitionResult {
        if let recognitionRecords,
           let existing = try await recognitionRecords.fetch(id: pending.acceptanceToken) {
            return ScreenshotRecognitionResult(
                acceptanceToken: pending.acceptanceToken,
                aiDraft: pending.aiDraft,
                editableDraft: pending.editableDraft,
                warnings: pending.warnings,
                sourceImageId: existing.sourceImageId,
                importIdentity: pending.importIdentity
            )
        }

        var retainOriginal = false
        if let consentService {
            let consent = try await consentService.requireScreenshotImage(userId: userId)
            retainOriginal = consent.retainOriginalImages
        }

        var imageId = MediaLifecyclePolicy.makeImageId(for: pending.imageData)
        var registeredMedia = false

        if let media {
            do {
                let artifact = try await media.register(
                    data: pending.imageData,
                    userId: userId,
                    kind: .screenshotTransaction,
                    retainOriginal: retainOriginal
                )
                imageId = artifact.id
                registeredMedia = true
            } catch {
                throw AIRecognitionError.requestFailed("识别结果保存失败，请重试")
            }
        }

        if let recognitionRecords {
            do {
                try await recognitionRecords.upsert(
                    AIRecognitionRecord(
                        id: pending.acceptanceToken,
                        userId: userId,
                        kind: .screenshotTransaction,
                        sourceImageId: imageId,
                        status: .recognized,
                        modelName: extractor.name,
                        summaryLabel: "截图记账识别"
                    )
                )
            } catch {
                if registeredMedia, let media {
                    try? await media.deleteImage(imageId: imageId, userId: userId)
                }
                throw AIRecognitionError.requestFailed("识别结果保存失败，请重试")
            }
        }

        return ScreenshotRecognitionResult(
            acceptanceToken: pending.acceptanceToken,
            aiDraft: pending.aiDraft,
            editableDraft: pending.editableDraft,
            warnings: pending.warnings,
            sourceImageId: imageId,
            importIdentity: pending.importIdentity
        )
    }

    /// 用户确认最终数据后创建 Transaction，并按策略清理原图。
    public func confirm(
        _ input: ConfirmScreenshotTransactionInput,
        userId: UUID
    ) async throws -> ConfirmScreenshotTransactionOutcome {
        try TransactionDraftValidator.validateConfirmation(input)
        let outcome = try await transactionService.record(
            RecordTransactionInput(
                amount: input.amount,
                currencyCode: input.currencyCode,
                date: input.date,
                merchant: input.merchant,
                category: input.category,
                accountId: input.accountId,
                note: input.note,
                formType: input.formType,
                source: .screenshot,
                recognitionConfidence: input.recognitionConfidence,
                sourceImageId: input.sourceImageId,
                idempotencyKey: input.confirmationToken
            ),
            userId: userId
        )

        if let imageId = input.sourceImageId, let media {
            try? await media.markProcessedAndMaybePurge(imageId: imageId, userId: userId)
        }
        if let recognitionRecords, let imageId = input.sourceImageId {
            let records = try await recognitionRecords.fetchAll(userId: userId)
            for var record in records where record.sourceImageId == imageId {
                record.status = .confirmed
                record.completedAt = Date()
                try? await recognitionRecords.upsert(record)
            }
        }

        var provenanceIssue: String?
        if let importIdentity = input.importIdentity, let confirmedImportProvenances {
            do {
                let provenance = try ConfirmedImportProvenance(
                    userId: userId,
                    capability: .transactionScreenshot,
                    sourceFingerprints: [importIdentity.sourceFingerprint],
                    confirmedEntityReferences: [.transaction(outcome.transaction.id)]
                )
                _ = try await confirmedImportProvenances.upsert(provenance)
            } catch {
                provenanceIssue = "导入来源记录未能保存，不影响已保存的账单"
            }
        }

        return ConfirmScreenshotTransactionOutcome(
            transaction: outcome.transaction,
            debtLinkingIssue: outcome.debtLinkingIssue,
            provenanceIssue: provenanceIssue
        )
    }

    /// 用户接受截图隐私条款后写入 AIDataConsent。
    public func acceptPrivacy(userId: UUID) async throws {
        guard let consentService else { return }
        _ = try await consentService.acceptScreenshotPrivacy(userId: userId)
    }

    public func defaultAccountId(
        for draft: TransactionDraft,
        userId: UUID
    ) async throws -> UUID? {
        let list = try await accounts.fetchAll(userId: userId)
        return TransactionDraftValidator.resolveAccountId(
            suggestedName: draft.suggestedAccountName,
            accounts: list,
            fallback: list.first?.id
        )
    }
}
