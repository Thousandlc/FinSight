import Foundation
import YoushuFoundation

/// Derived home dashboard snapshot. Values are computed, not authoritative ledger facts.
public struct HomeOverview: Equatable, Sendable {
    public var availableFunds: Money
    public var monthlyIncome: Money
    public var monthlyLivingExpense: Money
    public var monthlyDebtRepayment: Money
    public var projectedMonthEndBalance: Money
    /// 0...100 when enough data exists.
    public var financialHealthScore: Int?
    public var aiSummary: FinancialInsight?
    /// 7/30/60/90 天现金流预测。
    public var cashFlowProjections: [CashFlowProjection]
    /// 主风险（优先取 30 天窗口）。
    public var cashFlowRisk: CashFlowRisk?
    public var hasAccounts: Bool
    public var hasTransactions: Bool

    public var isEmpty: Bool {
        !hasAccounts && !hasTransactions
    }

    public init(
        availableFunds: Money = .zeroCNY,
        monthlyIncome: Money = .zeroCNY,
        monthlyLivingExpense: Money = .zeroCNY,
        monthlyDebtRepayment: Money = .zeroCNY,
        projectedMonthEndBalance: Money = .zeroCNY,
        financialHealthScore: Int? = nil,
        aiSummary: FinancialInsight? = nil,
        cashFlowProjections: [CashFlowProjection] = [],
        cashFlowRisk: CashFlowRisk? = nil,
        hasAccounts: Bool = false,
        hasTransactions: Bool = false
    ) {
        self.availableFunds = availableFunds
        self.monthlyIncome = monthlyIncome
        self.monthlyLivingExpense = monthlyLivingExpense
        self.monthlyDebtRepayment = monthlyDebtRepayment
        self.projectedMonthEndBalance = projectedMonthEndBalance
        self.financialHealthScore = financialHealthScore
        self.aiSummary = aiSummary
        self.cashFlowProjections = cashFlowProjections
        self.cashFlowRisk = cashFlowRisk
        self.hasAccounts = hasAccounts
        self.hasTransactions = hasTransactions
    }
}

public struct TransactionListSnapshot: Equatable, Sendable {
    public var sections: [TransactionDateSection]
    public var monthlyStats: MonthlyStats

    public var isEmpty: Bool {
        sections.allSatisfy { $0.items.isEmpty }
    }

    public init(sections: [TransactionDateSection] = [], monthlyStats: MonthlyStats? = nil) {
        self.sections = sections
        self.monthlyStats = monthlyStats ?? MonthlyStats(income: .zeroCNY, expense: .zeroCNY)
    }
}

public struct AssetListSnapshot: Equatable, Sendable {
    public var assets: [Asset]
    public var totalValue: Money

    public var isEmpty: Bool { assets.isEmpty }

    public init(assets: [Asset] = [], totalValue: Money = .zeroCNY) {
        self.assets = assets
        self.totalValue = totalValue
    }
}

public struct AIAssistantSnapshot: Equatable, Sendable {
    public var recentInsights: [FinancialInsight]
    public var suggestedQuestions: [String]
    public var lastAnswer: AssistantAnswer?

    public var isEmpty: Bool { recentInsights.isEmpty && lastAnswer == nil }

    public init(
        recentInsights: [FinancialInsight] = [],
        suggestedQuestions: [String] = FinancialQuestionRouter.suggestedQuestions,
        lastAnswer: AssistantAnswer? = nil
    ) {
        self.recentInsights = recentInsights
        self.suggestedQuestions = suggestedQuestions
        self.lastAnswer = lastAnswer
    }
}
