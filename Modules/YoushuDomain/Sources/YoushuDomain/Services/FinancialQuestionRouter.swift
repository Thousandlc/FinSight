import Foundation
import YoushuFoundation

/// 将自然语言问题路由到财务意图（规则匹配，非 AI）。
public enum FinancialQuestionRouter {
    public static func classify(_ question: String) -> FinancialQuestionIntent {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return .unknown }

        if containsAny(q, ["能不能买", "可以买", "买得起", "afford", "purchase"]) {
            return .purchaseAffordability
        }
        if containsAny(q, ["有多少钱", "可用资金", "余额", "手头", "how much money", "available"]) {
            return .availableCash
        }
        if containsAny(q, ["欠多少", "总债务", "负债", "how much debt", "owe"]) {
            return .totalDebt
        }
        if containsAny(q, ["为什么花", "花这么多", "支出", "消费构成", "为什么这么多"]) {
            return .spendingBreakdown
        }
        if containsAny(q, ["还清", "何时还完", "什么时候能还", "debt free", "还完"]) {
            return .debtFreeDate
        }
        if containsAny(q, ["存多少", "应该存", "储蓄", "每月存", "save"]) {
            return .monthlySavings
        }
        return .unknown
    }

    public static func extractPurchaseAmount(from question: String) -> Decimal? {
        let pattern = #"([0-9]+(?:\.[0-9]+)?)\s*元?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(question.startIndex..<question.endIndex, in: question)
        guard let match = regex.firstMatch(in: question, range: range),
              let amountRange = Range(match.range(at: 1), in: question)
        else { return nil }
        return Decimal(string: String(question[amountRange]))
    }

    public static let suggestedQuestions: [String] = [
        "我现在有多少钱？",
        "我总共欠多少钱？",
        "我这个月为什么花这么多？",
        "我什么时候能还清所有债务？",
        "我每个月应该存多少钱？",
        "我能不能买3000元的东西？",
    ]

    private static func containsAny(_ text: String, _ keywords: [String]) -> Bool {
        keywords.contains { text.contains($0.lowercased()) }
    }
}

