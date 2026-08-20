import Foundation

/// Product semantics for `FinancialRiskLevel` in FinSight v1.
public enum FinancialRiskLevelSemantics {
    /// Known data scope has no deterministic warning/risk signals.
    /// Does not mean all financial aspects are confirmed safe when data is missing.
    public static let safeSummary = "No deterministic warning/risk signals within known data scope."

    /// Deterministic financial attention needed; no near-term funding gap; no critical debt pressure.
    public static let warningSummary =
        "Deterministic attention signal without near-term funding gap or critical debt pressure."

    /// Near-term funding gap or critical debt pressure from existing engines.
    public static let riskSummary =
        "Deterministic near-term funding gap or critical debt pressure."
}

/// Machine-readable v1 policy rule definition. Specification only — not evaluated here.
public struct FinancialRiskPolicyRule: Equatable, Sendable, Identifiable {
    public var id: String
    public var requiredInputs: [String]
    public var preconditions: [String]
    public var condition: String
    public var outputLevel: FinancialRiskLevel
    public var reasonCode: FinancialRiskReasonCode
    public var sourceFactKeys: [String]
    public var recommendedActions: [FinancialRiskActionDestination]
    public var completenessBehavior: String
    public var suppressionNotes: String?
    public var dedupNotes: String?
    public var forbiddenInference: [String]

    public init(
        id: String,
        requiredInputs: [String],
        preconditions: [String],
        condition: String,
        outputLevel: FinancialRiskLevel,
        reasonCode: FinancialRiskReasonCode,
        sourceFactKeys: [String],
        recommendedActions: [FinancialRiskActionDestination] = [],
        completenessBehavior: String,
        suppressionNotes: String? = nil,
        dedupNotes: String? = nil,
        forbiddenInference: [String] = []
    ) {
        self.id = id
        self.requiredInputs = requiredInputs
        self.preconditions = preconditions
        self.condition = condition
        self.outputLevel = outputLevel
        self.reasonCode = reasonCode
        self.sourceFactKeys = sourceFactKeys
        self.recommendedActions = recommendedActions
        self.completenessBehavior = completenessBehavior
        self.suppressionNotes = suppressionNotes
        self.dedupNotes = dedupNotes
        self.forbiddenInference = forbiddenInference
    }
}

/// Canonical v1 rule catalog for `FinancialRiskPolicyEngine` (P0-4.5.3+).
public enum FinancialRiskPolicySpecification {
    public static let policyVersion = FinancialRiskPolicyVersion.v1

    // MARK: - Cash flow

    public static let cf1NegativeProjectedBalance = FinancialRiskPolicyRule(
        id: "CF-1",
        requiredInputs: ["minimumBalance"],
        preconditions: ["cashFlowProjection.minimumBalance known"],
        condition: "minimumBalance.amount < 0",
        outputLevel: .risk,
        reasonCode: .negativeProjectedBalance,
        sourceFactKeys: ["minimumBalance"],
        recommendedActions: [.cashFlow],
        completenessBehavior: "Requires cashFlowProjection known; missing projection → no CF-1/CF-2 signals.",
        dedupNotes: "Supersedes CF-2 when both conditions true.",
        forbiddenInference: ["predict insolvency", "guarantee default"]
    )

    public static let cf2BelowSafeBalance = FinancialRiskPolicyRule(
        id: "CF-2",
        requiredInputs: ["minimumBalance", "safeBalance"],
        preconditions: [
            "minimumBalance known",
            "safeBalance known as deterministic input (not policy-defined numeric default)",
            "minimumBalance.amount >= 0",
        ],
        condition: "minimumBalance.amount < safeBalance.amount",
        outputLevel: .warning,
        reasonCode: .cashFlowBelowSafeBalance,
        sourceFactKeys: ["minimumBalance", "safeBalance"],
        recommendedActions: [.cashFlow],
        completenessBehavior: "Requires cashFlowProjection known.",
        dedupNotes: "Omitted when CF-1 applies.",
        forbiddenInference: ["minimumBalance < safeBalance does not imply risk in v1"]
    )

