import Foundation
import YoushuFoundation

/// AI 债务扫描输出的候选 DTO。禁止直接写入正式 Debt。
///
/// 金额字段必须严格区分，禁止把「本期应还」当成「剩余总欠款」。
public struct DebtCandidate: Identifiable, Sendable, Hashable, Codable, Equatable {
    public var id: UUID
    public var lender: String?
    public var productName: String?
    public var debtType: DebtType?
    /// 剩余总欠款（不是本期账单）。
    public var outstandingBalance: Decimal?
    /// 本期应还。
    public var currentDue: Decimal?
    /// 最低还款。
    public var minimumDue: Decimal?
    /// 每期金额（分期）。
    public var installmentAmount: Decimal?
    /// 原始借款/授信金额。
    public var originalAmount: Decimal?
    public var dueDate: Date?
    public var remainingInstallments: Int?
    /// 无法确定时必须为 nil，禁止臆造。
    public var interestRate: Decimal?
    public var currencyCode: String?
    public var confidence: Double?
    public var sourceDocuments: [String]
    public var unknowns: [String]

    public init(
        id: UUID = UUID(),
        lender: String? = nil,
        productName: String? = nil,
        debtType: DebtType? = nil,
        outstandingBalance: Decimal? = nil,
        currentDue: Decimal? = nil,
        minimumDue: Decimal? = nil,
        installmentAmount: Decimal? = nil,
        originalAmount: Decimal? = nil,
        dueDate: Date? = nil,
        remainingInstallments: Int? = nil,
        interestRate: Decimal? = nil,
        currencyCode: String? = "CNY",
        confidence: Double? = nil,
        sourceDocuments: [String] = [],
        unknowns: [String] = []
    ) {
        self.id = id
        self.lender = lender
        self.productName = productName
        self.debtType = debtType
        self.outstandingBalance = outstandingBalance
        self.currentDue = currentDue
        self.minimumDue = minimumDue
        self.installmentAmount = installmentAmount
        self.originalAmount = originalAmount
        self.dueDate = dueDate
        self.remainingInstallments = remainingInstallments
        self.interestRate = interestRate
        self.currencyCode = currencyCode?.uppercased()
        self.confidence = confidence.map { min(max($0, 0), 1) }
        self.sourceDocuments = sourceDocuments
        self.unknowns = unknowns
    }

    public var profileCompletenessPercent: Int {
        DebtProfileCompleteness.percentage(
            for: Debt(
                userId: UUID(),
                lender: lender,
                productName: productName,
                debtType: debtType ?? .other,
                originalAmount: originalAmount.map { Money(amount: $0, currencyCode: currencyCode ?? "CNY") },
                outstandingBalance: outstandingBalance.map { Money(amount: $0, currencyCode: currencyCode ?? "CNY") },
                currentDue: currentDue.map { Money(amount: $0, currencyCode: currencyCode ?? "CNY") },
                minimumDue: minimumDue.map { Money(amount: $0, currencyCode: currencyCode ?? "CNY") },
                installmentAmount: installmentAmount.map { Money(amount: $0, currencyCode: currencyCode ?? "CNY") },
                dueDate: dueDate,
                remainingInstallments: remainingInstallments,
                interestRate: interestRate,
                status: .active,
                source: .screenshot
            )
        )
    }
}

/// Provider 扫描完成、Application 接受前的暂态结果（ADR-036 Step C）。
/// 不表示 MediaArtifact / AIRecognitionRecord 已持久化。
public struct PendingDebtScanResult: Sendable, Equatable {
    public let acceptanceToken: UUID
    public var candidates: [DebtCandidate]
    public var warnings: [String]
    public var documentCount: Int
    public let documents: [BillDocument]
    public let importIdentity: DebtScanImportIdentity

    public init(
        acceptanceToken: UUID = UUID(),
        candidates: [DebtCandidate],
        warnings: [String] = [],
        documentCount: Int,
        documents: [BillDocument],
        importIdentity: DebtScanImportIdentity
    ) {
        self.acceptanceToken = acceptanceToken
        self.candidates = candidates
        self.warnings = warnings
        self.documentCount = documentCount
        self.documents = documents
        self.importIdentity = importIdentity
    }
}

/// Application 接受后进入审核流程的扫描结果；此时 eligible 元数据已持久化。
public struct DebtScanResult: Sendable, Equatable {
    public let acceptanceToken: UUID
    public var candidates: [DebtCandidate]
    public var warnings: [String]
    public var documentCount: Int
    public let importIdentity: DebtScanImportIdentity

