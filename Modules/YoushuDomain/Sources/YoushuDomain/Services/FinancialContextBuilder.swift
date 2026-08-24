import Foundation
import YoushuFoundation

/// 将账本数据整理为授权最小化 Context。AI 不访问此 Builder 背后的仓库。
public enum FinancialContextBuilder {
    public struct Source: Sendable {
        public var accounts: [Account]
        public var transactions: [Transaction]
        public var debts: [Debt]
        public var repaymentPlans: [RepaymentPlan]
        public var assets: [Asset]
        public var budgets: [Budget]
        public var goals: [Goal]
        public var asOf: Date
        public var calendar: Calendar
        public var safeBalance: Money

        public init(
            accounts: [Account],
            transactions: [Transaction],
            debts: [Debt] = [],
            repaymentPlans: [RepaymentPlan] = [],
            assets: [Asset] = [],
            budgets: [Budget] = [],
            goals: [Goal] = [],
            asOf: Date = Date(),
            calendar: Calendar = .current,
            safeBalance: Money = Money(amount: 2_000, currencyCode: "CNY")
        ) {
            self.accounts = accounts
            self.transactions = transactions
            self.debts = debts
            self.repaymentPlans = repaymentPlans
            self.assets = assets
            self.budgets = budgets
            self.goals = goals
            self.asOf = asOf
            self.calendar = calendar
            self.safeBalance = safeBalance
        }
    }

    public static func build(_ source: Source) -> FinancialContext {
        let currency = FinancialSummaryEngine.resolveCurrency(
            accounts: source.accounts,
            transactions: source.transactions
        )
        let safe = Money(amount: source.safeBalance.amount, currencyCode: currency)
        let summary = FinancialSummaryEngine.summarize(
            .init(
                accounts: source.accounts,
                transactions: source.transactions,
                debts: source.debts,
                repaymentPlans: source.repaymentPlans,
                asOf: source.asOf,
                calendar: source.calendar,
                safeBalance: safe
            )
        )
        let projection = CashFlowEngine.project(
            .init(
                accounts: source.accounts,
                transactions: source.transactions,
                debts: source.debts,
                repaymentPlans: source.repaymentPlans,
                asOf: source.asOf,
                horizonDays: CashFlowHorizon.days30.rawValue,
                calendar: source.calendar,
                safeBalance: safe
            )
        )
        let outstanding = DebtMoneyPresentation.knownOutstandingTotal(
            from: source.debts,
            computed: DebtBalanceCalculator.totalOutstanding(debts: source.debts)
        )
        let monthly = DebtMoneyPresentation.estimatedMonthly(from: source.debts)
        let debtFree = DebtCenterCalculator.debtFreeEstimate(debts: source.debts, asOf: source.asOf)

        var ratio: Decimal?
        if summary.monthlyIncome.amount > 0 {
            ratio = (summary.monthlyDebtPayment.amount * 100) / summary.monthlyIncome.amount
        }

        var notes: [String] = []
        if source.accounts.isEmpty { notes.append("尚无账户数据") }
        if source.transactions.isEmpty { notes.append("尚无交易数据") }
        if source.debts.isEmpty { notes.append("尚无债务数据") }

        var risks: [String] = []
        if let risk = projection.risk {
            risks.append(CashFlowExplanationBuilder.build(from: risk, calendar: source.calendar))
        }

        let cashSlice = CashFlowContextSlice(
            endingBalance: projection.endingBalance,
            minimumBalance: projection.minimumBalance,
            minimumBalanceDate: projection.minimumBalanceDate,
            isBelowSafeBalance: projection.risk != nil,
            peakRepayment: projection.peakRepayment,
            explanation: projection.risk.map { CashFlowExplanationBuilder.build(from: $0, calendar: source.calendar) }
        )

        let topCategories = topExpenseCategories(
            transactions: source.transactions,
            asOf: source.asOf,
            calendar: source.calendar,
            currency: currency
        )

        let goalSlices = source.goals.map(goalSlice)
        let budgetSlices = source.budgets.map {
            budgetSlice($0, transactions: source.transactions, asOf: source.asOf, calendar: source.calendar)
        }

        let assetTotal: Money? = {
            guard let code = source.assets.first?.currentValue.currencyCode else { return nil }
            return source.assets.reduce(Money(amount: 0, currencyCode: code)) { $0 + $1.currentValue }
        }()

        return FinancialContext(
            availableCash: summary.availableCash,
            monthlyIncome: summary.monthlyIncome,
            monthlyExpense: summary.monthlyExpense,
            monthlyDebtPayment: summary.monthlyDebtPayment,
            estimatedMonthEndBalance: summary.estimatedMonthEndBalance,
            totalDebt: outstanding.knownAmount ?? .zeroCNY,
            totalDebtAvailability: outstanding.availability,
            estimatedMonthlyRepayment: monthly.knownAmount ?? .zeroCNY,
            estimatedMonthlyRepaymentAvailability: monthly.availability,
            estimatedDebtFreeDate: debtFree,
            financialHealthScore: summary.financialHealthScore,
            debtPaymentToIncomePercent: ratio,
            topExpenseCategories: topCategories,
            cashFlow30: cashSlice,
            recentRisks: risks,
            goals: goalSlices,
            budgets: budgetSlices,
            totalAssets: assetTotal,
            hasAccounts: !source.accounts.isEmpty,
            hasTransactions: !source.transactions.isEmpty,
            hasDebts: !source.debts.isEmpty,
            dataNotes: notes,
            asOf: source.asOf,
            currencyCode: currency
        )
    }

