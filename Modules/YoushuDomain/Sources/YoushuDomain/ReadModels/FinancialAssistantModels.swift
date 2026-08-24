import Foundation
import YoushuFoundation

/// 授权给 AI 的最小化财务 Context。AI 不得直连数据库。
public struct FinancialContext: Equatable, Sendable {
    public var availableCash: Money
    public var monthlyIncome: Money
    public var monthlyExpense: Money
    public var monthlyDebtPayment: Money
    public var estimatedMonthEndBalance: Money
    public var totalDebt: Money
    public var totalDebtAvailability: FieldAvailability
    public var estimatedMonthlyRepayment: Money
    public var estimatedMonthlyRepaymentAvailability: FieldAvailability
    public var estimatedDebtFreeDate: Date?
    public var financialHealthScore: Int?
    public var debtPaymentToIncomePercent: Decimal?
    public var topExpenseCategories: [CategoryAmount]
    public var cashFlow30: CashFlowContextSlice?
    public var recentRisks: [String]
    public var goals: [GoalContextSlice]
    public var budgets: [BudgetContextSlice]
    public var totalAssets: Money?
    public var hasAccounts: Bool
    public var hasTransactions: Bool
    public var hasDebts: Bool
    public var dataNotes: [String]
    public var asOf: Date
    public var currencyCode: String

    public var isDataInsufficient: Bool {
        !hasAccounts && !hasTransactions
    }

    public init(
        availableCash: Money = .zeroCNY,
        monthlyIncome: Money = .zeroCNY,
        monthlyExpense: Money = .zeroCNY,
        monthlyDebtPayment: Money = .zeroCNY,
        estimatedMonthEndBalance: Money = .zeroCNY,
        totalDebt: Money = .zeroCNY,
        totalDebtAvailability: FieldAvailability = .known,
        estimatedMonthlyRepayment: Money = .zeroCNY,
        estimatedMonthlyRepaymentAvailability: FieldAvailability = .known,
        estimatedDebtFreeDate: Date? = nil,
        financialHealthScore: Int? = nil,
        debtPaymentToIncomePercent: Decimal? = nil,
        topExpenseCategories: [CategoryAmount] = [],
        cashFlow30: CashFlowContextSlice? = nil,
        recentRisks: [String] = [],
        goals: [GoalContextSlice] = [],
        budgets: [BudgetContextSlice] = [],
        totalAssets: Money? = nil,
        hasAccounts: Bool = false,
        hasTransactions: Bool = false,
        hasDebts: Bool = false,
        dataNotes: [String] = [],
        asOf: Date = Date(),
        currencyCode: String = "CNY"
    ) {
        self.availableCash = availableCash
        self.monthlyIncome = monthlyIncome
        self.monthlyExpense = monthlyExpense
        self.monthlyDebtPayment = monthlyDebtPayment
        self.estimatedMonthEndBalance = estimatedMonthEndBalance
        self.totalDebt = totalDebt
        self.totalDebtAvailability = totalDebtAvailability
        self.estimatedMonthlyRepayment = estimatedMonthlyRepayment
        self.estimatedMonthlyRepaymentAvailability = estimatedMonthlyRepaymentAvailability
        self.estimatedDebtFreeDate = estimatedDebtFreeDate
        self.financialHealthScore = financialHealthScore
        self.debtPaymentToIncomePercent = debtPaymentToIncomePercent
        self.topExpenseCategories = topExpenseCategories
        self.cashFlow30 = cashFlow30
        self.recentRisks = recentRisks
        self.goals = goals
        self.budgets = budgets
        self.totalAssets = totalAssets
        self.hasAccounts = hasAccounts
        self.hasTransactions = hasTransactions
        self.hasDebts = hasDebts
        self.dataNotes = dataNotes
        self.asOf = asOf
        self.currencyCode = currencyCode
    }
}

public struct CategoryAmount: Equatable, Sendable {
    public var category: String
    public var amount: Money

    public init(category: String, amount: Money) {
        self.category = category
        self.amount = amount
    }
}

public struct CashFlowContextSlice: Equatable, Sendable {
    public var endingBalance: Money
    public var minimumBalance: Money
    public var minimumBalanceDate: Date
    public var isBelowSafeBalance: Bool
    public var peakRepayment: Money?
    public var explanation: String?

    public init(
        endingBalance: Money,
        minimumBalance: Money,
        minimumBalanceDate: Date,
        isBelowSafeBalance: Bool,
        peakRepayment: Money? = nil,
        explanation: String? = nil
    ) {
        self.endingBalance = endingBalance
        self.minimumBalance = minimumBalance
        self.minimumBalanceDate = minimumBalanceDate
        self.isBelowSafeBalance = isBelowSafeBalance
        self.peakRepayment = peakRepayment
        self.explanation = explanation
    }
}

