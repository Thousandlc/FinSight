import Foundation
import YoushuFoundation

/// 在不修改 FinancialContextBuilder 的前提下，为 MonthlySummaryFacts 补齐 explanation 引用的确定性金额。
public enum MonthlySummaryFactsEnricher {
    public static func enrich(
        _ facts: MonthlySummaryFacts,
        context: FinancialContext,
        safeBalance: Money
    ) -> MonthlySummaryFacts {
        guard facts.cashFlowRiskExplanation != nil,
              let slice = context.cashFlow30 else {
            return facts
        }
        var copy = facts
        copy.safeBalance = Money(amount: safeBalance.amount, currencyCode: context.currencyCode)
        copy.minimumBalance = slice.minimumBalance
        return copy
    }

    /// Registers `debtPressureLevel` only when full-profile debt inventory is established (`knownDebt`).
    /// Value must come from upstream `DebtCenterCalculator` assembly — never recomputed here.
    public static func enrichDebtPressureProvenance(
        _ facts: MonthlySummaryFacts,
        debtPressureLevel: DebtPressureLevel,
        debtDataState: DebtDataState
    ) -> MonthlySummaryFacts {
        var copy = facts
        switch debtDataState {
        case .knownDebt:
            copy.debtPressureLevel = debtPressureLevel
        case .partial, .knownNoDebt, .missing:
            copy.debtPressureLevel = nil
        }
        return copy
    }
}

extension AssistantAnswerValidator {
    /// 将 MonthlySummaryFacts 转为 AnswerFactPack，供校验与测试复用。
    public static func factPack(from facts: MonthlySummaryFacts) -> AnswerFactPack {
        var factMap: [String: String] = [
            "primaryPressure": facts.primaryPressure,
        ]
        if let pct = facts.debtPaymentToIncomePercent {
            factMap["debtPaymentToIncomePercent"] = normalizedPercentString(pct)
        }
        if let risk = facts.cashFlowRiskExplanation {
            factMap["cashFlowRiskExplanation"] = risk
        }
        if let level = facts.debtPressureLevel {
            factMap["debtPressureLevel"] = level.rawValue
        }
        var amounts: [String: Money] = [
            "availableCash": facts.availableCash,
            "monthlyIncome": facts.monthlyIncome,
            "monthlyExpense": facts.monthlyExpense,
            "monthlyDebtPayment": facts.monthlyDebtPayment,
            "estimatedMonthEndBalance": facts.estimatedMonthEndBalance,
        ]
        if let safeBalance = facts.safeBalance {
            amounts["safeBalance"] = safeBalance
        }
        if let minimumBalance = facts.minimumBalance {
            amounts["minimumBalance"] = minimumBalance
        }
        return AnswerFactPack(
            intent: .unknown,
            facts: factMap,
            amounts: amounts,
            sourceLabels: facts.sourceLabels,
            requiresDisclaimer: false
        )
    }

    private static func normalizedPercentString(_ value: Decimal) -> String {
        var v = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &v, 2, .plain)
        return "\(rounded)"
    }
}
