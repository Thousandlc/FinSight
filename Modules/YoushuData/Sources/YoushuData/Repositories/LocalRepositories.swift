import Foundation
import YoushuDomain

public struct LocalUserRepository: UserRepository {
    private let store: YoushuStore

    public init(store: YoushuStore) {
        self.store = store
    }

    public func upsert(_ user: User) async throws {
        try await store.upsertUser(user)
    }

    public func fetch(id: UUID) async throws -> User? {
        await store.fetchUser(id: id)
    }

    public func fetchAll() async throws -> [User] {
        await store.fetchAllUsers()
    }

    public func delete(id: UUID) async throws {
        try await store.deleteUser(id: id)
    }
}

public struct LocalAccountRepository: AccountRepository {
    private let store: YoushuStore

    public init(store: YoushuStore) {
        self.store = store
    }

    public func upsert(_ account: Account) async throws {
        try await store.upsertAccount(account)
    }

    public func fetch(id: UUID) async throws -> Account? {
        await store.fetchAccount(id: id)
    }

    public func fetchAll(userId: UUID) async throws -> [Account] {
        await store.fetchAccounts(userId: userId)
    }

    public func delete(id: UUID) async throws {
        try await store.deleteAccount(id: id)
    }
}

public struct LocalTransactionRepository: TransactionRepository {
    private let store: YoushuStore

    public init(store: YoushuStore) {
        self.store = store
    }

    public func upsert(_ transaction: Transaction) async throws {
        try await store.upsertTransaction(transaction)
    }

    public func fetch(id: UUID) async throws -> Transaction? {
        await store.fetchTransaction(id: id)
    }

    public func fetchAll(userId: UUID) async throws -> [Transaction] {
        await store.fetchTransactions(userId: userId)
    }

    public func fetchAll(accountId: UUID) async throws -> [Transaction] {
        await store.fetchTransactions(accountId: accountId)
    }

    public func fetchAll(relatedDebtId: UUID) async throws -> [Transaction] {
        await store.fetchTransactions(relatedDebtId: relatedDebtId)
    }

    public func delete(id: UUID) async throws {
        try await store.deleteTransaction(id: id)
    }
}

public struct LocalDebtRepository: DebtRepository {
    private let store: YoushuStore

    public init(store: YoushuStore) {
        self.store = store
    }

    public func upsert(_ debt: Debt) async throws {
        try await store.upsertDebt(debt)
    }

    public func fetch(id: UUID) async throws -> Debt? {
        await store.fetchDebt(id: id)
    }

    public func fetchAll(userId: UUID) async throws -> [Debt] {
        await store.fetchDebts(userId: userId)
    }

    public func delete(id: UUID) async throws {
        try await store.deleteDebt(id: id)
    }
}

public struct LocalDebtEventRepository: DebtEventRepository {
    private let store: YoushuStore

    public init(store: YoushuStore) {
        self.store = store
    }

    public func upsert(_ event: DebtEvent) async throws {
        try await store.upsertDebtEvent(event)
    }

    public func fetch(id: UUID) async throws -> DebtEvent? {
        await store.fetchDebtEvent(id: id)
    }

    public func fetchAll(debtId: UUID) async throws -> [DebtEvent] {
        await store.fetchDebtEvents(debtId: debtId)
    }

    public func delete(id: UUID) async throws {
        try await store.deleteDebtEvent(id: id)
    }
}

public struct LocalRepaymentPlanRepository: RepaymentPlanRepository {
    private let store: YoushuStore

    public init(store: YoushuStore) {
        self.store = store
    }

    public func upsert(_ plan: RepaymentPlan) async throws {
        try await store.upsertRepaymentPlan(plan)
    }

    public func fetch(id: UUID) async throws -> RepaymentPlan? {
        await store.fetchRepaymentPlan(id: id)
    }

    public func fetchAll(debtId: UUID) async throws -> [RepaymentPlan] {
        await store.fetchRepaymentPlans(debtId: debtId)
    }

    public func fetchAll(userId: UUID) async throws -> [RepaymentPlan] {
        await store.fetchRepaymentPlans(userId: userId)
    }

    public func delete(id: UUID) async throws {
        try await store.deleteRepaymentPlan(id: id)
    }
}

public struct LocalAssetRepository: AssetRepository {
    private let store: YoushuStore

    public init(store: YoushuStore) {
        self.store = store
    }

    public func upsert(_ asset: Asset) async throws {
        try await store.upsertAsset(asset)
    }

    public func fetchAll(userId: UUID) async throws -> [Asset] {
        await store.fetchAssets(userId: userId)
    }

    public func delete(id: UUID) async throws {
        try await store.deleteAsset(id: id)
    }
}

public struct LocalBudgetRepository: BudgetRepository {
    private let store: YoushuStore

    public init(store: YoushuStore) {
        self.store = store
    }

    public func upsert(_ budget: Budget) async throws {
        try await store.upsertBudget(budget)
    }

    public func fetchAll(userId: UUID) async throws -> [Budget] {
        await store.fetchBudgets(userId: userId)
    }

