import Foundation
import YoushuFoundation

/// AI 债务扫描编排：扫描 → 校验 → 聚合 →（用户确认后）创建 Debt。
/// AI 输出不得直接入库。
public struct DebtScannerService: Sendable {
    public static let recommendedMinDocuments = 5
    public static let recommendedMaxDocuments = 20

    private let scanner: any DebtScanning
    private let debtService: any DebtManaging
    private let debts: (any DebtRepository)?
    private let confirmedImportProvenances: (any ConfirmedImportProvenanceRepository)?
    private let consentService: AIDataConsentService?
    private let media: MediaLifecycleService?
    private let recognitionRecords: (any AIRecognitionRecordRepository)?

    public init(
        scanner: any DebtScanning,
        debtService: any DebtManaging,
        debts: (any DebtRepository)? = nil,
        confirmedImportProvenances: (any ConfirmedImportProvenanceRepository)? = nil,
        consentService: AIDataConsentService? = nil,
        media: MediaLifecycleService? = nil,
        recognitionRecords: (any AIRecognitionRecordRepository)? = nil
    ) {
        self.scanner = scanner
        self.debtService = debtService
        self.debts = debts
        self.confirmedImportProvenances = confirmedImportProvenances
        self.consentService = consentService
        self.media = media
        self.recognitionRecords = recognitionRecords
    }

    /// Local exact-batch prior-scan lookup before Provider recognition (ADR-036 Step E).
    public func checkPriorScan(
        documents: [BillDocument],
        userId: UUID
    ) async throws -> DebtPriorScanWarning? {
        guard !documents.isEmpty else { return nil }
        for document in documents where document.data.isEmpty {
            return nil
        }

        let importIdentity = DebtScanImportIdentity.from(documents: documents)
        guard let confirmedImportProvenances else { return nil }

        guard let provenance = try await confirmedImportProvenances.find(
            userId: userId,
            capability: .debtScan,
            operationFingerprint: importIdentity.operationFingerprint
        ) else {
            return nil
        }

        var summaries: [PriorImportedDebtSummary] = []
        if let debts {
            for reference in provenance.confirmedEntityReferences {
                guard case .debt(let debtId) = reference else { continue }
                guard let debt = try await debts.fetch(id: debtId), debt.userId == userId else {
                    continue
                }
                summaries.append(
                    PriorImportedDebtSummary(
                        id: debt.id,
                        lender: debt.lender,
                        productName: debt.productName,
                        outstandingBalanceText: debt.outstandingBalance.map { "\($0.amount)" }
                    )
                )
            }
        }

        guard !summaries.isEmpty else { return nil }
        return DebtPriorScanWarning(importIdentity: importIdentity, existingDebts: summaries)
    }

    /// Phase 1：Provider 扫描、聚合与校验。不持久化媒体/识别元数据。
    public func scan(
        documents: [BillDocument],
        userId: UUID,
        importIdentity: DebtScanImportIdentity
    ) async throws -> PendingDebtScanResult {
        guard !documents.isEmpty else {
            throw AIRecognitionError.imageUnreadable
        }
        for document in documents where document.data.isEmpty {
            throw AIRecognitionError.imageUnreadable
        }

        if let consentService {
            _ = try await consentService.requireDebtScanImage(userId: userId)
        }

        var warnings: [String] = []
        if documents.count < Self.recommendedMinDocuments {
            warnings.append("建议上传 \(Self.recommendedMinDocuments)–\(Self.recommendedMaxDocuments) 张账单以提高覆盖率（当前 \(documents.count) 张）。")
        }
        if documents.count > Self.recommendedMaxDocuments {
            warnings.append("一次上传超过 \(Self.recommendedMaxDocuments) 张，可能影响识别稳定性。")
        }

        let raw: [DebtCandidate]
        do {
            raw = try await scanner.scanDebts(from: documents)
        } catch let error as AIRecognitionError {
            throw error
        } catch let error as PrivacyError {
            throw error
        } catch {
            throw AIRecognitionError.requestFailed(PrivacySafeErrorMapper.userMessage(for: error))
        }

        let aggregated = DebtCandidateAggregator.aggregate(raw)
        guard !aggregated.isEmpty else {
            throw AIRecognitionError.invalidResponse("未从账单中发现债务，请更换更清晰的截图后重试。")
        }

        let validationWarnings = try DebtCandidateValidator.validateBatch(aggregated)
        warnings.append(contentsOf: validationWarnings)

        return PendingDebtScanResult(
            candidates: aggregated,
            warnings: Array(Set(warnings)).sorted(),
            documentCount: documents.count,
            documents: documents,
            importIdentity: importIdentity
        )
    }

