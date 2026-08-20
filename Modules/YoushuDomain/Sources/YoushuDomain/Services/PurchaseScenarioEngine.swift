import Foundation
import YoushuFoundation

/// 消费决策场景：确定性计算。AI 只负责解释结果。
public enum PurchaseScenarioEngine {
    public static func evaluate(
        purchaseAmount: Money,
        context: FinancialContext,
        safetyReserve: Money? = nil
    ) -> PurchaseScenario {
        let currency = context.currencyCode
        let amount = Money(amount: purchaseAmount.amount, currencyCode: currency)
        let cash = context.availableCash
        let reserve = safetyReserve.map { Money(amount: $0.amount, currencyCode: currency) }
            ?? Money(amount: 2_000, currencyCode: currency)
        let cashAfter = Money(amount: cash.amount - amount.amount, currencyCode: currency)
        let breaches = cashAfter.amount < reserve.amount

        let futureIncome = context.monthlyIncome
        let fixedExpenses = context.monthlyExpense
        let debtPayments = context.estimatedMonthlyRepayment.amount > 0
            ? context.estimatedMonthlyRepayment
            : context.monthlyDebtPayment

        var projectedMin = context.cashFlow30.map {
            Money(amount: $0.minimumBalance.amount - amount.amount, currencyCode: currency)
        }
        var projectedMinDate = context.cashFlow30?.minimumBalanceDate

        // 若当前扣款后已低于预测最低点，以扣款后现金为准
        if let min = projectedMin, cashAfter.amount < min.amount {
            projectedMin = cashAfter
            projectedMinDate = context.asOf
        }

        var goalImpact: String?
        if let goal = context.goals.first(where: { $0.remainingAmount.amount > 0 }) {
            if cashAfter.amount < goal.remainingAmount.amount {
                goalImpact = "购买后可用资金低于目标「\(goal.name)」剩余需储金额"
            } else {
                goalImpact = "购买后仍可能覆盖目标「\(goal.name)」当前剩余需储（未考虑后续固定支出）"
            }
        }

        let affordability: PurchaseAffordability
        if amount.amount > cash.amount {
            affordability = .notRecommended
        } else if breaches || (projectedMin?.amount ?? cashAfter.amount) < reserve.amount {
            affordability = .caution
        } else {
            affordability = .affordable
        }

        var facts: [String: String] = [
            "affordability": affordability.rawValue,
            "breachesSafetyReserve": breaches ? "true" : "false",
        ]
        if let goalImpact { facts["goalImpact"] = goalImpact }
        if let date = projectedMinDate {
            let cal = Calendar.current
            facts["projectedMinimumDate"] = "\(cal.component(.month, from: date))月\(cal.component(.day, from: date))日"
        }

        var amounts: [String: Money] = [
            "purchaseAmount": amount,
            "currentCash": cash,
            "cashAfterPurchase": cashAfter,
            "safetyReserve": reserve,
            "futureIncome": futureIncome,
            "fixedExpenses": fixedExpenses,
            "debtPayments": debtPayments,
        ]
        if let projectedMin {
            amounts["projectedMinimumBalance"] = projectedMin
        }

        let pack = AnswerFactPack(
            intent: .purchaseAffordability,
            facts: facts,
            amounts: amounts,
            sourceLabels: ["Account", "Transaction", "Debt", "CashFlow", "Goal"],
            unknowns: context.dataNotes,
            requiresDisclaimer: true,
            dataInsufficient: context.isDataInsufficient
        )

        return PurchaseScenario(
            purchaseAmount: amount,
            currentCash: cash,
            cashAfterPurchase: cashAfter,
            safetyReserve: reserve,
            breachesSafetyReserve: breaches,
            projectedMinimumBalance: projectedMin,
            projectedMinimumDate: projectedMinDate,
            futureIncome: futureIncome,
            fixedExpenses: fixedExpenses,
            debtPayments: debtPayments,
            goalImpact: goalImpact,
            affordability: affordability,
            factPack: pack
        )
    }
}
