import Foundation
import YoushuFoundation

public struct Asset: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var userId: UUID
    public var name: String
    public var type: AssetType
    public var currentValue: Money
    public var linkedAccountId: UUID?
    public var note: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        userId: UUID,
        name: String,
        type: AssetType,
        currentValue: Money,
        linkedAccountId: UUID? = nil,
        note: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.type = type
        self.currentValue = currentValue
        self.linkedAccountId = linkedAccountId
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct Budget: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var userId: UUID
    public var name: String
    public var category: String?
    public var limit: Money
    public var period: BudgetPeriod
    public var startDate: Date
    public var endDate: Date?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        userId: UUID,
        name: String,
        category: String? = nil,
        limit: Money,
        period: BudgetPeriod = .monthly,
        startDate: Date = Date(),
        endDate: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.category = category
        self.limit = limit
        self.period = period
        self.startDate = startDate
        self.endDate = endDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct Goal: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var userId: UUID
    public var name: String
    public var type: GoalType
    public var targetAmount: Money
    public var currentAmount: Money
    public var targetDate: Date?
    public var relatedDebtId: UUID?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        userId: UUID,
        name: String,
        type: GoalType,
        targetAmount: Money,
        currentAmount: Money = .zeroCNY,
        targetDate: Date? = nil,
        relatedDebtId: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.type = type
        self.targetAmount = targetAmount
        self.currentAmount = currentAmount
        self.targetDate = targetDate
        self.relatedDebtId = relatedDebtId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct Subscription: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var userId: UUID
    public var name: String
    public var amount: Money
    public var frequency: PaymentFrequency
    public var nextBillingDate: Date?
    public var accountId: UUID?
    public var isActive: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        userId: UUID,
        name: String,
        amount: Money,
        frequency: PaymentFrequency = .monthly,
        nextBillingDate: Date? = nil,
        accountId: UUID? = nil,
        isActive: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.amount = amount
        self.frequency = frequency
        self.nextBillingDate = nextBillingDate
        self.accountId = accountId
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// AI / system conclusion. Must remain traceable to source facts.
public struct FinancialInsight: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var userId: UUID
    public var type: InsightType
    public var title: String
    public var body: String
    public var sourceTransactionIds: [UUID]
    public var sourceDebtIds: [UUID]
    public var sourceAccountIds: [UUID]
    public var modelName: String?
    public var generatedAt: Date
    public var createdAt: Date
    /// Opaque freshness provenance for current monthly `.summary` cache (ADR-032). Nil for legacy/proactive insights.
    public var freshnessMetadata: FinancialInsightFreshnessMetadata?

    public init(
        id: UUID = UUID(),
        userId: UUID,
        type: InsightType,
        title: String,
        body: String,
        sourceTransactionIds: [UUID] = [],
        sourceDebtIds: [UUID] = [],
        sourceAccountIds: [UUID] = [],
        modelName: String? = nil,
        generatedAt: Date = Date(),
        createdAt: Date = Date(),
        freshnessMetadata: FinancialInsightFreshnessMetadata? = nil
    ) {
        self.id = id
        self.userId = userId
        self.type = type
        self.title = title
        self.body = body
        self.sourceTransactionIds = sourceTransactionIds
        self.sourceDebtIds = sourceDebtIds
        self.sourceAccountIds = sourceAccountIds
        self.modelName = modelName
        self.generatedAt = generatedAt
        self.createdAt = createdAt
        self.freshnessMetadata = freshnessMetadata
    }
}
