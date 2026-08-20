import Foundation
import YoushuFoundation

public struct RecurringRule: Hashable, Codable, Sendable {
    public var frequency: PaymentFrequency
    public var interval: Int
    public var nextDate: Date?
    public var endDate: Date?

    public init(
        frequency: PaymentFrequency,
        interval: Int = 1,
        nextDate: Date? = nil,
        endDate: Date? = nil
    ) {
        self.frequency = frequency
        self.interval = max(1, interval)
        self.nextDate = nextDate
        self.endDate = endDate
    }
}

/// Underlying financial fact. Do not treat derived aggregates as authoritative over transactions.
public struct Transaction: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var userId: UUID
    public var accountId: UUID
    public var amount: Money
    public var date: Date
    public var merchant: String?
    public var category: String?
    public var transactionType: TransactionType
    public var currencyCode: String
    public var note: String?
    public var tags: [String]
    public var sourceImageId: String?
    public var relatedDebtId: UUID?
    public var transferCounterpartyAccountId: UUID?
    public var recurringRule: RecurringRule?
    public var recognitionConfidence: Double?
    public var source: TransactionSource
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        userId: UUID,
        accountId: UUID,
        amount: Money,
        date: Date = Date(),
        merchant: String? = nil,
        category: String? = nil,
        transactionType: TransactionType,
        currencyCode: String? = nil,
        note: String? = nil,
        tags: [String] = [],
        sourceImageId: String? = nil,
        relatedDebtId: UUID? = nil,
        transferCounterpartyAccountId: UUID? = nil,
        recurringRule: RecurringRule? = nil,
        recognitionConfidence: Double? = nil,
        source: TransactionSource = .manual,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.accountId = accountId
        self.amount = amount
        self.date = date
        self.merchant = merchant
        self.category = category
        self.transactionType = transactionType
        self.currencyCode = (currencyCode ?? amount.currencyCode).uppercased()
        self.note = note
        self.tags = tags
        self.sourceImageId = sourceImageId
        self.relatedDebtId = relatedDebtId
        self.transferCounterpartyAccountId = transferCounterpartyAccountId
        self.recurringRule = recurringRule
        self.recognitionConfidence = recognitionConfidence.map { min(max($0, 0), 1) }
        self.source = source
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
