import Foundation
import YoushuFoundation

public struct Account: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var userId: UUID
    public var name: String
    public var type: AccountType
    public var currencyCode: String
    /// 期初余额（事实）。当前余额由 AccountBalanceEngine 从交易派生。
    public var openingBalance: Money
    public var note: String?
    /// 信用卡账户可关联 Debt，分别追踪现金流与欠款。
    public var linkedDebtId: UUID?
    public var institutionName: String?
    public var isArchived: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        userId: UUID,
        name: String,
        type: AccountType,
        currencyCode: String = "CNY",
        openingBalance: Money = .zeroCNY,
        note: String? = nil,
        linkedDebtId: UUID? = nil,
        institutionName: String? = nil,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.type = type
        self.currencyCode = currencyCode.uppercased()
        self.openingBalance = openingBalance
        self.note = note
        self.linkedDebtId = linkedDebtId
        self.institutionName = institutionName
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