    public func delete(id: UUID) async throws {
        try await store.deleteBudget(id: id)
    }
}

public struct LocalGoalRepository: GoalRepository {
    private let store: YoushuStore

    public init(store: YoushuStore) {
        self.store = store
    }

    public func upsert(_ goal: Goal) async throws {
        try await store.upsertGoal(goal)
    }

    public func fetchAll(userId: UUID) async throws -> [Goal] {
        await store.fetchGoals(userId: userId)
    }

    public func delete(id: UUID) async throws {
        try await store.deleteGoal(id: id)
    }
}

public struct LocalFinancialInsightRepository: FinancialInsightRepository {
    private let store: YoushuStore

    public init(store: YoushuStore) {
        self.store = store
    }

    public func upsert(_ insight: FinancialInsight) async throws {
        try await store.upsertInsight(insight)
    }

    public func fetchAll(userId: UUID) async throws -> [FinancialInsight] {
        await store.fetchInsights(userId: userId)
    }

    public func delete(id: UUID) async throws {
        try await store.deleteInsight(id: id)
    }
}

public struct LocalPendingDebtLinkRepository: PendingDebtLinkRepository {
    private let store: YoushuStore

    public init(store: YoushuStore) {
        self.store = store
    }

    public func upsert(_ link: PendingDebtLink) async throws {
        try await store.upsertPendingDebtLink(link)
    }

    public func fetch(id: UUID) async throws -> PendingDebtLink? {
        await store.fetchPendingDebtLink(id: id)
    }

    public func fetchPending(userId: UUID) async throws -> [PendingDebtLink] {
        await store.fetchPendingDebtLinks(userId: userId, pendingOnly: true)
    }

    public func fetchAll(userId: UUID) async throws -> [PendingDebtLink] {
        await store.fetchPendingDebtLinks(userId: userId, pendingOnly: false)
    }

    public func delete(id: UUID) async throws {
        try await store.deletePendingDebtLink(id: id)
    }
}

public struct LocalSuspectedDebtRepository: SuspectedDebtRepository {
    private let store: YoushuStore

    public init(store: YoushuStore) {
        self.store = store
    }

    public func upsert(_ suspected: SuspectedDebt) async throws {
        try await store.upsertSuspectedDebt(suspected)
    }

    public func fetch(id: UUID) async throws -> SuspectedDebt? {
        await store.fetchSuspectedDebt(id: id)
    }

    public func fetchPending(userId: UUID) async throws -> [SuspectedDebt] {
        await store.fetchSuspectedDebts(userId: userId, pendingOnly: true)
    }

    public func fetchAll(userId: UUID) async throws -> [SuspectedDebt] {
        await store.fetchSuspectedDebts(userId: userId, pendingOnly: false)
    }

    public func delete(id: UUID) async throws {
        try await store.deleteSuspectedDebt(id: id)
    }
}

public struct LocalAIDataConsentRepository: AIDataConsentRepository {
    private let store: YoushuStore

    public init(store: YoushuStore) {
        self.store = store
    }

    public func upsert(_ consent: AIDataConsent) async throws {
        try await store.upsertAIDataConsent(consent)
    }

    public func fetch(userId: UUID) async throws -> AIDataConsent? {
        await store.fetchAIDataConsent(userId: userId)
    }

    public func delete(userId: UUID) async throws {
        try await store.deleteAIDataConsent(userId: userId)
    }
}

public struct LocalAIRecognitionRecordRepository: AIRecognitionRecordRepository {
    private let store: YoushuStore

    public init(store: YoushuStore) {
        self.store = store
    }

    public func upsert(_ record: AIRecognitionRecord) async throws {
        try await store.upsertAIRecognitionRecord(record)
    }

    public func fetch(id: UUID) async throws -> AIRecognitionRecord? {
        await store.fetchAIRecognitionRecord(id: id)
    }

    public func fetchAll(userId: UUID) async throws -> [AIRecognitionRecord] {
        await store.fetchAIRecognitionRecords(userId: userId)
    }

    public func delete(id: UUID) async throws {
        try await store.deleteAIRecognitionRecord(id: id)
    }

    public func deleteAll(userId: UUID) async throws {
        try await store.deleteAIRecognitionRecords(userId: userId)
    }
}

public struct LocalMediaArtifactRepository: MediaArtifactRepository {
    private let store: YoushuStore

    public init(store: YoushuStore) {
        self.store = store
    }

    public func upsert(_ artifact: MediaArtifact) async throws {
        try await store.upsertMediaArtifact(artifact)
    }

    public func fetch(id: String) async throws -> MediaArtifact? {
        await store.fetchMediaArtifact(id: id)
    }

    public func fetchAll(userId: UUID) async throws -> [MediaArtifact] {
        await store.fetchMediaArtifacts(userId: userId)
    }

    public func delete(id: String) async throws {
        try await store.deleteMediaArtifact(id: id)
    }

    public func deleteAll(userId: UUID) async throws {
        try await store.deleteMediaArtifacts(userId: userId)
    }
}
