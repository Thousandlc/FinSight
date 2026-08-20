import Foundation
import YoushuFoundation

/// 确定性现金流预测（7 / 30 / 60 / 90 天）。
/// 输入：历史收支、固定/周期支出、债务还款、已知未来收入。AI 不参与金额计算。
public enum CashFlowEngine {
    public struct Input: Sendable {
        public var accounts: [Account]
        public var transactions: [Transaction]
        public var debts: [Debt]
        public var repaymentPlans: [RepaymentPlan]
        public var asOf: Date
        public var horizonDays: Int
        public var calendar: Calendar
        public var safeBalance: Money
        /// 计算日均收支时回看的天数。
        public var lookbackDays: Int

        public init(
            accounts: [Account],
            transactions: [Transaction],
            debts: [Debt] = [],
            repaymentPlans: [RepaymentPlan] = [],
            asOf: Date = Date(),
            horizonDays: Int,
            calendar: Calendar = .current,
            safeBalance: Money = Money(amount: 2_000, currencyCode: "CNY"),
            lookbackDays: Int = 30
        ) {
            self.accounts = accounts
            self.transactions = transactions
            self.debts = debts
            self.repaymentPlans = repaymentPlans
            self.asOf = asOf
            self.horizonDays = max(horizonDays, 0)
            self.calendar = calendar
            self.safeBalance = safeBalance
            self.lookbackDays = max(lookbackDays, 1)
        }
    }

    public static func project(_ input: Input) -> CashFlowProjection {
        let currency = FinancialSummaryEngine.resolveCurrency(
            accounts: input.accounts,
            transactions: input.transactions
        )
        let starting = AccountBalanceEngine.availableFunds(
            accounts: input.accounts,
            transactions: input.transactions
        )
        let startOfToday = input.calendar.startOfDay(for: input.asOf)
        let rates = dailyRates(input: input, currency: currency, startOfToday: startOfToday)
        let discrete = discreteDrivers(input: input, currency: currency, startOfToday: startOfToday)

        var balance = starting
        var minimum = starting
        var minimumDate = startOfToday
        var peakRepayment: Money?
        var peakRepaymentDate: Date?
        var allDrivers: [CashFlowDriver] = []
        var driversByDay: [Date: [CashFlowDriver]] = [:]

        guard input.horizonDays > 0 else {
            return CashFlowProjection(
                horizon: nearestHorizon(input.horizonDays),
                startingBalance: starting,
                endingBalance: starting,
                minimumBalance: starting,
                minimumBalanceDate: startOfToday
            )
        }

        for offset in 1...input.horizonDays {
            guard let day = input.calendar.date(byAdding: .day, value: offset, to: startOfToday) else {
                continue
            }
            var dayDrivers: [CashFlowDriver] = []

            if rates.dailyIncome.amount > 0 {
                let income = CashFlowDriver(
                    date: day,
                    amount: rates.dailyIncome,
                    signedAmount: rates.dailyIncome,
                    kind: .historicalIncome,
                    label: "历史日均收入"
                )
                dayDrivers.append(income)
                balance = balance + income.signedAmount
            }
            if rates.dailyExpense.amount > 0 {
                let expense = CashFlowDriver(
                    date: day,
                    amount: rates.dailyExpense,
                    signedAmount: Money(amount: -rates.dailyExpense.amount, currencyCode: currency),
                    kind: .historicalExpense,
                    label: "历史日均生活支出"
                )
                dayDrivers.append(expense)
                balance = balance + expense.signedAmount
            }

            let dayKey = input.calendar.startOfDay(for: day)
            for event in discrete[dayKey, default: []] {
                dayDrivers.append(event)
                balance = balance + event.signedAmount
                if event.kind == .debtRepayment {
                    if peakRepayment == nil || event.amount > peakRepayment! {
                        peakRepayment = event.amount
                        peakRepaymentDate = day
                    }
                }
            }

            if balance < minimum {
                minimum = balance
                minimumDate = day
            }
            driversByDay[dayKey] = dayDrivers
            allDrivers.append(contentsOf: dayDrivers)
        }

        let safe = Money(amount: input.safeBalance.amount, currencyCode: currency)
        let riskDrivers = significantDrivers(
            on: minimumDate,
            in: driversByDay,
            calendar: input.calendar
        )
        let facts = CashFlowExplanationFacts(
            minimumBalance: minimum,
            minimumBalanceDate: minimumDate,
            majorDrivers: riskDrivers,
            safeBalance: safe,
            isBelowSafeBalance: minimum.amount < safe.amount
        )
        let risk: CashFlowRisk? = facts.isBelowSafeBalance
            ? CashFlowRisk(
                minimumBalance: minimum,
                minimumBalanceDate: minimumDate,
                peakRepayment: peakRepayment,
                peakRepaymentDate: peakRepaymentDate,
                safeBalance: safe,
                drivers: riskDrivers,
                explanationFacts: facts
            )
            : nil

        return CashFlowProjection(
            horizon: nearestHorizon(input.horizonDays),
            startingBalance: starting,
            endingBalance: balance,
            minimumBalance: minimum,
            minimumBalanceDate: minimumDate,
            peakRepayment: peakRepayment,
            peakRepaymentDate: peakRepaymentDate,
            drivers: allDrivers,
            risk: risk
        )
    }

