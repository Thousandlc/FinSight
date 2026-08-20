import Foundation

/// MVP 基础分类。不使用复杂标签体系。
public enum TransactionCategory {
    public static let transfer = "转账"

    public static let expense: [String] = [
        "餐饮", "交通", "购物", "娱乐", "住房", "医疗", "生活", "教育", "旅行", "其他",
    ]

    public static let income: [String] = [
        "工资", "奖金", "兼职", "投资", "其他",
    ]

    public static func categories(for type: TransactionType) -> [String] {
        switch type {
        case .expense:
            return expense
        case .income:
            return income
        case .transfer:
            return [transfer]
        default:
            return expense
        }
    }

    public static func isValid(_ category: String, for type: TransactionType) -> Bool {
        categories(for: type).contains(category)
    }

    /// 转入账单的展示类型（含转账转入腿）。
    public static func displayType(for transaction: Transaction) -> TransactionType {
        if transaction.transactionType == .income, transaction.category == transfer,
           transaction.transferCounterpartyAccountId != nil {
            return .transfer
        }
        return transaction.transactionType
    }
}

public enum TransactionFormType: String, CaseIterable, Sendable {
    case expense
    case income
    case transfer

    public var transactionType: TransactionType {
        switch self {
        case .expense: .expense
        case .income: .income
        case .transfer: .transfer
        }
    }

    public var title: String {
        switch self {
        case .expense: "支出"
        case .income: "收入"
        case .transfer: "转账"
        }
    }
}
