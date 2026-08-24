import Foundation
import YoushuFoundation

/// 债务压力等级（确定性规则，非 AI）。
public enum DebtPressureLevel: String, Codable, Sendable, Equatable {
    case low
    case medium
    case high
    case critical

    public var displayName: String {
        switch self {
        case .low: return "较低"
        case .medium: return "中等"
        case .high: return "偏高"
        case .critical: return "很高"
        }
    }
}

/// 债务中心确定性计算。AI 不参与任何金额/日期数学。
public enum DebtCenterCalculator {
    /// 总剩余债务（活跃 / 逾期 / 未知）。
    public static func totalDebt(debts: [Debt]) -> Money {
        DebtBalanceCalculator.totalOutstanding(debts: debts)
    }

    /// 预计每月还款：按频率折算 installment / currentDue / minimumDue。
    /// Returns the **known-only** sum. Callers that must preserve missingness
    /// should use `DebtMoneyPresentation.estimatedMonthly(from:)`.
    public static func estimatedMonthlyRepayment(debts: [Debt]) -> Money {
        DebtMoneyPresentation.estimatedMonthly(from: debts).knownAmount ?? .zeroCNY
    }

    /// 最近一次还款（跨所有债务事件）。
    public static func lastRepayment(events: [DebtEvent]) -> (date: Date, amount: Money)? {
        let repayments = events
            .filter { $0.type == .repayment }
            .sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date > rhs.date }
                return lhs.createdAt > rhs.createdAt
            }
        guard let latest = repayments.first, let amount = latest.amount else { return nil }
        return (latest.date, amount)
    }

    /// 下一次还款：最近 dueDate 的债务。
    /// A known due date does not invent a payment amount; `amount` stays nil
    /// when currentDue / installmentAmount / minimumDue are all unknown.
    public static func nextPayment(debts: [Debt], asOf: Date = Date()) -> (debt: Debt, date: Date, amount: Money?)? {
        let candidates = debts.filter { isOpen($0) && $0.dueDate != nil }
        let upcoming = candidates
            .compactMap { debt -> (Debt, Date, Money?)? in
                guard let due = debt.dueDate else { return nil }
                let amount = debt.currentDue ?? debt.installmentAmount ?? debt.minimumDue
                return (debt, due, amount)
            }
            .sorted { $0.1 < $1.1 }

        if let future = upcoming.first(where: { $0.1 >= Calendar.current.startOfDay(for: asOf) }) {
            return future
        }
        return upcoming.first
    }

    /// 高成本债务：年化利率 ≥ 阈值，或信用卡/分期且利率未知。
    public static func highCostDebts(
        debts: [Debt],
        annualRateThreshold: Decimal = Decimal(string: "0.12")!
    ) -> [Debt] {
        debts.filter { debt in
            guard isOpen(debt) else { return false }
            if let rate = debt.interestRate {
                return rate >= annualRateThreshold
            }
            return debt.debtType.isTypicallyHighCost
        }
        .sorted {
            ($0.interestRate ?? 0) > ($1.interestRate ?? 0)
        }
    }

    /// 债务压力：0...100，越高压力越大。
    public static func debtPressureScore(debts: [Debt], monthlyRepayment: Money? = nil) -> Int {
        let open = debts.filter { isOpen($0) }
        guard !open.isEmpty else { return 0 }

        var score = 0
        let overdueCount = open.filter { $0.status == .overdue }.count
        score += min(overdueCount * 25, 40)

        let highCostCount = highCostDebts(debts: open).count
        if !open.isEmpty {
            let ratio = Double(highCostCount) / Double(open.count)
            score += Int(ratio * 30)
        }

        let total = totalDebt(debts: open).amount
        let monthly: Decimal
        if let monthlyRepayment {
            monthly = monthlyRepayment.amount
        } else {
            switch DebtMoneyPresentation.estimatedMonthly(from: open) {
            case .known(let money):
                monthly = money.amount
            case .unknown, .knownIncomplete:
                monthly = 0
            }
        }
        if total > 0, monthly > 0 {
            // 月供占余额比例越低，清偿越慢 → 压力上升
            let burdenPercent = (monthly * 100) / total
            if burdenPercent < 2 { score += 20 }
            else if burdenPercent < 5 { score += 10 }
            else { score += 5 }
        } else if total > 0 {
            score += 15
        }

        let lowCompleteness = open.filter { $0.profileCompleteness < 0.4 }.count
        score += min(lowCompleteness * 5, 15)

        return min(max(score, 0), 100)
    }

    public static func debtPressureLevel(score: Int) -> DebtPressureLevel {
        switch score {
        case 0..<25: return .low
        case 25..<50: return .medium
        case 50..<75: return .high
        default: return .critical
        }
    }

    /// 预计清偿时间：取各债估算日的最晚值。
    public static func debtFreeEstimate(debts: [Debt], asOf: Date = Date()) -> Date? {
        let dates = debts.filter { isOpen($0) }.compactMap { estimatePayoffDate(for: $0, asOf: asOf) }
        return dates.max()
    }

    public static func estimatePayoffDate(for debt: Debt, asOf: Date = Date()) -> Date? {
        if debt.status == .paidOff { return nil }
        if let maturity = debt.maturityDate { return maturity }

        let calendar = Calendar.current
        if let remaining = debt.remainingInstallments, remaining > 0 {
            let months = monthsForInstallments(remaining, frequency: debt.paymentFrequency)
            return calendar.date(byAdding: .month, value: months, to: asOf)
        }

        if let balance = debt.outstandingBalance?.amount, balance > 0,
           let monthly = monthlyAmount(for: debt)?.amount, monthly > 0 {
            let monthsNeeded = ceilDivision(balance, by: monthly)
            return calendar.date(byAdding: .month, value: monthsNeeded, to: asOf)
        }

        if let due = debt.dueDate, due > asOf {
            return due
        }
        return nil
    }

    // MARK: - Helpers

    public static func isOpen(_ debt: Debt) -> Bool {
        debt.status == .active || debt.status == .overdue || debt.status == .unknown
    }

    public static func monthlyAmount(for debt: Debt) -> Money? {
        if let installment = debt.installmentAmount {
            return normalizeToMonthly(installment, frequency: debt.paymentFrequency)
        }
        if let current = debt.currentDue {
            return normalizeToMonthly(current, frequency: debt.paymentFrequency == .unknown ? .monthly : debt.paymentFrequency)
        }
        if let minimum = debt.minimumDue {
            return normalizeToMonthly(minimum, frequency: .monthly)
        }
        return nil
    }

    public static func normalizeToMonthly(_ amount: Money, frequency: PaymentFrequency) -> Money {
        switch frequency {
        case .weekly:
            return Money(amount: amount.amount * 52 / 12, currencyCode: amount.currencyCode)
        case .biweekly:
            return Money(amount: amount.amount * 26 / 12, currencyCode: amount.currencyCode)
        case .monthly, .irregular, .unknown:
            return amount
        case .quarterly:
            return Money(amount: amount.amount / 3, currencyCode: amount.currencyCode)
        case .yearly:
            return Money(amount: amount.amount / 12, currencyCode: amount.currencyCode)
        }
    }

    private static func monthsForInstallments(_ count: Int, frequency: PaymentFrequency) -> Int {
        switch frequency {
        case .weekly: return max(Int(ceil(Double(count) / 4.0)), 1)
        case .biweekly: return max(Int(ceil(Double(count) / 2.0)), 1)
        case .monthly, .irregular, .unknown: return count
        case .quarterly: return count * 3
        case .yearly: return count * 12
        }
    }

    private static func ceilDivision(_ numerator: Decimal, by denominator: Decimal) -> Int {
        guard denominator > 0 else { return 0 }
        var quotient = numerator / denominator
        var rounded = Decimal()
        NSDecimalRound(&rounded, &quotient, 0, .up)
        let months = NSDecimalNumber(decimal: rounded).intValue
        return max(months, 1)
    }
}