    public static func projectAllHorizons(_ input: Input) -> [CashFlowProjection] {
        CashFlowHorizon.allCases.map { horizon in
            var copy = input
            copy.horizonDays = horizon.rawValue
            return project(copy)
        }
    }

    // MARK: - Rates

    private struct DailyRates {
        var dailyIncome: Money
        var dailyExpense: Money
    }

    private static func dailyRates(input: Input, currency: String, startOfToday: Date) -> DailyRates {
        let lookbackStart = input.calendar.date(
            byAdding: .day,
            value: -input.lookbackDays,
            to: startOfToday
        ) ?? startOfToday
        let history = input.transactions.filter {
            $0.date >= lookbackStart
                && $0.date < startOfToday
                && $0.amount.currencyCode == currency
        }

        var incomeTotal = Decimal(0)
        var expenseTotal = Decimal(0)
        for tx in history {
            switch tx.transactionType {
            case .income, .refund, .reimbursement:
                if tx.category == TransactionCategory.transfer { continue }
                incomeTotal += tx.amount.amount
            case .expense:
                // 固定/周期支出单独排程，不进入日均，避免双重计入。
                if tx.recurringRule != nil { continue }
                expenseTotal += tx.amount.amount
            default:
                break
            }
        }

        let days = Decimal(input.lookbackDays)
        return DailyRates(
            dailyIncome: Money(amount: incomeTotal / days, currencyCode: currency),
            dailyExpense: Money(amount: expenseTotal / days, currencyCode: currency)
        )
    }

    // MARK: - Discrete events

    private static func discreteDrivers(
        input: Input,
        currency: String,
        startOfToday: Date
    ) -> [Date: [CashFlowDriver]] {
        var map: [Date: [CashFlowDriver]] = [:]
        let end = input.calendar.date(byAdding: .day, value: input.horizonDays, to: startOfToday)
            ?? startOfToday

        appendKnownFutureIncome(
            transactions: input.transactions,
            currency: currency,
            startOfToday: startOfToday,
            end: end,
            calendar: input.calendar,
            into: &map
        )
        appendRecurringAndFixed(
            transactions: input.transactions,
            currency: currency,
            startOfToday: startOfToday,
            end: end,
            calendar: input.calendar,
            into: &map
        )
        appendDebtRepayments(
            debts: input.debts,
            plans: input.repaymentPlans,
            transactions: input.transactions,
            currency: currency,
            startOfToday: startOfToday,
            end: end,
            calendar: input.calendar,
            into: &map
        )
        return map
    }

    private static func appendKnownFutureIncome(
        transactions: [Transaction],
        currency: String,
        startOfToday: Date,
        end: Date,
        calendar: Calendar,
        into map: inout [Date: [CashFlowDriver]]
    ) {
        for tx in transactions where tx.amount.currencyCode == currency {
            guard tx.date > startOfToday, tx.date <= end else { continue }
            switch tx.transactionType {
            case .income, .refund, .reimbursement:
                if tx.category == TransactionCategory.transfer { continue }
                let day = calendar.startOfDay(for: tx.date)
                map[day, default: []].append(
                    CashFlowDriver(
                        date: day,
                        amount: tx.amount,
                        signedAmount: tx.amount,
                        kind: .knownFutureIncome,
                        label: tx.merchant ?? "已知未来收入",
                        transactionId: tx.id
                    )
                )
            default:
                break
            }
        }
    }

