import Foundation

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
