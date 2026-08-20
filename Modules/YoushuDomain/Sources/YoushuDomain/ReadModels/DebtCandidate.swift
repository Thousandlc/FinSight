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

/// 扫描阶段结果：候选已聚合，但仍非正式 Debt。
public struct DebtScanResult: Sendable, Equatable {
    public var candidates: [DebtCandidate]
    public var warnings: [String]
    public var documentCount: Int

    public init(candidates: [DebtCandidate], warnings: [String] = [], documentCount: Int) {
        self.candidates = candidates
        self.warnings = warnings
        self.documentCount = documentCount
    }
}

/// 用户确认页上的可编辑候选（与 AI 原始结果分离）。
public struct ReviewableDebtCandidate: Identifiable, Sendable, Equatable {
    public var id: UUID
    public var aiCandidate: DebtCandidate
    public var editable: DebtCandidate
    public var isIgnored: Bool

    public init(from candidate: DebtCandidate) {
        self.id = candidate.id
        self.aiCandidate = candidate
        self.editable = candidate
        self.isIgnored = false
    }
}

/// 兼容旧命名：DebtDraft 视为精简候选。
public typealias DebtDraft = DebtCandidate
