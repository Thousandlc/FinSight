import Foundation
import YoushuFoundation

/// 主动洞察：由确定性规则生成事实，AI 仅可润色表述。
public enum FinancialInsightGenerator {
    public static func generate(
        context: FinancialContext,
        accounts: [Account] = [],
        transactions: [Transaction] = [],
        debts: [Debt] = [],
        safeBalance: Money = Money(amount: 2_000, currencyCode: "CNY"),
        calendar: Calendar = .current
    ) -> [InsightFactPack] {
        var packs: [InsightFactPack] = []

        if let anomaly = spendingAnomaly(context: context, transactions: transactions, calendar: calendar) {
            packs.append(anomaly)
        }
        if let due = upcomingDebtDue(debts: debts, asOf: context.asOf, calendar: calendar) {
            packs.append(due)
        }
        if let risk = cashFlowRisk(context: context, safeBalance: safeBalance) {
            packs.append(risk)
        }
        if let goal = goalProgress(context: context) {
            packs.append(goal)
        }
        if let milestone = debtMilestone(context: context, debts: debts) {
            packs.append(milestone)
        }
        return packs
    }

    private static func spendingAnomaly(
        context: FinancialContext,
        transactions: [Transaction],
        calendar: Calendar
    ) -> InsightFactPack? {
        guard let top = context.topExpenseCategories.first,
              context.monthlyExpense.amount > 0
        else { return nil }
        let share = (top.amount.amount * 100) / context.monthlyExpense.amount
        guard share >= 40 else { return nil }
        let monthTxIds = transactions.filter {
            $0.transactionType == .expense && ($0.category ?? "其他") == top.category
        }.map(\.id)
        return InsightFactPack(
            type: .spendingPattern,
            titleHint: "异常消费集中",
            facts: [
                "category": top.category,
                "sharePercent": "\(share)",
                "message": "本月「\(top.category)」支出约占生活支出 \(NSDecimalNumber(decimal: share).intValue)%",
            ],
            amounts: [
                "categoryAmount": top.amount,
                "monthlyExpense": context.monthlyExpense,
            ],
            sourceTransactionIds: Array(monthTxIds.prefix(20)),
            sourceLabels: ["Transaction"]
        )
    }

    private static func upcomingDebtDue(
        debts: [Debt],
        asOf: Date,
        calendar: Calendar
    ) -> InsightFactPack? {
        guard let next = DebtCenterCalculator.nextPayment(debts: debts, asOf: asOf) else { return nil }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: asOf), to: calendar.startOfDay(for: next.date)).day ?? 0
        guard days >= 0, days <= 14 else { return nil }
        return InsightFactPack(
            type: .debtRisk,
            titleHint: "债务即将到期",
            facts: [
                "lender": next.debt.lender ?? "未命名债务",
                "dueInDays": "\(days)",
                "dueDate": "\(calendar.component(.month, from: next.date))月\(calendar.component(.day, from: next.date))日",
            ],
            amounts: ["dueAmount": next.amount],
            sourceDebtIds: [next.debt.id],
            sourceLabels: ["Debt"]
        )
    }

    private static func cashFlowRisk(context: FinancialContext, safeBalance: Money) -> InsightFactPack? {
        guard let slice = context.cashFlow30, slice.isBelowSafeBalance else { return nil }
        let alignedSafe = Money(amount: safeBalance.amount, currencyCode: context.currencyCode)
        return InsightFactPack(
            type: .cashFlow,
            titleHint: "现金流风险",
            facts: [
                "explanation": slice.explanation ?? "未来30天余额可能低于安全线",
            ],
            amounts: [
                "minimumBalance": slice.minimumBalance,
                "availableCash": context.availableCash,
                "safeBalance": alignedSafe,
            ],
            sourceLabels: ["Account", "Transaction", "Debt", "CashFlow"]
        )
    }

    private static func goalProgress(context: FinancialContext) -> InsightFactPack? {
        guard let goal = context.goals.first else { return nil }
        return InsightFactPack(
            type: .actionSuggestion,
            titleHint: "目标进度",
            facts: [
                "goalName": goal.name,
                "progressPercent": "\(goal.progressPercent)",
            ],
            amounts: [
                "currentAmount": goal.currentAmount,
                "targetAmount": goal.targetAmount,
                "remainingAmount": goal.remainingAmount,
            ],
            sourceLabels: ["Goal"]
        )
    }

    private static func debtMilestone(context: FinancialContext, debts: [Debt]) -> InsightFactPack? {
        let open = debts.filter { DebtCenterCalculator.isOpen($0) }
        guard !open.isEmpty, context.totalDebt.amount > 0 else { return nil }
        let original = open.compactMap { $0.originalAmount?.amount }.reduce(Decimal(0), +)
        guard original > 0 else { return nil }
        let paidRatio = ((original - context.totalDebt.amount) * 100) / original
        guard paidRatio >= 25 else { return nil }
        return InsightFactPack(
            type: .debtRisk,
            titleHint: "债务清偿里程碑",
            facts: [
                "paidPercent": "\(paidRatio)",
                "message": "已偿还约 \(NSDecimalNumber(decimal: paidRatio).intValue)% 的登记本金/原额",
            ],
            amounts: ["totalDebt": context.totalDebt],
            sourceDebtIds: open.map(\.id),
            sourceLabels: ["Debt"]
        )
    }
}
