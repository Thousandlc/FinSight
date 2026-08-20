import Foundation
import YoushuFoundation

/// 现金流预测时间范围（天）。
public enum CashFlowHorizon: Int, CaseIterable, Sendable, Equatable {
    case days7 = 7
    case days30 = 30
    case days60 = 60
    case days90 = 90
}

/// 单日确定性现金流驱动因素（供解释与风险分析，非 AI 编造）。
public struct CashFlowDriver: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable, Equatable {
        case historicalIncome
        case historicalExpense
        case fixedExpense
        case recurringExpense
        case debtRepayment
        case knownFutureIncome
    }

    public let id: UUID
    public var date: Date
    public var amount: Money
    /// 对可用资金的符号：收入为正，支出/还款为负。
    public var signedAmount: Money
    public var kind: Kind
    public var label: String
    public var debtId: UUID?
    public var transactionId: UUID?

    public init(
        id: UUID = UUID(),
        date: Date,
        amount: Money,
        signedAmount: Money,
        kind: Kind,
        label: String,
        debtId: UUID? = nil,
        transactionId: UUID? = nil
    ) {
        self.id = id
        self.date = date
        self.amount = amount
        self.signedAmount = signedAmount
        self.kind = kind
        self.label = label
        self.debtId = debtId
        self.transactionId = transactionId
    }
}

/// 确定性解释素材：数字与原因均来自引擎，文案可由 AI 润色。
public struct CashFlowExplanationFacts: Equatable, Sendable {
    public var minimumBalance: Money
    public var minimumBalanceDate: Date
    public var majorDrivers: [CashFlowDriver]
    public var safeBalance: Money
    public var isBelowSafeBalance: Bool

    public init(
        minimumBalance: Money,
        minimumBalanceDate: Date,
        majorDrivers: [CashFlowDriver],
        safeBalance: Money,
        isBelowSafeBalance: Bool
    ) {
        self.minimumBalance = minimumBalance
        self.minimumBalanceDate = minimumBalanceDate
        self.majorDrivers = majorDrivers
        self.safeBalance = safeBalance
        self.isBelowSafeBalance = isBelowSafeBalance
    }
}

/// 低于安全余额时的现金流风险。
public struct CashFlowRisk: Equatable, Sendable {
    public var minimumBalance: Money
    public var minimumBalanceDate: Date
    public var peakRepayment: Money?
    public var peakRepaymentDate: Date?
    public var safeBalance: Money
    public var drivers: [CashFlowDriver]
    public var explanationFacts: CashFlowExplanationFacts

    public init(
        minimumBalance: Money,
        minimumBalanceDate: Date,
        peakRepayment: Money?,
        peakRepaymentDate: Date?,
        safeBalance: Money,
        drivers: [CashFlowDriver],
        explanationFacts: CashFlowExplanationFacts
    ) {
        self.minimumBalance = minimumBalance
        self.minimumBalanceDate = minimumBalanceDate
        self.peakRepayment = peakRepayment
        self.peakRepaymentDate = peakRepaymentDate
        self.safeBalance = safeBalance
        self.drivers = drivers
        self.explanationFacts = explanationFacts
    }
}

/// 某一时间范围的现金流预测结果。
public struct CashFlowProjection: Equatable, Sendable {
    public var horizon: CashFlowHorizon
    public var startingBalance: Money
    public var endingBalance: Money
    public var minimumBalance: Money
    public var minimumBalanceDate: Date
    public var peakRepayment: Money?
    public var peakRepaymentDate: Date?
    public var drivers: [CashFlowDriver]
    public var risk: CashFlowRisk?

    public init(
        horizon: CashFlowHorizon,
        startingBalance: Money,
        endingBalance: Money,
        minimumBalance: Money,
        minimumBalanceDate: Date,
        peakRepayment: Money? = nil,
        peakRepaymentDate: Date? = nil,
        drivers: [CashFlowDriver] = [],
        risk: CashFlowRisk? = nil
    ) {
        self.horizon = horizon
        self.startingBalance = startingBalance
        self.endingBalance = endingBalance
        self.minimumBalance = minimumBalance
        self.minimumBalanceDate = minimumBalanceDate
        self.peakRepayment = peakRepayment
        self.peakRepaymentDate = peakRepaymentDate
        self.drivers = drivers
        self.risk = risk
    }
}

/// 首页财务汇总（确定性引擎输出）。
public struct FinancialSummary: Equatable, Sendable {
    public var availableCash: Money
    public var monthlyIncome: Money
    public var monthlyExpense: Money
    public var monthlyDebtPayment: Money
    public var estimatedMonthEndBalance: Money
    public var financialHealthScore: Int?

    public init(
        availableCash: Money = .zeroCNY,
        monthlyIncome: Money = .zeroCNY,
        monthlyExpense: Money = .zeroCNY,
        monthlyDebtPayment: Money = .zeroCNY,
        estimatedMonthEndBalance: Money = .zeroCNY,
        financialHealthScore: Int? = nil
    ) {
        self.availableCash = availableCash
        self.monthlyIncome = monthlyIncome
        self.monthlyExpense = monthlyExpense
        self.monthlyDebtPayment = monthlyDebtPayment
        self.estimatedMonthEndBalance = estimatedMonthEndBalance
        self.financialHealthScore = financialHealthScore
    }
}