    public static let cf3MonthEndFallbackNegative = FinancialRiskPolicyRule(
        id: "CF-3a",
        requiredInputs: ["estimatedMonthEndBalance", "safeBalance"],
        preconditions: [
            "minimumBalance unavailable",
            "estimatedMonthEndBalance known",
        ],
        condition: "estimatedMonthEndBalance.amount < 0",
        outputLevel: .risk,
        reasonCode: .negativeProjectedBalance,
        sourceFactKeys: ["estimatedMonthEndBalance"],
        recommendedActions: [.cashFlow],
        completenessBehavior: "Fallback only when minimumBalance unavailable. Domain facts: MonthlySummaryFacts.estimatedMonthEndBalance + optional minimumBalance — sufficient for v1.",
        dedupNotes: "Do not emit duplicate month-end warning when minimumBalance known.",
        forbiddenInference: []
    )

    public static let cf3MonthEndFallbackBelowSafe = FinancialRiskPolicyRule(
        id: "CF-3b",
        requiredInputs: ["estimatedMonthEndBalance", "safeBalance"],
        preconditions: [
            "minimumBalance unavailable",
            "estimatedMonthEndBalance known",
            "estimatedMonthEndBalance.amount >= 0",
        ],
        condition: "estimatedMonthEndBalance.amount < safeBalance.amount",
        outputLevel: .warning,
        reasonCode: .monthEndBelowSafeBalance,
        sourceFactKeys: ["estimatedMonthEndBalance", "safeBalance"],
        recommendedActions: [.cashFlow],
        completenessBehavior: "Fallback only when minimumBalance unavailable.",
        dedupNotes: "Omitted when CF-3a applies.",
        forbiddenInference: []
    )

    // MARK: - Debt pressure (reuse DebtCenterCalculator)

    public static let debtPressureHigh = FinancialRiskPolicyRule(
        id: "DEBT-P-1",
        requiredInputs: ["DebtPressureLevel"],
        preconditions: [
            "DebtDataState != missing",
            "DebtDataState != knownNoDebt",
            "debtPressureLevel == high",
            "DebtPressureLevel from DebtCenterCalculator (no recomputation)",
        ],
        condition: "debtPressureLevel == high",
        outputLevel: .warning,
        reasonCode: .highDebtPressureScore,
        sourceFactKeys: ["debtPressureLevel"],
        recommendedActions: [.debt, .cashFlow],
        completenessBehavior: "Requires complete/partial debt inventory with score available.",
        suppressionNotes: "Suppressed when DebtDataState.knownNoDebt.",
        dedupNotes: "Primary debt truth when available. Suppresses duplicate DTI warning (see DEDUP-2).",
        forbiddenInference: ["infer totalDebt when unavailable"]
    )

    public static let debtPressureCritical = FinancialRiskPolicyRule(
        id: "DEBT-P-2",
        requiredInputs: ["DebtPressureLevel"],
        preconditions: [
            "DebtDataState != missing",
            "DebtDataState != knownNoDebt",
            "debtPressureLevel == critical",
        ],
        condition: "debtPressureLevel == critical",
        outputLevel: .risk,
        reasonCode: .criticalDebtPressure,
        sourceFactKeys: ["debtPressureLevel"],
        recommendedActions: [.debt, .cashFlow],
        completenessBehavior: "Requires debt pressure from existing engine.",
        suppressionNotes: "Suppressed when DebtDataState.knownNoDebt.",
        dedupNotes: "Supersedes DEBT-P-1 and duplicate DTI warnings.",
        forbiddenInference: []
    )

    // MARK: - DTI

    public static let dtiWarning = FinancialRiskPolicyRule(
        id: "DTI-1",
        requiredInputs: ["debtPaymentToIncomePercent", "monthlyIncome"],
        preconditions: [
            "monthlyIncome.amount > 0",
            "debtPaymentToIncomePercent known",
            "DebtDataState != missing",
            "DebtDataState != knownNoDebt",
        ],
        condition: "debtPaymentToIncomePercent >= 20 (product v1 threshold)",
        outputLevel: .warning,
        reasonCode: .highDebtPaymentToIncome,
        sourceFactKeys: ["debtPaymentToIncomePercent"],
        recommendedActions: [.debt, .cashFlow],
        completenessBehavior: "Partial debt allowed when DTI computable from known payment + income.",
        suppressionNotes: "Suppressed when DebtDataState.knownNoDebt.",
        dedupNotes: "Omitted when DEBT-P-1 or DEBT-P-2 already emitted (supporting fact only).",
        forbiddenInference: [
            "regulatory DTI standard",
            "DTI alone produces risk in v1",
        ]
    )

