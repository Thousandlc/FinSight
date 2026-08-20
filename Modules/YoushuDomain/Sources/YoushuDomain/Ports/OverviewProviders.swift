import Foundation

public protocol HomeOverviewProviding: Sendable {
    func loadOverview(userId: UUID) async throws -> HomeOverview
}

public protocol TransactionListProviding: Sendable {
    func loadSnapshot(userId: UUID) async throws -> TransactionListSnapshot
}

public protocol DebtListProviding: Sendable {
    func loadSnapshot(userId: UUID) async throws -> DebtListSnapshot
}

public protocol AssetListProviding: Sendable {
    func loadSnapshot(userId: UUID) async throws -> AssetListSnapshot
}

public protocol AIAssistantProviding: Sendable {
    func loadSnapshot(userId: UUID) async throws -> AIAssistantSnapshot
    func ask(question: String, userId: UUID) async throws -> AssistantAnswer
    func refreshInsights(userId: UUID) async throws -> [FinancialInsight]
}

public protocol CurrentUserProviding: Sendable {
    func currentUserId() async throws -> UUID?
}
