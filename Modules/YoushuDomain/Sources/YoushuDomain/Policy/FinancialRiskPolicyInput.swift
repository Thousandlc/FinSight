import Foundation
import YoushuFoundation

/// Explicit availability for a policy money fact. Nil value does not imply missing without `availability`.
public struct PolicyMoneyField: Equatable, Sendable {
    public var availability: FieldAvailability
    public var value: Money?

    public init(availability: FieldAvailability, value: Money? = nil) {
        self.availability = availability
        self.value = value
    }

    public static func known(_ money: Money) -> PolicyMoneyField {
        PolicyMoneyField(availability: .known, value: money)
    }

    public static func missing(currencyCode: String = "CNY") -> PolicyMoneyField {
        PolicyMoneyField(availability: .missing, value: nil)
    }

    public var isKnown: Bool { availability == .known && value != nil }
}

/// Explicit availability for a policy decimal fact (e.g. DTI percent).
public struct PolicyDecimalField: Equatable, Sendable {
    public var availability: FieldAvailability
    public var value: Decimal?

    public init(availability: FieldAvailability, value: Decimal? = nil) {
        self.availability = availability
        self.value = value
    }

    public static func known(_ value: Decimal) -> PolicyDecimalField {
        PolicyDecimalField(availability: .known, value: value)
    }

    public static var missing: PolicyDecimalField {
        PolicyDecimalField(availability: .missing, value: nil)
    }

    public var isKnown: Bool { availability == .known && value != nil }
}

/// Minimal deterministic input for `FinancialRiskPolicyEngine`. Caller supplies semantic truth.
public struct FinancialRiskPolicyInput: Equatable, Sendable {
    public var minimumBalance: PolicyMoneyField
    public var safeBalance: PolicyMoneyField
    public var estimatedMonthEndBalance: PolicyMoneyField
    public var monthlyIncome: PolicyMoneyField
    public var monthlyExpense: PolicyMoneyField
    public var debtPaymentToIncomePercent: PolicyDecimalField
    /// Present only when upstream DebtCenterCalculator produced a level for complete debt inventory.
    public var debtPressureLevel: DebtPressureLevel?
    public var debtDataState: DebtDataState
    public var dataCompleteness: FinancialDataCompleteness
    public var evaluatedAt: Date

    public init(
        minimumBalance: PolicyMoneyField,
        safeBalance: PolicyMoneyField,
        estimatedMonthEndBalance: PolicyMoneyField,
        monthlyIncome: PolicyMoneyField,
        monthlyExpense: PolicyMoneyField,
        debtPaymentToIncomePercent: PolicyDecimalField = .missing,
        debtPressureLevel: DebtPressureLevel? = nil,
        debtDataState: DebtDataState,
        dataCompleteness: FinancialDataCompleteness,
        evaluatedAt: Date
    ) {
        self.minimumBalance = minimumBalance
        self.safeBalance = safeBalance
        self.estimatedMonthEndBalance = estimatedMonthEndBalance
        self.monthlyIncome = monthlyIncome
        self.monthlyExpense = monthlyExpense
        self.debtPaymentToIncomePercent = debtPaymentToIncomePercent
        self.debtPressureLevel = debtPressureLevel
        self.debtDataState = debtDataState
        self.dataCompleteness = dataCompleteness
        self.evaluatedAt = evaluatedAt
    }
}