/// 为各意图组装确定性事实包。
public enum FinancialAnswerFactBuilder {
    public static func build(
        intent: FinancialQuestionIntent,
        context: FinancialContext,
        purchaseAmount: Decimal? = nil,
        calendar: Calendar = .current
    ) -> AnswerFactPack {
        if context.isDataInsufficient {
            return AnswerFactPack(
                intent: intent,
                unknowns: ["财务数据不足"],
                dataInsufficient: true
            )
        }

        switch intent {
        case .availableCash:
            return AnswerFactPack(
                intent: intent,
                facts: [
                    "description": "当前可用资金（资产类账户余额合计）",
                ],
                amounts: ["availableCash": context.availableCash],
                sourceLabels: ["Account", "Transaction"]
            )

        case .totalDebt:
            var unknowns: [String] = []
            if !context.hasDebts { unknowns.append("尚无登记债务") }
            return AnswerFactPack(
                intent: intent,
                facts: [
                    "description": "未结清债务余额合计",
                ],
                amounts: [
                    "totalDebt": context.totalDebt,
                    "estimatedMonthlyRepayment": context.estimatedMonthlyRepayment,
                ],
                sourceLabels: ["Debt"],
                unknowns: unknowns
            )

        case .spendingBreakdown:
            var facts: [String: String] = [
                "description": "本月生活支出构成（按分类）",
            ]
            var amounts: [String: Money] = ["monthlyExpense": context.monthlyExpense]
            for (index, item) in context.topExpenseCategories.enumerated() {
                facts["category_\(index)"] = item.category
                amounts["categoryAmount_\(index)"] = item.amount
            }
            if context.topExpenseCategories.isEmpty {
                return AnswerFactPack(
                    intent: intent,
                    facts: facts,
                    amounts: amounts,
                    sourceLabels: ["Transaction"],
                    unknowns: ["本月尚无生活支出记录"]
                )
            }
            return AnswerFactPack(
                intent: intent,
                facts: facts,
                amounts: amounts,
                sourceLabels: ["Transaction"]
            )

        case .debtFreeDate:
            var facts: [String: String] = [:]
            var unknowns: [String] = []
            if let date = context.estimatedDebtFreeDate {
                let m = calendar.component(.month, from: date)
                let y = calendar.component(.year, from: date)
                facts["estimatedDebtFreeDate"] = "\(y)年\(m)月"
            } else {
                unknowns.append("缺少期数或月供，无法可靠估算清偿时间")
            }
            return AnswerFactPack(
                intent: intent,
                facts: facts,
                amounts: [
                    "totalDebt": context.totalDebt,
                    "estimatedMonthlyRepayment": context.estimatedMonthlyRepayment,
                ],
                sourceLabels: ["Debt"],
                unknowns: unknowns,
                requiresDisclaimer: true
            )

        case .monthlySavings:
            let recommended = recommendedMonthlySavings(context: context, calendar: calendar)
            let facts: [String: String] = [
                "method": recommended.method,
            ]
            var unknowns = recommended.unknowns
            if context.monthlyIncome.amount <= 0 {
                unknowns.append("本月收入不足，储蓄建议仅供参考")
            }
            return AnswerFactPack(
                intent: intent,
                facts: facts,
                amounts: [
                    "recommendedMonthlySavings": recommended.amount,
                    "monthlyIncome": context.monthlyIncome,
                    "monthlyExpense": context.monthlyExpense,
                    "monthlyDebtPayment": context.monthlyDebtPayment,
                ],
                sourceLabels: ["Transaction", "Debt", "Goal"],
                unknowns: unknowns,
                requiresDisclaimer: true
            )

        case .purchaseAffordability:
            guard let amount = purchaseAmount, amount > 0 else {
                return AnswerFactPack(
                    intent: intent,
                    unknowns: ["未识别购买金额"],
                    requiresDisclaimer: true,
                    dataInsufficient: false
                )
            }
            let scenario = PurchaseScenarioEngine.evaluate(
                purchaseAmount: Money(amount: amount, currencyCode: context.currencyCode),
                context: context
            )
            return scenario.factPack

        case .unknown:
            return AnswerFactPack(
                intent: .unknown,
                unknowns: ["无法识别问题意图"],
                requiresDisclaimer: false
            )
        }
    }

    private struct SavingsRecommendation {
        var amount: Money
        var method: String
        var unknowns: [String]
    }

    private static func recommendedMonthlySavings(
        context: FinancialContext,
        calendar: Calendar
    ) -> SavingsRecommendation {
        let currency = context.currencyCode
        let surplus = context.monthlyIncome.amount
            - context.monthlyExpense.amount
            - context.monthlyDebtPayment.amount

        if let goal = context.goals.sorted(by: { $0.remainingAmount.amount > $1.remainingAmount.amount }).first,
           goal.remainingAmount.amount > 0 {
            if let target = goal.targetDate, target > context.asOf {
                let months = max(
                    calendar.dateComponents([.month], from: context.asOf, to: target).month ?? 1,
                    1
                )
                let perMonth = goal.remainingAmount.amount / Decimal(months)
                return SavingsRecommendation(
                    amount: Money(amount: perMonth, currencyCode: currency),
                    method: "按目标「\(goal.name)」剩余金额与目标日期均摊",
                    unknowns: []
                )
            }
            let fallback = max(surplus * Decimal(string: "0.3")!, 0)
            return SavingsRecommendation(
                amount: Money(amount: fallback, currencyCode: currency),
                method: "目标「\(goal.name)」无明确日期，按本月结余约 30% 估算",
                unknowns: ["目标日期未知"]
            )
        }

        let base = max(surplus * Decimal(string: "0.2")!, 0)
        return SavingsRecommendation(
            amount: Money(amount: base, currencyCode: currency),
            method: "按本月收入减支出减还款后结余的约 20% 估算",
            unknowns: context.goals.isEmpty ? ["未设置储蓄目标"] : []
        )
    }
}
