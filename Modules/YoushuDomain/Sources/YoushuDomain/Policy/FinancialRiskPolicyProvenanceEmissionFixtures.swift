import Foundation
import YoushuFoundation

/// Production-like policy inputs for v1 reason-code emission path coverage (offline provenance matrix).
/// Not part of the 29-case evaluation dataset.
public enum FinancialRiskPolicyProvenanceEmissionFixtures {
    public static let monthEndBelowSafeFallbackScenarioID = "month_end_below_safe_fallback"

    /// CF-3b: minimumBalance unavailable, estimatedMonthEndBalance known and below safeBalance.
    public static func monthEndBelowSafeFallbackPolicyInput(
        evaluatedAt: Date = FinancialRiskPolicyVectorInputs.fixedEvaluatedAt
    ) -> FinancialRiskPolicyInput {
        FinancialRiskPolicyInput(
            minimumBalance: .missing(),
            safeBalance: .known(money(2000)),
            estimatedMonthEndBalance: .known(money(500)),
            monthlyIncome: .known(money(5000)),
            monthlyExpense: .known(money(3000)),
            debtPaymentToIncomePercent: .missing,
            debtPressureLevel: nil,
            debtDataState: .knownNoDebt,
            dataCompleteness: FinancialDataCompleteness(
                debt: .known,
                cashFlowProjection: .known,
                income: .known,
                expense: .known,
                requiredUnknownReasonCodes: []
            ),
            evaluatedAt: evaluatedAt
        )
    }

    /// FactPack aligned with `monthEndBelowSafeFallbackPolicyInput` (no minimumBalance registration).
    public static func monthEndBelowSafeFallbackFacts() -> MonthlySummaryFacts {
        MonthlySummaryFacts(
            availableCash: money(1000),
            monthlyIncome: money(5000),
            monthlyExpense: money(3000),
            monthlyDebtPayment: money(0),
            debtPaymentToIncomePercent: nil,
            primaryPressure: "未来现金流风险",
            estimatedMonthEndBalance: money(500),
            safeBalance: money(2000),
            sourceLabels: ["Account", "CashFlow"]
        )
    }

    public static func monthEndBelowSafeFallbackAssessment(
        evaluatedAt: Date = FinancialRiskPolicyVectorInputs.fixedEvaluatedAt
    ) -> FinancialRiskAssessment {
        FinancialRiskPolicyEngine.evaluate(monthEndBelowSafeFallbackPolicyInput(evaluatedAt: evaluatedAt))
    }

    private static func money(_ amount: Decimal, currency: String = "CNY") -> Money {
        Money(amount: amount, currencyCode: currency)
    }
}