    /// Phase 2：Application 确认当前操作后，持久化 eligible 媒体与识别审计元数据。
    public func acceptScan(_ pending: PendingDebtScanResult, userId: UUID) async throws -> DebtScanResult {
        if let recognitionRecords,
           let existing = try await recognitionRecords.fetch(id: pending.acceptanceToken) {
            _ = existing
            return DebtScanResult(
                acceptanceToken: pending.acceptanceToken,
                candidates: pending.candidates,
                warnings: pending.warnings,
                documentCount: pending.documentCount,
                importIdentity: pending.importIdentity
            )
        }

        var retainOriginal = false
        if let consentService {
            let consent = try await consentService.requireDebtScanImage(userId: userId)
            retainOriginal = consent.retainOriginalImages
        }

        var registeredImageIds: [String] = []
        if let media {
            for doc in pending.documents {
                do {
                    let artifact = try await media.register(
                        data: doc.data,
                        userId: userId,
                        kind: .debtScan,
                        retainOriginal: retainOriginal
                    )
                    registeredImageIds.append(artifact.id)
                } catch {
                    await rollbackRegisteredMedia(imageIds: registeredImageIds, userId: userId)
                    throw AIRecognitionError.requestFailed("识别结果保存失败，请重试")
                }
            }
        }

        if let recognitionRecords {
            do {
                try await recognitionRecords.upsert(
                    AIRecognitionRecord(
                        id: pending.acceptanceToken,
                        userId: userId,
                        kind: .debtScan,
                        sourceImageId: registeredImageIds.first,
                        status: .recognized,
                        modelName: scanner.name,
                        summaryLabel: "债务账单扫描（\(pending.documentCount)张）"
                    )
                )
            } catch {
                await rollbackRegisteredMedia(imageIds: registeredImageIds, userId: userId)
                throw AIRecognitionError.requestFailed("识别结果保存失败，请重试")
            }
        }

        return DebtScanResult(
            acceptanceToken: pending.acceptanceToken,
            candidates: pending.candidates,
            warnings: pending.warnings,
            documentCount: pending.documentCount,
            importIdentity: pending.importIdentity
        )
    }

    /// 用户确认后的候选才创建正式 Debt。返回逐项结果；不会在部分成功后抛出整体失败。
    public func confirm(
        requests: [ConfirmDebtCandidateInput],
        userId: UUID,
        importIdentity: DebtScanImportIdentity? = nil,
        cumulativeConfirmedDebtIds: [UUID] = []
    ) async -> DebtScanConfirmOutcome {
        guard !requests.isEmpty else {
            return DebtScanConfirmOutcome(results: [])
        }

        var results: [DebtScanCandidateConfirmResult] = []
        var stopAfterFailure = false
        var newlySucceededDebtIds: [UUID] = []

        for request in requests {
            if stopAfterFailure {
                results.append(
                    DebtScanCandidateConfirmResult(
                        reviewItemId: request.reviewItemId,
                        confirmationToken: request.confirmationToken,
                        status: .notAttempted
                    )
                )
                continue
            }

            do {
                _ = try DebtCandidateValidator.validate(request.candidate)
                let input = try makeCreateInput(
                    from: request.candidate,
                    idempotencyKey: request.confirmationToken
                )
                let debt = try await debtService.create(input, userId: userId)
                newlySucceededDebtIds.append(debt.id)
                results.append(
                    DebtScanCandidateConfirmResult(
                        reviewItemId: request.reviewItemId,
                        confirmationToken: request.confirmationToken,
                        status: .succeeded,
                        debtId: debt.id
                    )
                )
            } catch {
                results.append(
                    DebtScanCandidateConfirmResult(
                        reviewItemId: request.reviewItemId,
                        confirmationToken: request.confirmationToken,
                        status: .failed,
                        errorMessage: PrivacySafeErrorMapper.userMessage(for: error)
                    )
                )
                stopAfterFailure = true
            }
        }

        var provenanceIssue: String?
        if let importIdentity, let confirmedImportProvenances, !newlySucceededDebtIds.isEmpty {
            provenanceIssue = await upsertBatchProvenance(
                importIdentity: importIdentity,
                cumulativeConfirmedDebtIds: cumulativeConfirmedDebtIds,
                newlySucceededDebtIds: newlySucceededDebtIds,
                userId: userId,
                repository: confirmedImportProvenances
            )
        }

        let outcome = DebtScanConfirmOutcome(results: results, provenanceIssue: provenanceIssue)
        if outcome.isFullySuccessful {
            await finalizeRecognitionRecords(userId: userId)
        }
        return outcome
    }

