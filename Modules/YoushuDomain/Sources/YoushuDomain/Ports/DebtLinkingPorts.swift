import Foundation

/// 可选 AI 辅助提示。不得单独决定 Debt 更新。
public protocol DebtMatchAssisting: Sendable {
    func suggestDebtId(for transaction: Transaction, candidateDebtIds: [UUID]) async throws -> UUID?
}

public struct NoOpDebtMatchAssistant: DebtMatchAssisting {
    public init() {}
    public func suggestDebtId(for transaction: Transaction, candidateDebtIds: [UUID]) async throws -> UUID? {
        _ = transaction
        _ = candidateDebtIds
        return nil
    }
}

public protocol PendingDebtLinkRepository: Sendable {
    func upsert(_ link: PendingDebtLink) async throws
    func fetch(id: UUID) async throws -> PendingDebtLink?
    func fetchPending(userId: UUID) async throws -> [PendingDebtLink]
    func fetchAll(userId: UUID) async throws -> [PendingDebtLink]
    func delete(id: UUID) async throws
}

public protocol SuspectedDebtRepository: Sendable {
    func upsert(_ suspected: SuspectedDebt) async throws
    func fetch(id: UUID) async throws -> SuspectedDebt?
    func fetchPending(userId: UUID) async throws -> [SuspectedDebt]
    func fetchAll(userId: UUID) async throws -> [SuspectedDebt]
    func delete(id: UUID) async throws
}

public protocol TransactionDebtLinking: Sendable {
    func processNewTransaction(_ transaction: Transaction, userId: UUID) async throws -> DebtLinkOutcome
    func confirmPendingLink(pendingId: UUID, debtId: UUID, userId: UUID) async throws -> Debt
    func ignorePendingLink(pendingId: UUID, userId: UUID) async throws
    func refreshSuspectedDebts(userId: UUID) async throws -> [SuspectedDebt]
    func confirmSuspectedDebt(suspectedId: UUID, userId: UUID) async throws -> Debt
    func ignoreSuspectedDebt(suspectedId: UUID, userId: UUID) async throws
    func pendingLinks(userId: UUID) async throws -> [PendingDebtLink]
}
