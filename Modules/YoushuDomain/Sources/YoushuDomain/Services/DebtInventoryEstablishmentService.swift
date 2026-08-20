import Foundation

/// Persists debt inventory establishment semantics on `User`. Does not infer from `debts.count`.
public struct DebtInventoryEstablishmentService: Sendable {
    private let users: any UserRepository

    public init(users: any UserRepository) {
        self.users = users
    }

    /// User explicitly confirmed they currently have no debt.
    public func confirmNoDebt(userId: UUID, at: Date = Date()) async throws {
        guard var user = try await users.fetch(id: userId) else {
            throw DomainError.notFound(entity: "User", id: userId)
        }
        user.debtInventoryEstablishment = .confirmedComplete
        user.debtInventoryEstablishmentSource = .userConfirmedNoDebt
        user.debtInventoryEstablishedAt = at
        user.debtImportInProgress = false
        user.updatedAt = at
        try await users.upsert(user)
    }

    /// User reviewed debt inventory and confirmed it is complete.
    public func confirmInventoryComplete(
        userId: UUID,
        source: DebtInventoryEstablishmentSource = .inventoryReviewComplete,
        at: Date = Date()
    ) async throws {
        guard var user = try await users.fetch(id: userId) else {
            throw DomainError.notFound(entity: "User", id: userId)
        }
        user.debtInventoryEstablishment = .confirmedComplete
        user.debtInventoryEstablishmentSource = source
        user.debtInventoryEstablishedAt = at
        user.debtImportInProgress = false
        user.updatedAt = at
        try await users.upsert(user)
    }

    /// Debt import / scan flow started — inventory must not be treated as complete.
    public func beginImport(userId: UUID, at: Date = Date()) async throws {
        guard var user = try await users.fetch(id: userId) else {
            throw DomainError.notFound(entity: "User", id: userId)
        }
        if user.debtInventoryEstablishment == .confirmedComplete { return }
        user.debtInventoryEstablishment = .partial
        user.debtInventoryEstablishmentSource = .importInProgress
        user.debtImportInProgress = true
        user.updatedAt = at
        try await users.upsert(user)
    }

    /// First debt recorded — partial establishment until user confirms completeness.
    public func markPartialFromFirstDebt(userId: UUID, at: Date = Date()) async throws {
        guard var user = try await users.fetch(id: userId) else {
            throw DomainError.notFound(entity: "User", id: userId)
        }
        if user.debtInventoryEstablishment == .confirmedComplete { return }
        user.debtInventoryEstablishment = .partial
        user.debtInventoryEstablishmentSource = .firstDebtRecorded
        user.updatedAt = at
        try await users.upsert(user)
    }

    public func finishImport(userId: UUID, at: Date = Date()) async throws {
        guard var user = try await users.fetch(id: userId) else {
            throw DomainError.notFound(entity: "User", id: userId)
        }
        user.debtImportInProgress = false
        user.updatedAt = at
        try await users.upsert(user)
    }
}
