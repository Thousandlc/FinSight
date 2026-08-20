import Foundation
import YoushuDomain

/// Wires Domain overview services to repository ports.
public struct OverviewServiceContainer: Sendable {
    public let home: any HomeOverviewProviding
    public let transactions: any TransactionListProviding
    public let debts: any DebtListProviding
    public let debtManager: any DebtManaging
    public let debtDetail: any DebtDetailProviding
    public let assets: any AssetListProviding
    public let aiAssistant: any AIAssistantProviding
    public let financialAssistant: FinancialAssistantService
    public let accounts: any AccountListProviding
    public let accountManager: any AccountManaging
    public let currentUser: any CurrentUserProviding

    public init(
        accounts: any AccountRepository,
        transactions: any TransactionRepository,
        debts: any DebtRepository,
        debtEvents: any DebtEventRepository,
        repaymentPlans: any RepaymentPlanRepository,
        assets: any AssetRepository,
        budgets: any BudgetRepository,
        goals: any GoalRepository,
        insights: any FinancialInsightRepository,
        users: any UserRepository,
        financialAssisting: any FinancialAssisting,
        consentService: AIDataConsentService? = nil
    ) {
        let assistantService = FinancialAssistantService(
            accounts: accounts,
            transactions: transactions,
            debts: debts,
            repaymentPlans: repaymentPlans,
            assets: assets,
            budgets: budgets,
            goals: goals,
            insights: insights,
            users: users,
            assistant: financialAssisting,
            consentService: consentService
        )
        self.financialAssistant = assistantService
        self.home = HomeOverviewService(
            accounts: accounts,
            transactions: transactions,
            debts: debts,
            repaymentPlans: repaymentPlans,
            assets: assets,
            budgets: budgets,
            goals: goals,
            insights: insights,
            users: users,
            financialAssistant: financialAssisting,
            consentService: consentService
        )
        self.transactions = TransactionListService(transactions: transactions, accounts: accounts)
        let debtList = DebtListService(debts: debts, events: debtEvents)
        let debtService = DebtService(
            debts: debts,
            events: debtEvents,
            accounts: accounts,
            transactions: transactions,
            users: users
        )
        self.debts = debtList
        self.debtManager = debtService
        self.debtDetail = debtService
        self.assets = AssetListService(assets: assets)
        self.aiAssistant = AIAssistantService(insights: insights, assistant: assistantService)
        self.accounts = AccountListService(
            accounts: accounts,
            transactions: transactions,
            debts: debts
        )
        self.accountManager = AccountService(
            accounts: accounts,
            transactions: transactions,
            debts: debts
        )
        self.currentUser = RepositoryCurrentUserProvider(users: users)
    }

    public init(
        repositories: RepositoryContainer,
        financialAssisting: any FinancialAssisting,
        consentService: AIDataConsentService? = nil
    ) {
        self.init(
            accounts: repositories.accounts,
            transactions: repositories.transactions,
            debts: repositories.debts,
            debtEvents: repositories.debtEvents,
            repaymentPlans: repositories.repaymentPlans,
            assets: repositories.assets,
            budgets: repositories.budgets,
            goals: repositories.goals,
            insights: repositories.insights,
            users: repositories.users,
            financialAssisting: financialAssisting,
            consentService: consentService
        )
    }
}