public struct GoalContextSlice: Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var type: GoalType
    public var targetAmount: Money
    public var currentAmount: Money
    public var remainingAmount: Money
    public var progressPercent: Decimal
    public var targetDate: Date?

    public init(
        id: UUID,
        name: String,
        type: GoalType,
        targetAmount: Money,
        currentAmount: Money,
        remainingAmount: Money,
        progressPercent: Decimal,
        targetDate: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.targetAmount = targetAmount
        self.currentAmount = currentAmount
        self.remainingAmount = remainingAmount
        self.progressPercent = progressPercent
        self.targetDate = targetDate
    }
}

public struct BudgetContextSlice: Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var category: String?
    public var limit: Money
    public var spent: Money
    public var remaining: Money

    public init(
        id: UUID,
        name: String,
        category: String? = nil,
        limit: Money,
        spent: Money,
        remaining: Money
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.limit = limit
        self.spent = spent
        self.remaining = remaining
    }
}

/// AI 回答草稿。必须经 Validator；禁止直接写库。
public struct AssistantAnswerDraft: Equatable, Sendable {
    public var title: String
    public var body: String
    /// 面向用户的自然语言正文；默认与 body 同步，Validator 优先校验此字段。
    public var answer: String
    public var citedFactKeys: [String]
    public var disclaimer: String?
    public var unknowns: [String]
    public var confidence: Double
    public var keyFacts: [AssistantKeyFact]
    public var warnings: [AssistantWarning]
    public var actions: [AssistantAction]
    public var references: [AssistantReference]

    public init(
        title: String,
        body: String,
        answer: String? = nil,
        citedFactKeys: [String] = [],
        disclaimer: String? = nil,
        unknowns: [String] = [],
        confidence: Double = 0.8,
        keyFacts: [AssistantKeyFact] = [],
        warnings: [AssistantWarning] = [],
        actions: [AssistantAction] = [],
        references: [AssistantReference] = []
    ) {
        self.title = title
        self.body = body
        self.answer = answer ?? body
        self.citedFactKeys = citedFactKeys
        self.disclaimer = disclaimer
        self.unknowns = unknowns
        self.confidence = min(max(confidence, 0), 1)
        self.keyFacts = keyFacts
        self.warnings = warnings
        self.actions = actions
        self.references = references
    }

    public var structured: AssistantStructuredAnswer {
        AssistantStructuredAnswer(
            answer: answer,
            keyFacts: keyFacts,
            warnings: warnings,
            actions: actions,
            references: references
        )
    }
}

/// 面向用户的助手回答（已校验）。
public struct AssistantAnswer: Equatable, Sendable, Identifiable {
    public let id: UUID
    public var userId: UUID
    public var question: String
    public var intent: FinancialQuestionIntent
    public var title: String
    public var body: String
    /// 结构化自然语言正文；UI 可逐步迁移到此字段。
    public var answer: String
    public var disclaimer: String?
    public var factSources: [String]
    public var unknowns: [String]
    public var modelName: String?
    public var generatedAt: Date
    public var keyFacts: [AssistantKeyFact]
    public var warnings: [AssistantWarning]
    public var actions: [AssistantAction]
    public var references: [AssistantReference]

    public init(
        id: UUID = UUID(),
        userId: UUID,
        question: String,
        intent: FinancialQuestionIntent,
        title: String,
        body: String,
        answer: String? = nil,
        disclaimer: String? = nil,
        factSources: [String] = [],
        unknowns: [String] = [],
        modelName: String? = nil,
        generatedAt: Date = Date(),
        keyFacts: [AssistantKeyFact] = [],
        warnings: [AssistantWarning] = [],
        actions: [AssistantAction] = [],
        references: [AssistantReference] = []
    ) {
        self.id = id
        self.userId = userId
        self.question = question
        self.intent = intent
        self.title = title
        self.body = body
        self.answer = answer ?? body
        self.disclaimer = disclaimer
        self.factSources = factSources
        self.unknowns = unknowns
        self.modelName = modelName
        self.generatedAt = generatedAt
        self.keyFacts = keyFacts
        self.warnings = warnings
        self.actions = actions
        self.references = references
    }

    public var structured: AssistantStructuredAnswer {
        AssistantStructuredAnswer(
            answer: answer,
            keyFacts: keyFacts,
            warnings: warnings,
            actions: actions,
            references: references
        )
    }
}

public enum FinancialQuestionIntent: String, Codable, Sendable, Equatable, CaseIterable {
    case availableCash
    case totalDebt
    case spendingBreakdown
    case debtFreeDate
    case monthlySavings
    case purchaseAffordability
    case unknown
}

/// 确定性事实包：金额全部由引擎填写，AI 只可引用不可改算。
public struct AnswerFactPack: Equatable, Sendable {
    public var intent: FinancialQuestionIntent
    public var facts: [String: String]
    public var amounts: [String: Money]
    public var sourceLabels: [String]
    public var unknowns: [String]
    public var requiresDisclaimer: Bool
    public var dataInsufficient: Bool

