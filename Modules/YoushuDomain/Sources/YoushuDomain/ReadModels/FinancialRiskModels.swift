import Foundation
import YoushuFoundation

// MARK: - Financial risk level (Core Domain)

/// Global financial risk severity. Core Domain truth — not an Assistant presentation type.
public enum FinancialRiskLevel: String, Sendable, Equatable, Codable, CaseIterable {
    case safe
    case warning
    case risk

    /// Aggregation order: safe < warning < risk
    public var rank: Int {
        switch self {
        case .safe: return 0
        case .warning: return 1
        case .risk: return 2
        }
    }

    public static func highest(_ levels: [FinancialRiskLevel]) -> FinancialRiskLevel {
        levels.max(by: { $0.rank < $1.rank }) ?? .safe
    }
}

// MARK: - Reason codes (machine-readable, non-localized)

/// Stable reason identifiers for risk signals and completeness unknowns.
/// Rule Engine (future) emits these; AI must not invent new codes without product review.
public enum FinancialRiskReasonCode: String, Sendable, Equatable, Codable, CaseIterable {
    // Cash flow
    case cashFlowBelowSafeBalance
    case negativeProjectedBalance
    case monthEndBelowSafeBalance
    case healthyCashBuffer

    // Debt pressure (suppressed when DebtDataState.knownNoDebt)
    case highDebtPaymentToIncome
    case criticalDebtPaymentToIncome
    case highDebtPressureScore
    case criticalDebtPressure
    case repaymentConcern

    // Income / expense
    case zeroIncomeWithExpenses
    case expenseExceedsIncomeWithLowBuffer

    // Data completeness (for FinancialDataCompleteness — not FinancialRiskSignal aggregation)
    case debtDataMissing
    case debtDataPartial
    case cashFlowProjectionMissing
    case budgetNotApplicable
}

// MARK: - Action destinations (Core Domain)

/// Recommended navigation targets derived from risk policy. Mapped to Assistant layer separately.
public enum FinancialRiskActionDestination: String, Sendable, Equatable, Codable, CaseIterable {
    case cashFlow
    case debt
    case transactions
    case accounts
}

// MARK: - Risk signals

public enum FinancialRiskSignalKind: String, Sendable, Equatable, Codable, CaseIterable {
    case cashFlow
    case debt
    case incomeExpense
}

public struct FinancialRiskSignal: Equatable, Sendable, Identifiable {
    public var id: String
    public var kind: FinancialRiskSignalKind
    public var level: FinancialRiskLevel
    public var reasonCode: FinancialRiskReasonCode
    public var sourceFactKeys: [String]
    public var recommendedActionDestinations: [FinancialRiskActionDestination]

    public init(
        id: String? = nil,
        kind: FinancialRiskSignalKind,
        level: FinancialRiskLevel,
        reasonCode: FinancialRiskReasonCode,
        sourceFactKeys: [String],
        recommendedActionDestinations: [FinancialRiskActionDestination] = []
    ) {
        self.kind = kind
        self.level = level
        self.reasonCode = reasonCode
        self.sourceFactKeys = sourceFactKeys
        self.recommendedActionDestinations = recommendedActionDestinations
        self.id = id ?? Self.makeID(kind: kind, reasonCode: reasonCode, sourceFactKeys: sourceFactKeys)
    }

    public static func makeID(
        kind: FinancialRiskSignalKind,
        reasonCode: FinancialRiskReasonCode,
        sourceFactKeys: [String]
    ) -> String {
        let keys = sourceFactKeys.sorted().joined(separator: ",")
        return "\(kind.rawValue):\(reasonCode.rawValue):\(keys)"
    }

    /// Primary provenance key for UI warning source. Policy defines semantic order as the first entry.
    public var primarySourceFactKey: String {
        sourceFactKeys.first ?? reasonCode.rawValue
    }
}

// MARK: - Data completeness (separate from risk severity)

public enum FieldAvailability: String, Sendable, Equatable, Codable, CaseIterable {
    /// Determinate value present, including known zero.
    case known
    case partial
    case missing
    case notApplicable
}

public struct FinancialDataCompleteness: Equatable, Sendable {
    public var debt: FieldAvailability
    public var cashFlowProjection: FieldAvailability
    public var income: FieldAvailability
    public var expense: FieldAvailability
    /// Machine-readable codes AI should surface in unknowns when data is missing/partial.
    public var requiredUnknownReasonCodes: [FinancialRiskReasonCode]

    public init(
        debt: FieldAvailability,
        cashFlowProjection: FieldAvailability,
        income: FieldAvailability,
        expense: FieldAvailability,
        requiredUnknownReasonCodes: [FinancialRiskReasonCode] = []
    ) {
        self.debt = debt
        self.cashFlowProjection = cashFlowProjection
        self.income = income
        self.expense = expense
        self.requiredUnknownReasonCodes = requiredUnknownReasonCodes
    }
}

// MARK: - Debt semantic state

/// Canonical debt data semantics for risk policy and future semantic validation.
public enum DebtDataState: String, Sendable, Equatable, Codable, CaseIterable {
    /// Authoritative inventory: no open debt and zero outstanding.
    case knownNoDebt
    /// Authoritative inventory with active / resolvable debt profile.
    case knownDebt
    /// Some debt-related facts exist but inventory or profile is incomplete.
    case partial
    /// Debt inventory not authoritative or unavailable.
    case missing
}

// MARK: - Assessment

public struct FinancialRiskAssessment: Equatable, Sendable {
    public var overallLevel: FinancialRiskLevel
    public var signals: [FinancialRiskSignal]
    public var dataCompleteness: FinancialDataCompleteness
    public var debtDataState: DebtDataState
    public var policyVersion: String
    /// Injected by caller; pure domain assembly must not call Date() internally.
    public var evaluatedAt: Date

    public init(
        overallLevel: FinancialRiskLevel,
        signals: [FinancialRiskSignal],
        dataCompleteness: FinancialDataCompleteness,
        debtDataState: DebtDataState,
        policyVersion: String,
        evaluatedAt: Date
    ) {
        self.overallLevel = overallLevel
        self.signals = signals
        self.dataCompleteness = dataCompleteness
        self.debtDataState = debtDataState
        self.policyVersion = policyVersion
        self.evaluatedAt = evaluatedAt
    }
}