    // MARK: - Income / expense

    public static let zeroIncomeWithExpenses = FinancialRiskPolicyRule(
        id: "IE-1",
        requiredInputs: ["monthlyIncome", "monthlyExpense"],
        preconditions: [
            "income availability == known",
            "expense availability == known",
        ],
        condition: "monthlyIncome.amount == 0 AND monthlyExpense.amount > 0",
        outputLevel: .warning,
        reasonCode: .zeroIncomeWithExpenses,
        sourceFactKeys: ["monthlyIncome", "monthlyExpense"],
        recommendedActions: [.transactions, .cashFlow],
        completenessBehavior: "Does not elevate severity when data missing.",
        forbiddenInference: [
            "unemployment",
            "job loss",
            "income permanently stopped",
            "cannot repay debt",
        ]
    )

    // MARK: - Completeness-only (no risk signals)

    public static let missingDebtCompleteness = FinancialRiskPolicyRule(
        id: "DATA-DEBT-MISSING",
        requiredInputs: ["DebtDataState"],
        preconditions: ["DebtDataState == missing"],
        condition: "DebtDataState == missing",
        outputLevel: .safe,
        reasonCode: .debtDataMissing,
        sourceFactKeys: [],
        recommendedActions: [],
        completenessBehavior: "FinancialDataCompleteness.debt = missing; requiredUnknownReasonCodes includes debtDataMissing. No debt risk signals.",
        forbiddenInference: ["no debt", "low debt", "high debt", "DTI", "repayment burden"]
    )

    public static let missingCashFlowCompleteness = FinancialRiskPolicyRule(
        id: "DATA-CF-MISSING",
        requiredInputs: ["cashFlowProjection availability"],
        preconditions: ["cashFlowProjection unavailable"],
        condition: "cashFlowProjection missing",
        outputLevel: .safe,
        reasonCode: .cashFlowProjectionMissing,
        sourceFactKeys: [],
        recommendedActions: [],
        completenessBehavior: "No CF-1/CF-2/CF-3 signals. requiredUnknownReasonCodes may include cashFlowProjectionMissing when future cash-flow conclusion required.",
        forbiddenInference: ["negativeProjectedBalance", "cashFlowBelowSafeBalance"]
    )

    // MARK: - Catalog

    public static let allRules: [FinancialRiskPolicyRule] = [
        cf1NegativeProjectedBalance,
        cf2BelowSafeBalance,
        cf3MonthEndFallbackNegative,
        cf3MonthEndFallbackBelowSafe,
        debtPressureHigh,
        debtPressureCritical,
        dtiWarning,
        zeroIncomeWithExpenses,
        missingDebtCompleteness,
        missingCashFlowCompleteness,
    ]

    public static let signalEmittingRules: [FinancialRiskPolicyRule] = allRules.filter {
        !$0.sourceFactKeys.isEmpty && !$0.reasonCode.isCompletenessOnly
    }

    /// Reason codes that v1 policy rules may emit as transport signals (derived from catalog).
    public static var v1EmittedSignalReasonCodes: Set<FinancialRiskReasonCode> {
        Set(signalEmittingRules.map(\.reasonCode))
    }

    /// Stable raw values for cross-language contract metadata (Gateway policyVersion validation).
    public static var v1EmittedSignalReasonCodeRawValues: [String] {
        v1EmittedSignalReasonCodes.map(\.rawValue).sorted()
    }
}

private extension FinancialRiskReasonCode {
    var isCompletenessOnly: Bool {
        switch self {
        case .debtDataMissing, .debtDataPartial, .cashFlowProjectionMissing, .budgetNotApplicable:
            return true
        default:
            return false
        }
    }
}