    public init(
        intent: FinancialQuestionIntent,
        facts: [String: String] = [:],
        amounts: [String: Money] = [:],
        sourceLabels: [String] = [],
        unknowns: [String] = [],
        requiresDisclaimer: Bool = false,
        dataInsufficient: Bool = false
    ) {
        self.intent = intent
        self.facts = facts
        self.amounts = amounts
        self.sourceLabels = sourceLabels
        self.unknowns = unknowns
        self.requiresDisclaimer = requiresDisclaimer
        self.dataInsufficient = dataInsufficient
    }
}

public struct MonthlySummaryFacts: Equatable, Sendable {
    public var availableCash: Money
    public var monthlyIncome: Money
    public var monthlyExpense: Money
    public var monthlyDebtPayment: Money
    public var debtPaymentToIncomePercent: Decimal?
    public var primaryPressure: String
    public var estimatedMonthEndBalance: Money
    public var cashFlowRiskExplanation: String?
    /// 当存在现金流风险说明时，与 explanation 中的安全余额阈值一致。
    public var safeBalance: Money?
    /// 当存在现金流风险说明时，与 explanation 中的最低余额一致。
    public var minimumBalance: Money?
    /// Deterministic derived semantic fact from `DebtCenterCalculator` (machine-readable raw value).
    public var debtPressureLevel: DebtPressureLevel?
    public var sourceLabels: [String]

    public init(
        availableCash: Money,
        monthlyIncome: Money,
        monthlyExpense: Money,
        monthlyDebtPayment: Money,
        debtPaymentToIncomePercent: Decimal?,
        primaryPressure: String,
        estimatedMonthEndBalance: Money,
        cashFlowRiskExplanation: String? = nil,
        safeBalance: Money? = nil,
        minimumBalance: Money? = nil,
        debtPressureLevel: DebtPressureLevel? = nil,
        sourceLabels: [String] = []
    ) {
        self.availableCash = availableCash
        self.monthlyIncome = monthlyIncome
        self.monthlyExpense = monthlyExpense
        self.monthlyDebtPayment = monthlyDebtPayment
        self.debtPaymentToIncomePercent = debtPaymentToIncomePercent
        self.primaryPressure = primaryPressure
        self.estimatedMonthEndBalance = estimatedMonthEndBalance
        self.cashFlowRiskExplanation = cashFlowRiskExplanation
        self.safeBalance = safeBalance
        self.minimumBalance = minimumBalance
        self.debtPressureLevel = debtPressureLevel
        self.sourceLabels = sourceLabels
    }
}

public struct InsightFactPack: Equatable, Sendable {
    public var type: InsightType
    public var titleHint: String
    public var facts: [String: String]
    public var amounts: [String: Money]
    public var sourceTransactionIds: [UUID]
    public var sourceDebtIds: [UUID]
    public var sourceAccountIds: [UUID]
    public var sourceLabels: [String]

    public init(
        type: InsightType,
        titleHint: String,
        facts: [String: String] = [:],
        amounts: [String: Money] = [:],
        sourceTransactionIds: [UUID] = [],
        sourceDebtIds: [UUID] = [],
        sourceAccountIds: [UUID] = [],
        sourceLabels: [String] = []
    ) {
        self.type = type
        self.titleHint = titleHint
        self.facts = facts
        self.amounts = amounts
        self.sourceTransactionIds = sourceTransactionIds
        self.sourceDebtIds = sourceDebtIds
        self.sourceAccountIds = sourceAccountIds
        self.sourceLabels = sourceLabels
    }
}

public enum PurchaseAffordability: String, Sendable, Equatable {
    case affordable
    case caution
    case notRecommended
}

/// 消费决策场景：确定性计算结果。
public struct PurchaseScenario: Equatable, Sendable {
    public var purchaseAmount: Money
    public var currentCash: Money
    public var cashAfterPurchase: Money
    public var safetyReserve: Money
    public var breachesSafetyReserve: Bool
    public var projectedMinimumBalance: Money?
    public var projectedMinimumDate: Date?
    public var futureIncome: Money
    public var fixedExpenses: Money
    public var debtPayments: Money
    public var goalImpact: String?
    public var affordability: PurchaseAffordability
    public var factPack: AnswerFactPack

    public init(
        purchaseAmount: Money,
        currentCash: Money,
        cashAfterPurchase: Money,
        safetyReserve: Money,
        breachesSafetyReserve: Bool,
        projectedMinimumBalance: Money? = nil,
        projectedMinimumDate: Date? = nil,
        futureIncome: Money,
        fixedExpenses: Money,
        debtPayments: Money,
        goalImpact: String? = nil,
        affordability: PurchaseAffordability,
        factPack: AnswerFactPack
    ) {
        self.purchaseAmount = purchaseAmount
        self.currentCash = currentCash
        self.cashAfterPurchase = cashAfterPurchase
        self.safetyReserve = safetyReserve
        self.breachesSafetyReserve = breachesSafetyReserve
        self.projectedMinimumBalance = projectedMinimumBalance
        self.projectedMinimumDate = projectedMinimumDate
        self.futureIncome = futureIncome
        self.fixedExpenses = fixedExpenses
        self.debtPayments = debtPayments
        self.goalImpact = goalImpact
        self.affordability = affordability
        self.factPack = factPack
    }
}
