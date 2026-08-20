import Foundation
import YoushuDomain

/// Facade that wires Domain repository ports to the local store.
public struct RepositoryContainer: Sendable {
    public let users: any UserRepository
    public let accounts: any AccountRepository
    public let transactions: any TransactionRepository
    public let debts: any DebtRepository
    public let debtEvents: any DebtEventRepository
    public let repaymentPlans: any RepaymentPlanRepository
    public let assets: any AssetRepository
    public let budgets: any BudgetRepository
    public let goals: any GoalRepository
    public let insights: any FinancialInsightRepository
    public let pendingDebtLinks: any PendingDebtLinkRepository
    public let suspectedDebts: any SuspectedDebtRepository
    public let aiDataConsents: any AIDataConsentRepository
    public let aiRecognitionRecords: any AIRecognitionRecordRepository
    public let mediaArtifacts: any MediaArtifactRepository
    public let store: YoushuStore

    public init(store: YoushuStore) {
        self.store = store
        self.users = LocalUserRepository(store: store)
        self.accounts = LocalAccountRepository(store: store)
        self.transactions = LocalTransactionRepository(store: store)
        self.debts = LocalDebtRepository(store: store)
        self.debtEvents = LocalDebtEventRepository(store: store)
        self.repaymentPlans = LocalRepaymentPlanRepository(store: store)
        self.assets = LocalAssetRepository(store: store)
        self.budgets = LocalBudgetRepository(store: store)
        self.goals = LocalGoalRepository(store: store)
        self.insights = LocalFinancialInsightRepository(store: store)
        self.pendingDebtLinks = LocalPendingDebtLinkRepository(store: store)
        self.suspectedDebts = LocalSuspectedDebtRepository(store: store)
        self.aiDataConsents = LocalAIDataConsentRepository(store: store)
        self.aiRecognitionRecords = LocalAIRecognitionRecordRepository(store: store)
        self.mediaArtifacts = LocalMediaArtifactRepository(store: store)
    }

    public static func inMemory() -> RepositoryContainer {
        RepositoryContainer(store: YoushuStore())
    }

    public static func fileBacked(url: URL) -> RepositoryContainer {
        RepositoryContainer(store: YoushuStore(fileURL: url))
    }
}