    /// Convenience for tests and legacy call sites without explicit review identity.
    public func confirm(
        candidates: [DebtCandidate],
        userId: UUID,
        confirmationTokens: [UUID]? = nil,
        importIdentity: DebtScanImportIdentity? = nil,
        cumulativeConfirmedDebtIds: [UUID] = []
    ) async -> DebtScanConfirmOutcome {
        let requests = candidates.enumerated().map { index, candidate in
            ConfirmDebtCandidateInput(
                reviewItemId: candidate.id,
                confirmationToken: confirmationTokens?[index] ?? UUID(),
                candidate: candidate
            )
        }
        return await confirm(
            requests: requests,
            userId: userId,
            importIdentity: importIdentity,
            cumulativeConfirmedDebtIds: cumulativeConfirmedDebtIds
        )
    }

    private func upsertBatchProvenance(
        importIdentity: DebtScanImportIdentity,
        cumulativeConfirmedDebtIds: [UUID],
        newlySucceededDebtIds: [UUID],
        userId: UUID,
        repository: any ConfirmedImportProvenanceRepository
    ) async -> String? {
        var seen = Set<UUID>()
        var orderedIds: [UUID] = []
        for debtId in cumulativeConfirmedDebtIds + newlySucceededDebtIds where seen.insert(debtId).inserted {
            orderedIds.append(debtId)
        }
        guard !orderedIds.isEmpty else { return nil }

        do {
            let provenance = try ConfirmedImportProvenance(
                userId: userId,
                capability: .debtScan,
                sourceFingerprints: importIdentity.sourceFingerprints,
                confirmedEntityReferences: orderedIds.map { .debt($0) }
            )
            _ = try await repository.upsert(provenance)
            return nil
        } catch {
            return "扫描来源记录未能保存，不影响已保存的债务"
        }
    }

    private func rollbackRegisteredMedia(imageIds: [String], userId: UUID) async {
        guard let media else { return }
        for imageId in imageIds {
            try? await media.deleteImage(imageId: imageId, userId: userId)
        }
    }

    private func finalizeRecognitionRecords(userId: UUID) async {
        guard let recognitionRecords, let media else { return }
        let records = (try? await recognitionRecords.fetchAll(userId: userId)) ?? []
        for var record in records where record.kind == .debtScan && record.status == .recognized {
            if let imageId = record.sourceImageId {
                try? await media.markProcessedAndMaybePurge(imageId: imageId, userId: userId)
            }
            record.status = .confirmed
            record.completedAt = Date()
            try? await recognitionRecords.upsert(record)
        }
    }

    public func acceptPrivacy(userId: UUID) async throws {
        guard let consentService else { return }
        _ = try await consentService.acceptDebtScanPrivacy(userId: userId)
    }

    public func makeCreateInput(
        from candidate: DebtCandidate,
        idempotencyKey: UUID? = nil
    ) throws -> CreateDebtInput {
        let lender = candidate.lender?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !lender.isEmpty else {
            throw DomainError.validationFailed("请填写债权方")
        }

        if let outstanding = candidate.outstandingBalance, outstanding < 0 {
            throw DomainError.validationFailed("剩余总欠款不能为负")
        }

        return CreateDebtInput(
            lender: lender,
            approximateBalance: candidate.outstandingBalance,
            currencyCode: candidate.currencyCode ?? "CNY",
            productName: candidate.productName,
            debtType: candidate.debtType ?? .other,
            originalAmount: candidate.originalAmount,
            currentDue: candidate.currentDue,
            minimumDue: candidate.minimumDue,
            installmentAmount: candidate.installmentAmount,
            paymentFrequency: candidate.installmentAmount != nil ? .monthly : .unknown,
            dueDate: candidate.dueDate,
            remainingInstallments: candidate.remainingInstallments,
            interestRate: candidate.interestRate,
            note: sourceNote(for: candidate),
            status: .active,
            source: .screenshot,
            idempotencyKey: idempotencyKey
        )
    }

    private func sourceNote(for candidate: DebtCandidate) -> String? {
        let docs = candidate.sourceDocuments
        guard !docs.isEmpty else { return "来自 AI 债务扫描（用户已确认）" }
        return "来自 AI 债务扫描，来源：\(docs.joined(separator: "、"))"
    }
}
