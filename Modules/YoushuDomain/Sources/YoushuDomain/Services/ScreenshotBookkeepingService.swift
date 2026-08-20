import Foundation

/// 截图 AI 记账编排：识别 → 校验 DTO →（用户确认后）创建 Transaction。
/// AI 不直接写库；余额由 AccountBalanceEngine 从 Transaction 派生。
public struct ScreenshotBookkeepingService: Sendable {
    private let extractor: any TransactionExtracting
    private let transactionService: any TransactionManaging
    private let accounts: any AccountRepository
    private let consentService: AIDataConsentService?
    private let media: MediaLifecycleService?
    private let recognitionRecords: (any AIRecognitionRecordRepository)?

    public init(
        extractor: any TransactionExtracting,
        transactionService: any TransactionManaging,
        accounts: any AccountRepository,
        consentService: AIDataConsentService? = nil,
        media: MediaLifecycleService? = nil,
        recognitionRecords: (any AIRecognitionRecordRepository)? = nil
    ) {
        self.extractor = extractor
        self.transactionService = transactionService
        self.accounts = accounts
        self.consentService = consentService
        self.media = media
        self.recognitionRecords = recognitionRecords
    }

    /// 从单张图片识别交易草稿。不创建 Transaction。需已授权截图发给 AI。
    public func recognize(imageData: Data, userId: UUID) async throws -> ScreenshotRecognitionResult {
        guard !imageData.isEmpty else {
            throw AIRecognitionError.imageUnreadable
        }

        var retainOriginal = false
        if let consentService {
            let consent = try await consentService.requireScreenshotImage(userId: userId)
            retainOriginal = consent.retainOriginalImages
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
        var imageId = MediaLifecyclePolicy.makeImageId(for: imageData)

        if let media {
            let artifact = try await media.register(
                data: imageData,
                userId: userId,
                kind: .screenshotTransaction,
                retainOriginal: retainOriginal
            )
            imageId = artifact.id
        }

        if let recognitionRecords {
            try await recognitionRecords.upsert(
                AIRecognitionRecord(
                    userId: userId,
                    kind: .screenshotTransaction,
                    sourceImageId: imageId,
                    status: .recognized,
                    modelName: extractor.name,
                    summaryLabel: "截图记账识别"
                )
            )
        }

        return ScreenshotRecognitionResult(
            aiDraft: draft,
            editableDraft: draft,
            warnings: warnings,
            sourceImageId: imageId
        )
    }

    /// 用户确认最终数据后创建 Transaction，并按策略清理原图。
    public func confirm(
        _ input: ConfirmScreenshotTransactionInput,
        userId: UUID
    ) async throws -> Transaction {
        try TransactionDraftValidator.validateConfirmation(input)
        let tx = try await transactionService.record(
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
                sourceImageId: input.sourceImageId
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
        return tx
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