    public init(
        acceptanceToken: UUID,
        candidates: [DebtCandidate],
        warnings: [String] = [],
        documentCount: Int,
        importIdentity: DebtScanImportIdentity
    ) {
        self.acceptanceToken = acceptanceToken
        self.candidates = candidates
        self.warnings = warnings
        self.documentCount = documentCount
        self.importIdentity = importIdentity
    }
}

/// 用户确认页上的可编辑候选（与 AI 原始结果分离）。
public enum ReviewConfirmationState: Equatable, Sendable {
    case unresolved
    case confirmed(debtId: UUID)
    case failed(message: String)
}

public struct ConfirmDebtCandidateInput: Sendable, Equatable {
    public var reviewItemId: UUID
    public var confirmationToken: UUID
    public var candidate: DebtCandidate

    public init(reviewItemId: UUID, confirmationToken: UUID, candidate: DebtCandidate) {
        self.reviewItemId = reviewItemId
        self.confirmationToken = confirmationToken
        self.candidate = candidate
    }
}

public enum DebtScanCandidateConfirmStatus: String, Sendable, Equatable, Codable {
    case succeeded
    case failed
    case notAttempted
}

public struct DebtScanCandidateConfirmResult: Sendable, Equatable {
    public var reviewItemId: UUID
    public var confirmationToken: UUID
    public var status: DebtScanCandidateConfirmStatus
    public var debtId: UUID?
    public var errorMessage: String?

    public init(
        reviewItemId: UUID,
        confirmationToken: UUID,
        status: DebtScanCandidateConfirmStatus,
        debtId: UUID? = nil,
        errorMessage: String? = nil
    ) {
        self.reviewItemId = reviewItemId
        self.confirmationToken = confirmationToken
        self.status = status
        self.debtId = debtId
        self.errorMessage = errorMessage
    }
}

public struct DebtScanConfirmOutcome: Sendable, Equatable {
    public var results: [DebtScanCandidateConfirmResult]
    public var provenanceIssue: String?

    public init(results: [DebtScanCandidateConfirmResult], provenanceIssue: String? = nil) {
        self.results = results
        self.provenanceIssue = provenanceIssue
    }

    public var succeeded: [DebtScanCandidateConfirmResult] {
        results.filter { $0.status == .succeeded }
    }

    public var failed: [DebtScanCandidateConfirmResult] {
        results.filter { $0.status == .failed }
    }

    public var notAttempted: [DebtScanCandidateConfirmResult] {
        results.filter { $0.status == .notAttempted }
    }

    public var isFullySuccessful: Bool {
        !results.isEmpty && results.allSatisfy { $0.status == .succeeded }
    }

    public var hasPartialSuccess: Bool {
        succeeded.count > 0 && !isFullySuccessful
    }
}

public struct ReviewableDebtCandidate: Identifiable, Sendable, Equatable {
    public var id: UUID
    public var aiCandidate: DebtCandidate
    public var editable: DebtCandidate
    public var isIgnored: Bool
    public var confirmationToken: UUID
    public var confirmationState: ReviewConfirmationState

    public init(from candidate: DebtCandidate) {
        self.id = candidate.id
        self.aiCandidate = candidate
        self.editable = candidate
        self.isIgnored = false
        self.confirmationToken = UUID()
        self.confirmationState = .unresolved
    }

    public var isConfirmable: Bool {
        guard !isIgnored else { return false }
        if case .confirmed = confirmationState { return false }
        return true
    }
}

/// Edit-state mapping for a DebtCandidate. Unknown optional facts stay unknown
/// unless the user explicitly supplies them (for example enabling due date).
public struct DebtCandidateEditDraft: Equatable, Sendable {
    public var candidate: DebtCandidate
    public var includeDueDate: Bool

    public init(from candidate: DebtCandidate) {
        self.candidate = candidate
        self.includeDueDate = candidate.dueDate != nil
    }

    /// Explicit user action: enable or clear due date. Enabling with a nil date
    /// uses `explicitDate` as the newly chosen value.
    public mutating func setIncludeDueDate(_ include: Bool, explicitDate: Date) {
        includeDueDate = include
        if include {
            if candidate.dueDate == nil {
                candidate.dueDate = explicitDate
            }
        } else {
            candidate.dueDate = nil
        }
    }

    public func finalized() -> DebtCandidate {
        var result = candidate
        if !includeDueDate {
            result.dueDate = nil
        }
        return result
    }
}

/// 兼容旧命名：DebtDraft 视为精简候选。
public typealias DebtDraft = DebtCandidate