    private static func appendRecurringAndFixed(
        transactions: [Transaction],
        currency: String,
        startOfToday: Date,
        end: Date,
        calendar: Calendar,
        into map: inout [Date: [CashFlowDriver]]
    ) {
        let templates = transactions.filter {
            $0.amount.currencyCode == currency
                && $0.transactionType == .expense
                && $0.recurringRule != nil
        }
        // 去重：同商户+金额+频率只排一次
        var seen = Set<String>()
        for tx in templates {
            guard let rule = tx.recurringRule else { continue }
            let key = "\(tx.merchant ?? "")|\(tx.amount.amount)|\(rule.frequency.rawValue)"
            if seen.contains(key) { continue }
            seen.insert(key)

            let kind: CashFlowDriver.Kind = rule.frequency == .monthly || rule.frequency == .yearly
                ? .fixedExpense
                : .recurringExpense
            let dates = occurrenceDates(
                start: rule.nextDate ?? tx.date,
                frequency: rule.frequency,
                interval: rule.interval,
                endDate: rule.endDate,
                rangeStart: startOfToday,
                rangeEnd: end,
                calendar: calendar
            )
            for day in dates {
                map[day, default: []].append(
                    CashFlowDriver(
                        date: day,
                        amount: tx.amount,
                        signedAmount: Money(amount: -tx.amount.amount, currencyCode: currency),
                        kind: kind,
                        label: tx.merchant ?? "固定支出",
                        transactionId: tx.id
                    )
                )
            }
        }
    }

    private static func appendDebtRepayments(
        debts: [Debt],
        plans: [RepaymentPlan],
        transactions: [Transaction],
        currency: String,
        startOfToday: Date,
        end: Date,
        calendar: Calendar,
        into map: inout [Date: [CashFlowDriver]]
    ) {
        let plansByDebt = Dictionary(grouping: plans, by: \.debtId)
        let repaidDebtIdsThisMonth: Set<UUID> = {
            let monthStart = calendar.date(
                from: calendar.dateComponents([.year, .month], from: startOfToday)
            ) ?? startOfToday
            return Set(
                transactions.compactMap { tx -> UUID? in
                    guard tx.transactionType == .repayment,
                          tx.date >= monthStart,
                          tx.date <= startOfToday,
                          let debtId = tx.relatedDebtId
                    else { return nil }
                    return debtId
                }
            )
        }()

        for debt in debts where DebtCenterCalculator.isOpen(debt) {
            let amount = repaymentAmount(for: debt, plans: plansByDebt[debt.id] ?? [])
            guard let amount, amount.currencyCode == currency, amount.amount > 0 else { continue }

            if let plan = plansByDebt[debt.id]?.first {
                let dates = occurrenceDates(
                    start: plan.startDate,
                    frequency: plan.frequency,
                    interval: 1,
                    endDate: plan.endDate,
                    rangeStart: startOfToday,
                    rangeEnd: end,
                    calendar: calendar
                )
                for day in dates {
                    if isSameMonth(day, startOfToday, calendar: calendar),
                       repaidDebtIdsThisMonth.contains(debt.id) {
                        continue
                    }
                    map[day, default: []].append(
                        debtDriver(debt: debt, amount: amount, day: day)
                    )
                }
            } else if let due = debt.dueDate {
                let dueDay = calendar.component(.day, from: due)
                var cursor = startOfToday
                while cursor <= end {
                    if let occurrence = dateOnDayOfMonth(dueDay, inSameMonthAs: cursor, calendar: calendar),
                       occurrence > startOfToday,
                       occurrence <= end {
                        if !(isSameMonth(occurrence, startOfToday, calendar: calendar)
                             && repaidDebtIdsThisMonth.contains(debt.id)) {
                            map[occurrence, default: []].append(
                                debtDriver(debt: debt, amount: amount, day: occurrence)
                            )
                        }
                    }
                    guard let next = calendar.date(byAdding: .month, value: 1, to: cursor) else { break }
                    cursor = calendar.date(
                        from: calendar.dateComponents([.year, .month], from: next)
                    ) ?? next
                }
            }
        }
    }

    private static func debtDriver(debt: Debt, amount: Money, day: Date) -> CashFlowDriver {
        CashFlowDriver(
            date: day,
            amount: amount,
            signedAmount: Money(amount: -amount.amount, currencyCode: amount.currencyCode),
            kind: .debtRepayment,
            label: debt.lender.map { "\($0)还款" } ?? "债务还款",
            debtId: debt.id
        )
    }

    private static func repaymentAmount(for debt: Debt, plans: [RepaymentPlan]) -> Money? {
        if let plan = plans.first {
            return plan.installmentAmount
        }
        return debt.currentDue ?? debt.installmentAmount ?? debt.minimumDue
    }

    // MARK: - Scheduling helpers

    private static func occurrenceDates(
        start: Date,
        frequency: PaymentFrequency,
        interval: Int,
        endDate: Date?,
        rangeStart: Date,
        rangeEnd: Date,
        calendar: Calendar
    ) -> [Date] {
        var dates: [Date] = []
        var cursor = calendar.startOfDay(for: start)
        let step = max(interval, 1)
        var guardCount = 0
        while cursor <= rangeEnd, guardCount < 500 {
            if cursor > rangeStart, cursor <= rangeEnd {
                if let endDate, cursor > endDate { break }
                dates.append(cursor)
            }
            guard let next = advance(cursor, frequency: frequency, interval: step, calendar: calendar) else {
                break
            }
            if next <= cursor { break }
            cursor = next
            guardCount += 1
        }
        return dates
    }

