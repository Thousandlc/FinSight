import Foundation
import YoushuFoundation

extension DebtType {
    /// MVP 可选类型：信用卡 / 消费信贷 / 消费分期 / 银行贷款 / 个人借款
    public static var mvpCases: [DebtType] {
        [.creditCard, .consumerLoan, .bnpl, .bankLoan, .personalLoan]
    }

    public var displayName: String {
        switch self {
        case .creditCard: return "信用卡"
        case .consumerLoan: return "消费信贷"
        case .bnpl: return "消费分期"
        case .bankLoan, .mortgage, .carLoan, .studentLoan: return "银行贷款"
        case .personalLoan: return "个人借款"
        case .other: return "其他"
        }
    }

    /// 是否视为高成本债务候选（无利率时信用卡默认纳入）。
    public var isTypicallyHighCost: Bool {
        switch self {
        case .creditCard, .bnpl, .consumerLoan: return true
        default: return false
        }
    }
}

extension DebtStatus {
    public var displayName: String {
        switch self {
        case .active: return "还款中"
        case .overdue: return "已逾期"
        case .paidOff: return "已结清"
        case .unknown: return "未知"
        }
    }
}

extension DebtSource {
    public var displayName: String {
        switch self {
        case .screenshot: return "截图识别"
        case .pdf: return "PDF"
        case .transactionInference: return "交易推断"
        case .userInput: return "手动录入"
        case .futureAPI: return "外部同步"
        }
    }
}

extension DebtEventType {
    /// MVP 事件：创建 / 账单更新 / 还款 / 利息变化 / 逾期 / 分期完成 / 手动修改
    public static var mvpCases: [DebtEventType] {
        [.created, .billUpdated, .repayment, .interestChanged, .overdue, .installmentCompleted, .manualEdit]
    }

    public var displayName: String {
        switch self {
        case .created: return "创建债务"
        case .billUpdated: return "账单更新"
        case .repayment: return "还款"
        case .interestChanged, .interestAccrued: return "利息变化"
        case .overdue: return "逾期"
        case .installmentCompleted: return "分期完成"
        case .manualEdit, .adjustment: return "手动修改"
        case .feeCharged: return "手续费"
        case .statusChanged: return "状态变更"
        case .scheduleUpdated: return "计划更新"
        }
    }
}

extension PaymentFrequency {
    public var displayName: String {
        switch self {
        case .weekly: return "每周"
        case .biweekly: return "每两周"
        case .monthly: return "每月"
        case .quarterly: return "每季"
        case .yearly: return "每年"
        case .irregular: return "不定期"
        case .unknown: return "未知"
        }
    }

    /// 换算为每月期数（确定性）。
    public var monthsPerPeriod: Decimal {
        switch self {
        case .weekly: return Decimal(string: "0.25")!
        case .biweekly: return Decimal(string: "0.5")!
        case .monthly: return 1
        case .quarterly: return 3
        case .yearly: return 12
        case .irregular, .unknown: return 1
        }
    }
}

/// Presentation mapping for optional Debt money facts.
/// Unknown (`nil`) is not a known-zero amount.
/// A known-only subtotal is not a complete total.
public enum DebtMoneyPresentation: Equatable, Sendable {
    public static let unknownPlaceholder = "—"
    public static let incompleteCaption = "部分金额未知"

    case unknown
    case known(Money)
    case knownIncomplete(Money)

    public init(_ money: Money?) {
        if let money {
            self = .known(money)
        } else {
            self = .unknown
        }
    }

    public init(amount: Money, availability: FieldAvailability) {
        switch availability {
        case .missing, .notApplicable:
            self = .unknown
        case .partial:
            self = .knownIncomplete(amount)
        case .known:
            self = .known(amount)
        }
    }

    public var isUnknown: Bool {
        if case .unknown = self { return true }
        return false
    }

    public var isComplete: Bool {
        if case .known = self { return true }
        return false
    }

    public var availability: FieldAvailability {
        switch self {
        case .unknown: return .missing
        case .known: return .known
        case .knownIncomplete: return .partial
        }
    }

    public var knownAmount: Money? {
        switch self {
        case .unknown: return nil
        case .known(let money), .knownIncomplete(let money): return money
        }
    }

    public var caption: String? {
        if case .knownIncomplete = self { return Self.incompleteCaption }
        return nil
    }

    public func text(formatted: (Money) -> String) -> String {
        switch self {
        case .unknown:
            return Self.unknownPlaceholder
        case .known(let money), .knownIncomplete(let money):
            return formatted(money)
        }
    }

    /// Sum of **known** outstanding balances for open debts.
    /// All-unknown open balances stay unknown. Mixed inventories are incomplete
    /// subtotals — not a complete total. An empty open set uses `computed`.
    public static func knownOutstandingTotal(from debts: [Debt], computed: Money) -> DebtMoneyPresentation {
        let open = debts.filter { DebtCenterCalculator.isOpen($0) }
        if open.isEmpty {
            return .known(computed)
        }
        let knownCount = open.filter { $0.outstandingBalance != nil }.count
        if knownCount == 0 {
            return .unknown
        }
        if knownCount == open.count {
            return .known(computed)
        }
        return .knownIncomplete(computed)
    }

    /// Estimated monthly repayment from known installment / currentDue / minimumDue.
    /// No usable known payment facts stay unknown — not a fabricated ¥0.
    public static func estimatedMonthly(from debts: [Debt]) -> DebtMoneyPresentation {
        let open = debts.filter { DebtCenterCalculator.isOpen($0) }
        if open.isEmpty {
            return .known(.zeroCNY)
        }

        var known: [Money] = []
        var unknownCount = 0
        for debt in open {
            if let monthly = DebtCenterCalculator.monthlyAmount(for: debt) {
                known.append(monthly)
            } else {
                unknownCount += 1
            }
        }

        guard let currency = known.first?.currencyCode else {
            return .unknown
        }
        let sum = known
            .filter { $0.currencyCode == currency }
            .reduce(Money(amount: 0, currencyCode: currency), +)
        if unknownCount == 0 {
            return .known(sum)
        }
        return .knownIncomplete(sum)
    }
}
