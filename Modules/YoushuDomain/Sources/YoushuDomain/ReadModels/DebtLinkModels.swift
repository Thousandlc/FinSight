import Foundation
import YoushuFoundation

/// DebtMatcher 输出。不可靠时不要自动更新 Debt。
public struct DebtMatchResult: Sendable, Equatable {
    public enum Status: String, Sendable, Equatable {
        case matched
        case pendingConfirmation
        case unmatched
        case ambiguous
    }

    public var status: Status
    public var matchedDebtId: UUID?
    public var confidence: Double
    public var reason: String
    public var candidateDebtIds: [UUID]

    public init(
        status: Status,
        matchedDebtId: UUID? = nil,
        confidence: Double,
        reason: String,
        candidateDebtIds: [UUID] = []
    ) {
        self.status = status
        self.matchedDebtId = matchedDebtId
        self.confidence = min(max(confidence, 0), 1)
        self.reason = reason
        self.candidateDebtIds = candidateDebtIds
    }

    public static func unmatched(reason: String) -> DebtMatchResult {
        DebtMatchResult(status: .unmatched, confidence: 0, reason: reason)
    }
}

/// 待用户确认的 Transaction → Debt 关联。
public struct PendingDebtLink: Identifiable, Hashable, Codable, Sendable {
    public enum Status: String, Codable, Sendable {
        case pending
        case confirmed
        case ignored
    }

    public let id: UUID
    public var userId: UUID
    public var transactionId: UUID
    public var suggestedDebtId: UUID?
    public var candidateDebtIds: [UUID]
    public var confidence: Double
    public var reason: String
    public var status: Status
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        userId: UUID,
        transactionId: UUID,
        suggestedDebtId: UUID? = nil,
        candidateDebtIds: [UUID] = [],
        confidence: Double,
        reason: String,
        status: Status = .pending,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.transactionId = transactionId
        self.suggestedDebtId = suggestedDebtId
        self.candidateDebtIds = candidateDebtIds
        self.confidence = min(max(confidence, 0), 1)
        self.reason = reason
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// 疑似周期性还款发现的债务候选（确认前非正式 Debt）。
public struct SuspectedDebt: Identifiable, Hashable, Codable, Sendable {
    public enum Status: String, Codable, Sendable {
        case pending
        case confirmed
        case ignored
    }

    public let id: UUID
    public var userId: UUID
    public var merchant: String
    public var amount: Money
    public var dayOfMonth: Int
    public var occurrenceCount: Int
    public var sampleTransactionIds: [UUID]
    public var reason: String
    public var status: Status
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        userId: UUID,
        merchant: String,
        amount: Money,
        dayOfMonth: Int,
        occurrenceCount: Int,
        sampleTransactionIds: [UUID],
        reason: String,
        status: Status = .pending,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.merchant = merchant
        self.amount = amount
        self.dayOfMonth = dayOfMonth
        self.occurrenceCount = occurrenceCount
        self.sampleTransactionIds = sampleTransactionIds
        self.reason = reason
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public enum DebtLinkOutcome: Sendable, Equatable {
    case autoLinked(debtId: UUID, eventId: UUID)
    case pendingConfirmation(PendingDebtLink)
    case unmatched(reason: String)
    case skipped(reason: String)
}
