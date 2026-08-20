import Foundation
import YoushuFoundation

/// 确定性财务汇总。金额全部来自 Account / Transaction / Debt，禁止写死。
public enum FinancialSummaryEngine {
    public struct Input: Sendable {
        public var accounts: [Account]
        public var transactions: [Transaction]
        public var debts: [Debt]
        public var repaymentPlans: [RepaymentPlan]
        public var asOf: Date
        public var calendar: Calendar
        public var safeBalance: Money

        public init(
            accounts: [Account],
            transactions: [Transaction],
            debts: [Debt] = [],
            repaymentPlans: [RepaymentPlan] = [],
            asOf: Date = Date(),
            calendar: Calendar = .current,
            safeBalance: Money = Money(amount: 2_000, currencyCode: "CNY")
        ) {
            self.accounts = accounts
            self.transactions = transactions
            self.debts = debts
            self.repaymentPlans = repaymentPlans
            self.asOf = asOf
            self.calendar = calendar
            self.safeBalance = safeBalance
        }
    }

    public static func summarize(_ input: Input) -> FinancialSummary {
        let currency = resolveCurrency(accounts: input.accounts, transactions: input.transactions)
        let zero = Money(amount: 0, currencyCode: currency)
        let availableCash = AccountBalanceEngine.availableFunds(
            accounts: input.accounts,
            transactions: input.transactions
        )

        let monthStart = input.calendar.date(
            from: input.calendar.dateComponents([.year, .month], from: input.asOf)
        ) ?? input.asOf
        let monthTx = input.transactions.filter {
            $0.date >= monthStart && $0.date <= input.asOf && $0.amount.currencyCode == currency
        }

        var monthlyIncome = zero
        var monthlyExpense = zero
        var monthlyDebtPayment = zero
        for tx in monthTx {
            switch tx.transactionType {
            case .income, .refund, .reimbursement:
                if tx.category == TransactionCategory.transfer { continue }
                monthlyIncome = monthlyIncome + tx.amount
            case .expense:
                monthlyExpense = monthlyExpense + tx.amount
            case .repayment:
                monthlyDebtPayment = monthlyDebtPayment + tx.amount
            default:
                break
            }
        }

        let daysRemaining = remainingDaysInMonth(asOf: input.asOf, calendar: input.calendar)
        let monthEndProjection = CashFlowEngine.project(
            CashFlowEngine.Input(
                accounts: input.accounts,
                transactions: input.transactions,
                debts: input.debts,
                repaymentPlans: input.repaymentPlans,
                asOf: input.asOf,
                horizonDays: max(daysRemaining, 0),
                calendar: input.calendar,
                safeBalance: alignedSafeBalance(input.safeBalance, currency: currency)
            )
        )

        let estimatedMonthEnd = daysRemaining == 0
            ? availableCash
            : monthEndProjection.endingBalance

        let totalDebt = DebtBalanceCalculator.totalOutstanding(debts: input.debts)
        let health = healthScore(
            availableCash: availableCash,
            totalDebt: totalDebt,
            monthlyIncome: monthlyIncome,
            monthlyExpense: monthlyExpense + monthlyDebtPayment
        )

        return FinancialSummary(
            availableCash: availableCash,
            monthlyIncome: monthlyIncome,
            monthlyExpense: monthlyExpense,
            monthlyDebtPayment: monthlyDebtPayment,
            estimatedMonthEndBalance: estimatedMonthEnd,
            financialHealthScore: health
        )
    }

    // MARK: - Health

    public static func healthScore(
        availableCash: Money,
        totalDebt: Money,
        monthlyIncome: Money,
        monthlyExpense: Money
    ) -> Int? {
        guard monthlyIncome.amount > 0 || availableCash.amount > 0 else { return nil }
        let income = max(monthlyIncome.amount, 1)
        let expenseRatio = monthlyExpense.amount / income
        let debtRatio = totalDebt.amount / max(availableCash.amount + totalDebt.amount, 1)
        let expenseComponent = max(0, 1 - min(expenseRatio, Decimal(1.5)) / Decimal(1.5))
        let debtComponent = max(0, 1 - min(debtRatio, Decimal(1)))
        let score = (expenseComponent * 50 + debtComponent * 50)
        return Int((score as NSDecimalNumber).doubleValue.rounded())
    }

    // MARK: - Helpers

    public static func remainingDaysInMonth(asOf: Date, calendar: Calendar = .current) -> Int {
        let day = calendar.component(.day, from: asOf)
        let daysInMonth = calendar.range(of: .day, in: .month, for: asOf)?.count ?? day
        return max(daysInMonth - day, 0)
    }

    public static func resolveCurrency(accounts: [Account], transactions: [Transaction]) -> String {
        accounts.first?.currencyCode
            ?? transactions.first?.currencyCode
            ?? "CNY"
    }

    private static func alignedSafeBalance(_ safe: Money, currency: String) -> Money {
        Money(amount: safe.amount, currencyCode: currency)
    }
}
