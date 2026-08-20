import Foundation
import YoushuFoundation

/// AI 债务扫描编排：扫描 → 校验 → 聚合 →（用户确认后）创建 Debt。
/// AI 输出不得直接入库。
public struct DebtScannerService: Sendable {
    public static let recommendedMinDocuments = 5
    public static let recommendedMaxDocuments = 20

    private let scanner: any DebtScanning
    private let debtService: any DebtManaging
    private let consentService: AIDataConsentService?
    private let media: MediaLifecycleService?
    private let recognitionRecords: (any AIRecognitionRecordRepository)?

    public init(
        scanner: any DebtScanning,
        debtService: any DebtManaging,
        consentService: AIDataConsentService? = nil,
        media: MediaLifecycleService? = nil,
        recognitionRecords: (any AIRecognitionRecordRepository)? = nil
    ) {
        self.scanner = scanner
        self.debtService = debtService
        self.consentService = consentService
        self.media = media
        self.recognitionRecords = recognitionRecords
    }

    /// 批量扫描账单文档，返回聚合后的候选（非正式 Debt）。
    public func scan(documents: [BillDocument], userId: UUID) async throws -> DebtScanResult {
        guard !documents.isEmpty else {
            throw AIRecognitionError.imageUnreadable
        }
        for document in documents where document.data.isEmpty {
            throw AIRecognitionError.imageUnreadable
        }

        var retainOriginal = false
        if let consentService {
            let consent = try await consentService.requireDebtScanImage(userId: userId)
            retainOriginal = consent.retainOriginalImages
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

        var imageIds: [String] = []
        if let media {
            for doc in documents {
                let artifact = try await media.register(
                    data: doc.data,
                    userId: userId,
                    kind: .debtScan,
                    retainOriginal: retainOriginal
                )
                imageIds.append(artifact.id)
            }
        }

        if let recognitionRecords {
            try await recognitionRecords.upsert(
                AIRecognitionRecord(
                    userId: userId,
                    kind: .debtScan,
                    sourceImageId: imageIds.first,
                    status: .recognized,
                    modelName: scanner.name,
                    summaryLabel: "债务账单扫描（\(documents.count)张）"
                )
            )
        }

        let aggregated = DebtCandidateAggregator.aggregate(raw)
        guard !aggregated.isEmpty else {
            throw AIRecognitionError.invalidResponse("未从账单中发现债务，请更换更清晰的截图后重试。")
        }

        let validationWarnings = try DebtCandidateValidator.validateBatch(aggregated)
        warnings.append(contentsOf: validationWarnings)

        return DebtScanResult(
            candidates: aggregated,
            warnings: Array(Set(warnings)).sorted(),
            documentCount: documents.count
        )
    }

    /// 用户确认后的候选才创建正式 Debt。
    public func confirm(
        candidates: [DebtCandidate],
        userId: UUID
    ) async throws -> [Debt] {
        guard !candidates.isEmpty else {
            throw DomainError.validationFailed("没有可确认的债务")
        }

        var created: [Debt] = []
        for candidate in candidates {
            _ = try DebtCandidateValidator.validate(candidate)
            let input = try makeCreateInput(from: candidate)
            let debt = try await debtService.create(input, userId: userId)
            created.append(debt)
        }

        if let recognitionRecords, let media {
            let records = try await recognitionRecords.fetchAll(userId: userId)
            for var record in records where record.kind == .debtScan && record.status == .recognized {
                if let imageId = record.sourceImageId {
                    try? await media.markProcessedAndMaybePurge(imageId: imageId, userId: userId)
                }
                record.status = .confirmed
                record.completedAt = Date()
                try? await recognitionRecords.upsert(record)
            }
        }

        return created
    }

    public func acceptPrivacy(userId: UUID) async throws {
        guard let consentService else { return }
        _ = try await consentService.acceptDebtScanPrivacy(userId: userId)
    }

    public func makeCreateInput(from candidate: DebtCandidate) throws -> CreateDebtInput {
        let lender = candidate.lender?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !lender.isEmpty else {
            throw DomainError.validationFailed("请填写债权方")
        }

        // 正式欠款优先用剩余总欠款；若缺失才回退本期应还（需用户已知晓）。
        let balance = candidate.outstandingBalance ?? candidate.currentDue
        guard let balance, balance >= 0 else {
            throw DomainError.validationFailed("请填写剩余总欠款或本期应还")
        }

        return CreateDebtInput(
            lender: lender,
            approximateBalance: balance,
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
            source: .screenshot
        )
    }

    private func sourceNote(for candidate: DebtCandidate) -> String? {
        let docs = candidate.sourceDocuments
        guard !docs.isEmpty else { return "来自 AI 债务扫描（用户已确认）" }
        return "来自 AI 债务扫描，来源：\(docs.joined(separator: "、"))"
    }
}
