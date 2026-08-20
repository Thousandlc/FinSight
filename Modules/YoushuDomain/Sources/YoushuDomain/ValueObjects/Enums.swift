import Foundation

public enum TransactionType: String, Codable, CaseIterable, Sendable, Hashable {
    case expense
    case income
    case transfer
    case refund
    case reimbursement
    case borrowing
    case repayment
    case investmentBuy
    case investmentSell
}

public enum TransactionSource: String, Codable, CaseIterable, Sendable, Hashable {
    case manual
    case screenshot
    case shortcut
    case importFile
    case aiInference
    case system
}

public enum AssetType: String, Codable, CaseIterable, Sendable, Hashable {
    case cashEquivalent
    case investment
    case realEstate
    case vehicle
    case other
}

public enum DebtType: String, Codable, CaseIterable, Sendable, Hashable {
    case creditCard
    case consumerLoan
    /// 消费分期（BNPL / 分期付款）
    case bnpl
    /// 银行贷款（含房贷/车贷等，MVP 合并展示）
    case bankLoan
    case personalLoan
    case mortgage
    case carLoan
    case studentLoan
    case other
}

public enum DebtStatus: String, Codable, CaseIterable, Sendable, Hashable {
    case active
    case overdue
    case paidOff
    case unknown
}

public enum DebtSource: String, Codable, CaseIterable, Sendable, Hashable {
    case screenshot
    case pdf
    case transactionInference
    case userInput
    case futureAPI
}

public enum DebtEventType: String, Codable, CaseIterable, Sendable, Hashable {
    case created
    case billUpdated
    case repayment
    case interestChanged
    case overdue
    case installmentCompleted
    case manualEdit
    /// Legacy aliases kept for persisted snapshots.
    case interestAccrued
    case feeCharged
    case adjustment
    case statusChanged
    case scheduleUpdated
}

public enum PaymentFrequency: String, Codable, CaseIterable, Sendable, Hashable {
    case weekly
    case biweekly
    case monthly
    case quarterly
    case yearly
    case irregular
    case unknown
}

public enum InsightType: String, Codable, CaseIterable, Sendable, Hashable {
    case summary
    case cashFlow
    case debtRisk
    case spendingPattern
    case actionSuggestion
}

public enum BudgetPeriod: String, Codable, CaseIterable, Sendable, Hashable {
    case weekly
    case monthly
    case yearly
}

public enum GoalType: String, Codable, CaseIterable, Sendable, Hashable {
    case savings
    case debtPayoff
    case emergencyFund
    case custom
}