    public static func monthlySummaryFacts(from context: FinancialContext) -> MonthlySummaryFacts {
        let pressure: String
        if let pct = context.debtPaymentToIncomePercent, pct >= 20 {
            pressure = "债务还款"
        } else if context.monthlyExpense.amount >= context.monthlyDebtPayment.amount
                    && context.monthlyExpense.amount > 0 {
            pressure = "生活支出"
        } else if context.cashFlow30?.isBelowSafeBalance == true {
            pressure = "未来现金流风险"
        } else {
            pressure = "暂无明显单一压力"
        }

        var sources = ["Account", "Transaction", "Debt", "CashFlow"]
        if !context.goals.isEmpty { sources.append("Goal") }
        if !context.budgets.isEmpty { sources.append("Budget") }

        return MonthlySummaryFacts(
            availableCash: context.availableCash,
            monthlyIncome: context.monthlyIncome,
            monthlyExpense: context.monthlyExpense,
            monthlyDebtPayment: context.monthlyDebtPayment,
            debtPaymentToIncomePercent: context.debtPaymentToIncomePercent,
            primaryPressure: pressure,
            estimatedMonthEndBalance: context.estimatedMonthEndBalance,
            cashFlowRiskExplanation: context.cashFlow30?.explanation,
            sourceLabels: sources
        )
    }

    // MARK: - Helpers

    public static func topExpenseCategories(
        transactions: [Transaction],
        asOf: Date,
        calendar: Calendar,
        currency: String,
        limit: Int = 5
    ) -> [CategoryAmount] {
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: asOf)) ?? asOf
        var totals: [String: Decimal] = [:]
        for tx in transactions where tx.transactionType == .expense
            && tx.date >= monthStart
            && tx.date <= asOf
            && tx.amount.currencyCode == currency {
            let key = tx.category ?? "其他"
            totals[key, default: 0] += tx.amount.amount
        }
        return totals
            .map { CategoryAmount(category: $0.key, amount: Money(amount: $0.value, currencyCode: currency)) }
            .sorted { $0.amount.amount > $1.amount.amount }
            .prefix(limit)
            .map { $0 }
    }

    private static func goalSlice(_ goal: Goal) -> GoalContextSlice {
        let remaining = max(goal.targetAmount.amount - goal.currentAmount.amount, 0)
        let progress: Decimal
        if goal.targetAmount.amount > 0 {
            progress = min((goal.currentAmount.amount * 100) / goal.targetAmount.amount, 100)
        } else {
            progress = 0
        }
        return GoalContextSlice(
            id: goal.id,
            name: goal.name,
            type: goal.type,
            targetAmount: goal.targetAmount,
            currentAmount: goal.currentAmount,
            remainingAmount: Money(amount: remaining, currencyCode: goal.targetAmount.currencyCode),
            progressPercent: progress,
            targetDate: goal.targetDate
        )
    }

    private static func budgetSlice(
        _ budget: Budget,
        transactions: [Transaction],
        asOf: Date,
        calendar: Calendar
    ) -> BudgetContextSlice {
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: asOf)) ?? asOf
        var spent: Decimal = 0
        for tx in transactions where tx.transactionType == .expense
            && tx.date >= monthStart
            && tx.date <= asOf
            && tx.amount.currencyCode == budget.limit.currencyCode {
            if let category = budget.category, tx.category != category { continue }
            spent += tx.amount.amount
        }
        let spentMoney = Money(amount: spent, currencyCode: budget.limit.currencyCode)
        let remaining = Money(
            amount: max(budget.limit.amount - spent, 0),
            currencyCode: budget.limit.currencyCode
        )
        return BudgetContextSlice(
            id: budget.id,
            name: budget.name,
            category: budget.category,
            limit: budget.limit,
            spent: spentMoney,
            remaining: remaining
        )
    }
}
