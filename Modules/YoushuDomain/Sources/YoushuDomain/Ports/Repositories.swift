import Foundation

public protocol UserRepository: Sendable {
    func upsert(_ user: User) async throws
    func fetch(id: UUID) async throws -> User?
    func fetchAll() async throws -> [User]
    func delete(id: UUID) async throws
}

public protocol AccountRepository: Sendable {
    func upsert(_ account: Account) async throws
    func fetch(id: UUID) async throws -> Account?
    func fetchAll(userId: UUID) async throws -> [Account]
    func delete(id: UUID) async throws
}

public protocol TransactionRepository: Sendable {
    func upsert(_ transaction: Transaction) async throws
    func fetch(id: UUID) async throws -> Transaction?
    func fetchAll(userId: UUID) async throws -> [Transaction]
    func fetchAll(accountId: UUID) async throws -> [Transaction]
    func fetchAll(relatedDebtId: UUID) async throws -> [Transaction]
    func delete(id: UUID) async throws
}

public protocol DebtRepository: Sendable {
    func upsert(_ debt: Debt) async throws
    func fetch(id: UUID) async throws -> Debt?
    func fetchAll(userId: UUID) async throws -> [Debt]
    func delete(id: UUID) async throws
}

public protocol DebtEventRepository: Sendable {
    func upsert(_ event: DebtEvent) async throws
    func fetch(id: UUID) async throws -> DebtEvent?
    func fetchAll(debtId: UUID) async throws -> [DebtEvent]
    func delete(id: UUID) async throws
}

public protocol RepaymentPlanRepository: Sendable {
    func upsert(_ plan: RepaymentPlan) async throws
    func fetch(id: UUID) async throws -> RepaymentPlan?
    func fetchAll(debtId: UUID) async throws -> [RepaymentPlan]
    func fetchAll(userId: UUID) async throws -> [RepaymentPlan]
    func delete(id: UUID) async throws
}

public protocol AssetRepository: Sendable {
    func upsert(_ asset: Asset) async throws
    func fetchAll(userId: UUID) async throws -> [Asset]
    func delete(id: UUID) async throws
}

public protocol BudgetRepository: Sendable {
    func upsert(_ budget: Budget) async throws
    func fetchAll(userId: UUID) async throws -> [Budget]
    func delete(id: UUID) async throws
}

public protocol GoalRepository: Sendable {
    func upsert(_ goal: Goal) async throws
    func fetchAll(userId: UUID) async throws -> [Goal]
    func delete(id: UUID) async throws
}

public protocol SubscriptionRepository: Sendable {
    func upsert(_ subscription: Subscription) async throws
    func fetchAll(userId: UUID) async throws -> [Subscription]
    func delete(id: UUID) async throws
}

public protocol FinancialInsightRepository: Sendable {
    func upsert(_ insight: FinancialInsight) async throws
    func fetchAll(userId: UUID) async throws -> [FinancialInsight]
    func delete(id: UUID) async throws
}

public protocol ConfirmedImportProvenanceRepository: Sendable {
    func find(
        userId: UUID,
        capability: ConfirmedImportCapability,
        operationFingerprint: ImportOperationFingerprint
    ) async throws -> ConfirmedImportProvenance?

    func fetch(id: UUID) async throws -> ConfirmedImportProvenance?

    func fetchAll(userId: UUID) async throws -> [ConfirmedImportProvenance]

    /// Creates or merges entity references for the logical provenance key.
    func upsert(_ provenance: ConfirmedImportProvenance) async throws -> ConfirmedImportProvenance

    func removeConfirmedEntity(
        userId: UUID,
        reference: ConfirmedImportEntityReference
    ) async throws

    func deleteAll(userId: UUID) async throws
}
