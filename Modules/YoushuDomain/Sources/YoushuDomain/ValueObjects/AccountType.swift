import Foundation

public enum AccountType: String, Codable, CaseIterable, Sendable, Hashable {
    case cash
    case bankCard
    case creditCard
    case alipay
    case weChat
    case investment

    /// 计入「可用资金」的资产类账户。
    public var isAsset: Bool {
        switch self {
        case .cash, .bankCard, .alipay, .weChat, .investment:
            return true
        case .creditCard:
            return false
        }
    }

    public var isLiability: Bool { self == .creditCard }

    public var displayName: String {
        switch self {
        case .cash: return "现金"
        case .bankCard: return "银行卡"
        case .creditCard: return "信用卡"
        case .alipay: return "支付宝"
        case .weChat: return "微信"
        case .investment: return "投资"
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "checking", "savings", "loan", "other":
            self = .bankCard
        default:
            guard let value = AccountType(rawValue: raw) else {
                self = .cash
                return
            }
            self = value
        }
    }
}
