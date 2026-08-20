import Foundation
import YoushuDomain
import YoushuFoundation

public enum GatewayMonthlySummaryFactsMapper {
    public static func toDTO(_ facts: MonthlySummaryFacts) -> GatewayMonthlySummaryFactsDTO {
        GatewayMonthlySummaryFactsDTO(
            availableCash: moneyDTO(facts.availableCash),
            monthlyIncome: moneyDTO(facts.monthlyIncome),
            monthlyExpense: moneyDTO(facts.monthlyExpense),
            monthlyDebtPayment: moneyDTO(facts.monthlyDebtPayment),
            debtPaymentToIncomePercent: facts.debtPaymentToIncomePercent.map(normalizedDecimal),
            primaryPressure: facts.primaryPressure,
            estimatedMonthEndBalance: moneyDTO(facts.estimatedMonthEndBalance),
            cashFlowRiskExplanation: facts.cashFlowRiskExplanation,
            safeBalance: facts.safeBalance.map(moneyDTO),
            minimumBalance: facts.minimumBalance.map(moneyDTO),
            debtPressureLevel: facts.debtPressureLevel?.rawValue,
            sourceLabels: facts.sourceLabels
        )
    }

    private static func moneyDTO(_ money: Money) -> GatewayMoneyDTO {
        GatewayMoneyDTO(amount: normalizedDecimal(money.amount), currencyCode: money.currencyCode)
    }

    private static func normalizedDecimal(_ value: Decimal) -> String {
        var v = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &v, 2, .plain)
        return "\(rounded)"
    }
}