    private static func advance(
        _ date: Date,
        frequency: PaymentFrequency,
        interval: Int,
        calendar: Calendar
    ) -> Date? {
        switch frequency {
        case .weekly:
            return calendar.date(byAdding: .day, value: 7 * interval, to: date)
        case .biweekly:
            return calendar.date(byAdding: .day, value: 14 * interval, to: date)
        case .monthly, .irregular, .unknown:
            return calendar.date(byAdding: .month, value: interval, to: date)
        case .quarterly:
            return calendar.date(byAdding: .month, value: 3 * interval, to: date)
        case .yearly:
            return calendar.date(byAdding: .year, value: interval, to: date)
        }
    }

    private static func dateOnDayOfMonth(_ day: Int, inSameMonthAs date: Date, calendar: Calendar) -> Date? {
        var comps = calendar.dateComponents([.year, .month], from: date)
        let maxDay = calendar.range(of: .day, in: .month, for: date)?.count ?? 28
        comps.day = min(max(day, 1), maxDay)
        return calendar.date(from: comps).map { calendar.startOfDay(for: $0) }
    }

    private static func isSameMonth(_ a: Date, _ b: Date, calendar: Calendar) -> Bool {
        calendar.isDate(a, equalTo: b, toGranularity: .month)
    }

    private static func significantDrivers(
        on date: Date,
        in driversByDay: [Date: [CashFlowDriver]],
        calendar: Calendar
    ) -> [CashFlowDriver] {
        let day = calendar.startOfDay(for: date)
        let candidates = driversByDay[day, default: []].filter {
            $0.kind == .debtRepayment || $0.kind == .fixedExpense || $0.kind == .recurringExpense
                || $0.kind == .knownFutureIncome
        }
        return candidates
            .sorted { abs($0.signedAmount.amount) > abs($1.signedAmount.amount) }
            .prefix(3)
            .map { $0 }
    }

    private static func nearestHorizon(_ days: Int) -> CashFlowHorizon {
        CashFlowHorizon.allCases.min(by: { abs($0.rawValue - days) < abs($1.rawValue - days) }) ?? .days30
    }
}

/// 由确定性事实生成可读解释（非 AI）。后续可交给 AI 润色，但数字必须来自此文案的事实源。
public enum CashFlowExplanationBuilder {
    public static func build(from facts: CashFlowExplanationFacts, calendar: Calendar = .current) -> String {
        let dateText = formatDate(facts.minimumBalanceDate, calendar: calendar)
        let balanceText = formatMoney(facts.minimumBalance)
        let drivers = facts.majorDrivers.filter { $0.signedAmount.amount < 0 }
        if drivers.isEmpty {
            if facts.isBelowSafeBalance {
                return "预计\(dateText)账户余额可能下降至\(balanceText)，已低于安全余额\(formatMoney(facts.safeBalance))。"
            }
            return "预计\(dateText)账户余额最低约\(balanceText)。"
        }
        let reason = drivers.map { "\($0.label)\(formatMoney($0.amount))" }.joined(separator: "和")
        var text = "预计\(dateText)账户余额可能下降至\(balanceText)，主要原因是\(reason)集中发生。"
        if facts.isBelowSafeBalance {
            text += "该水平低于安全余额\(formatMoney(facts.safeBalance))。"
        }
        return text
    }

    public static func build(from risk: CashFlowRisk, calendar: Calendar = .current) -> String {
        build(from: risk.explanationFacts, calendar: calendar)
    }

    public static func buildSummary(from summary: FinancialSummary, risk: CashFlowRisk?) -> String {
        if let risk {
            return build(from: risk)
        }
        let income = formatMoney(summary.monthlyIncome)
        let expense = formatMoney(summary.monthlyExpense)
        let debt = formatMoney(summary.monthlyDebtPayment)
        let end = formatMoney(summary.estimatedMonthEndBalance)
        return "本月目前收入\(income)、生活支出\(expense)、债务还款\(debt)；按当前节奏预计月底结余约\(end)。"
    }

    private static func formatDate(_ date: Date, calendar: Calendar) -> String {
        let m = calendar.component(.month, from: date)
        let d = calendar.component(.day, from: date)
        return "\(m)月\(d)日"
    }

    private static func formatMoney(_ money: Money) -> String {
        let number = money.amount as NSDecimalNumber
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        let amount = formatter.string(from: number) ?? "\(money.amount)"
        return "¥\(amount)"
    }
}
