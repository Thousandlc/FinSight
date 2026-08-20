import Foundation
import Testing
import YoushuAI
import YoushuData
import YoushuDomain
import YoushuFoundation

@Suite("Home overview stored summary freshness (ADR-032 Step 3)")
struct HomeOverviewFreshnessTests {
    private final class RecordingTransport: GatewayHTTPTransport, @unchecked Sendable {
        private(set) var performCount = 0

        func perform(_ request: GatewayHTTPRequest) async throws -> GatewayHTTPResponse {
            performCount += 1
            let requestId = request.headers["X-Youshu-Request-Id"] ?? "req-test"
            let json = """
            {"schemaVersion":"v1","requestId":"\(requestId)","modelAlias":"mock-qwen","draft":{"title":"重新生成摘要","body":"remote regenerated current summary","answer":"remote regenerated current summary","citedFactKeys":["primaryPressure"],"unknowns":[],"confidence":0.9,"keyFacts":[],"warnings":[],"actions":[],"references":[]}}
            """
            return GatewayHTTPResponse(statusCode: 200, data: Data(json.utf8))
        }
    }

    private final class FailingTransport: GatewayHTTPTransport, @unchecked Sendable {
        private(set) var performCount = 0

        func perform(_ request: GatewayHTTPRequest) async throws -> GatewayHTTPResponse {
            performCount += 1
            return GatewayHTTPResponse(
                statusCode: 401,
                data: Data("""
                {"schemaVersion":"v1","requestId":"req-fail","error":{"code":"unauthorized","message":"unauthorized"}}
                """.utf8)
            )
        }
    }

    private struct ThrowingAccountRepository: AccountRepository {
        func upsert(_ account: Account) async throws {}
        func fetch(id: UUID) async throws -> Account? { nil }
        func fetchAll(userId: UUID) async throws -> [Account] {
            throw DataError.persistenceFailed("simulated repository failure")
        }
        func delete(id: UUID) async throws {}
    }

    private func seedLedger(container: RepositoryContainer, userId: UUID) async throws -> Account {
        try await container.users.upsert(User(id: userId, displayName: "FreshnessHome"))
        let account = Account(
            userId: userId,
            name: "银行",
            type: .bankCard,
            openingBalance: Money(amount: 10_000, currencyCode: "CNY")
        )
        try await container.accounts.upsert(account)
        let txService = TransactionService(
            accounts: container.accounts,
            transactions: container.transactions
        )
        _ = try await txService.record(
            RecordTransactionInput(
                amount: 5_000,
                merchant: "公司",
                category: "工资",
                accountId: account.id,
                formType: .income
            ),
            userId: userId
        )
        _ = try await txService.record(
            RecordTransactionInput(
                amount: 1_000,
                merchant: "生活",
                category: "生活",
                accountId: account.id,
                formType: .expense
            ),
            userId: userId
        )
        return account
    }

    private func makeAssistantService(container: RepositoryContainer) -> FinancialAssistantService {
        FinancialAssistantService(
            accounts: container.accounts,
            transactions: container.transactions,
            debts: container.debts,
            repaymentPlans: container.repaymentPlans,
            assets: container.assets,
            budgets: container.budgets,
            goals: container.goals,
            insights: container.insights,
            users: container.users,
            assistant: MockAIProvider()
        )
    }

    private func makeRemoteHome(
        container: RepositoryContainer,
        transport: any GatewayHTTPTransport,
        consentService: AIDataConsentService
    ) -> HomeOverviewService {
        let client = AIGatewayClient(
            configuration: AIGatewayConfiguration(baseURL: URL(string: "http://127.0.0.1:8080")!),
            transport: transport
        )
        let router = FinancialAssistingRouter(
            mode: .remoteMonthlySummaryOnly,
            remote: RemoteFinancialAIProvider(client: client)
        )
        return HomeOverviewService(
            accounts: container.accounts,
            transactions: container.transactions,
            debts: container.debts,
            repaymentPlans: container.repaymentPlans,
            assets: container.assets,
            budgets: container.budgets,
            goals: container.goals,
            insights: container.insights,
            users: container.users,
            financialAssistant: router,
            consentService: consentService
        )
    }

    private func summaryInsights(userId: UUID, container: RepositoryContainer) async throws -> [FinancialInsight] {
        try await container.insights.fetchAll(userId: userId).filter { $0.type == .summary }
    }

    @Test("fresh persisted summary is reused without provider regeneration")
    func freshPersistedSummaryReused() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        _ = try await seedLedger(container: container, userId: userId)
        let assistant = makeAssistantService(container: container)
        let persisted = try await assistant.generateMonthlySummary(userId: userId)

        let transport = RecordingTransport()
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        _ = try await consentService.acceptAssistantPrivacy(userId: userId)
        let home = makeRemoteHome(container: container, transport: transport, consentService: consentService)

        let overview = try await home.loadOverview(userId: userId)

        #expect(transport.performCount == 0)
        #expect(overview.aiSummary?.id == persisted.id)
        #expect(overview.aiSummary?.body == persisted.body)
        #expect(try await summaryInsights(userId: userId, container: container).count == 1)
    }

    @Test("fact change makes persisted summary stale and triggers regeneration")
    func factChangeMakesSummaryStale() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        let account = try await seedLedger(container: container, userId: userId)
        let assistant = makeAssistantService(container: container)
        let persisted = try await assistant.generateMonthlySummary(userId: userId)

        let txService = TransactionService(
            accounts: container.accounts,
            transactions: container.transactions
        )
        _ = try await txService.record(
            RecordTransactionInput(
                amount: 2_000,
                merchant: "奖金",
                category: "工资",
                accountId: account.id,
                formType: .income
            ),
            userId: userId
        )

        let transport = RecordingTransport()
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        _ = try await consentService.acceptAssistantPrivacy(userId: userId)
        let home = makeRemoteHome(container: container, transport: transport, consentService: consentService)

        let overview = try await home.loadOverview(userId: userId)

        #expect(transport.performCount == 1)
        #expect(overview.aiSummary?.id != persisted.id)
        #expect(overview.aiSummary?.body.contains("remote regenerated current summary") == true)
        #expect(overview.aiSummary?.body != persisted.body)

        let summaries = try await summaryInsights(userId: userId, container: container)
        #expect(summaries.contains(where: { $0.id == persisted.id }))
        #expect(summaries.contains(where: { $0.body.contains("remote regenerated current summary") }))
    }

    @Test("policy version mismatch makes stored summary stale")
    func policyVersionMismatchMakesSummaryStale() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        _ = try await seedLedger(container: container, userId: userId)
        let assistant = makeAssistantService(container: container)
        var persisted = try await assistant.generateMonthlySummary(userId: userId)
        var staleMetadata = persisted.freshnessMetadata
        staleMetadata?.policyVersion = "v0-legacy-test"
        persisted.freshnessMetadata = staleMetadata
        try await container.insights.upsert(persisted)

        let transport = RecordingTransport()
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        _ = try await consentService.acceptAssistantPrivacy(userId: userId)
        let home = makeRemoteHome(container: container, transport: transport, consentService: consentService)

        let overview = try await home.loadOverview(userId: userId)

        #expect(transport.performCount == 1)
        #expect(overview.aiSummary?.body.contains("remote regenerated current summary") == true)
        #expect(overview.aiSummary?.body != persisted.body)
    }

    @Test("legacy nil-metadata summary is treated as cache miss without deletion")
    func legacyNilMetadataTreatedAsCacheMiss() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        _ = try await seedLedger(container: container, userId: userId)
        let legacy = FinancialInsight(
            userId: userId,
            type: .summary,
            title: "legacy summary",
            body: "legacy stale body",
            modelName: "mock",
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try await container.insights.upsert(legacy)

        let transport = RecordingTransport()
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        _ = try await consentService.acceptAssistantPrivacy(userId: userId)
        let home = makeRemoteHome(container: container, transport: transport, consentService: consentService)

        let overview = try await home.loadOverview(userId: userId)

        #expect(transport.performCount == 1)
        #expect(overview.aiSummary?.body != legacy.body)
        let summaries = try await summaryInsights(userId: userId, container: container)
        #expect(summaries.contains(where: { $0.id == legacy.id && $0.body == legacy.body }))
    }

    @Test("stale summary with AI success persists replacement with freshness metadata")
    func staleSummaryAIReplacementPersistsFreshness() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        let account = try await seedLedger(container: container, userId: userId)
        let assistant = makeAssistantService(container: container)
        let persisted = try await assistant.generateMonthlySummary(userId: userId)

        let txService = TransactionService(
            accounts: container.accounts,
            transactions: container.transactions
        )
        _ = try await txService.record(
            RecordTransactionInput(
                amount: 500,
                merchant: "额外支出",
                category: "生活",
                accountId: account.id,
                formType: .expense
            ),
            userId: userId
        )

        let transport = RecordingTransport()
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        _ = try await consentService.acceptAssistantPrivacy(userId: userId)
        let home = makeRemoteHome(container: container, transport: transport, consentService: consentService)

        _ = try await home.loadOverview(userId: userId)

        let summaries = try await summaryInsights(userId: userId, container: container)
        let regenerated = summaries.first(where: { $0.body.contains("remote regenerated current summary") })
        #expect(regenerated?.freshnessMetadata != nil)
        #expect(regenerated?.freshnessMetadata?.schemaVersion == StoredInsightFreshnessSchemaVersion.current)
        #expect(regenerated?.freshnessMetadata?.policyVersion == FinancialRiskPolicyVersion.current)
        #expect(summaries.contains(where: { $0.id == persisted.id }))
    }

    @Test("stale summary with AI failure still loads Home with deterministic fallback")
    func staleSummaryAIFailureUsesDeterministicFallback() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        let account = try await seedLedger(container: container, userId: userId)
        let assistant = makeAssistantService(container: container)
        let persisted = try await assistant.generateMonthlySummary(userId: userId)

        let txService = TransactionService(
            accounts: container.accounts,
            transactions: container.transactions
        )
        _ = try await txService.record(
            RecordTransactionInput(
                amount: 500,
                merchant: "额外支出",
                category: "生活",
                accountId: account.id,
                formType: .expense
            ),
            userId: userId
        )

        let transport = FailingTransport()
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        _ = try await consentService.acceptAssistantPrivacy(userId: userId)
        let home = makeRemoteHome(container: container, transport: transport, consentService: consentService)

        let overview = try await home.loadOverview(userId: userId)

        #expect(transport.performCount == 1)
        #expect(overview.aiSummary?.modelName == "deterministic")
        #expect(overview.aiSummary?.body != persisted.body)
        #expect(try await summaryInsights(userId: userId, container: container).count == 1)
    }

    @Test("legacy summary with consent denied uses deterministic path without remote request")
    func legacySummaryConsentDeniedUsesDeterministic() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        _ = try await seedLedger(container: container, userId: userId)
        let legacy = FinancialInsight(
            userId: userId,
            type: .summary,
            title: "legacy summary",
            body: "legacy stale body",
            modelName: "mock"
        )
        try await container.insights.upsert(legacy)

        let transport = FailingTransport()
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        let home = makeRemoteHome(container: container, transport: transport, consentService: consentService)

        let overview = try await home.loadOverview(userId: userId)

        #expect(transport.performCount == 0)
        #expect(overview.aiSummary?.modelName == "deterministic")
        #expect(overview.aiSummary?.body != legacy.body)
        #expect(try await summaryInsights(userId: userId, container: container).count == 1)
    }

    @Test("core repository failure still surfaces Home load error")
    func coreRepositoryFailureStillThrows() async {
        let home = HomeOverviewService(
            accounts: ThrowingAccountRepository(),
            transactions: InMemoryTransactionRepository(),
            debts: InMemoryDebtRepository(),
            repaymentPlans: InMemoryRepaymentPlanRepository(),
            assets: InMemoryAssetRepository(),
            budgets: InMemoryBudgetRepository(),
            goals: InMemoryGoalRepository(),
            insights: InMemoryInsightRepository(),
            users: InMemoryUserRepository(),
            financialAssistant: MockAIProvider()
        )
        await #expect(throws: DataError.self) {
            _ = try await home.loadOverview(userId: UUID())
        }
    }

    @Test("proactive insights remain unaffected by Home summary freshness resolution")
    func proactiveInsightsUnaffected() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        _ = try await seedLedger(container: container, userId: userId)
        let assistant = makeAssistantService(container: container)
        let proactive = try await assistant.refreshProactiveInsights(userId: userId)
        #expect(!proactive.isEmpty)
        for insight in proactive {
            #expect(insight.type != .summary)
            #expect(insight.freshnessMetadata == nil)
        }
    }
}

private actor InMemoryTransactionRepository: TransactionRepository {
    func upsert(_ transaction: Transaction) async throws {}
    func fetch(id: UUID) async throws -> Transaction? { nil }
    func fetchAll(userId: UUID) async throws -> [Transaction] { [] }
    func fetchAll(accountId: UUID) async throws -> [Transaction] { [] }
    func fetchAll(relatedDebtId: UUID) async throws -> [Transaction] { [] }
    func delete(id: UUID) async throws {}
}

private actor InMemoryDebtRepository: DebtRepository {
    func upsert(_ debt: Debt) async throws {}
    func fetch(id: UUID) async throws -> Debt? { nil }
    func fetchAll(userId: UUID) async throws -> [Debt] { [] }
    func delete(id: UUID) async throws {}
}

private actor InMemoryRepaymentPlanRepository: RepaymentPlanRepository {
    func upsert(_ plan: RepaymentPlan) async throws {}
    func fetch(id: UUID) async throws -> RepaymentPlan? { nil }
    func fetchAll(userId: UUID) async throws -> [RepaymentPlan] { [] }
    func fetchAll(debtId: UUID) async throws -> [RepaymentPlan] { [] }
    func delete(id: UUID) async throws {}
}

private actor InMemoryAssetRepository: AssetRepository {
    func upsert(_ asset: Asset) async throws {}
    func fetch(id: UUID) async throws -> Asset? { nil }
    func fetchAll(userId: UUID) async throws -> [Asset] { [] }
    func delete(id: UUID) async throws {}
}

private actor InMemoryBudgetRepository: BudgetRepository {
    func upsert(_ budget: Budget) async throws {}
    func fetch(id: UUID) async throws -> Budget? { nil }
    func fetchAll(userId: UUID) async throws -> [Budget] { [] }
    func delete(id: UUID) async throws {}
}

private actor InMemoryGoalRepository: GoalRepository {
    func upsert(_ goal: Goal) async throws {}
    func fetch(id: UUID) async throws -> Goal? { nil }
    func fetchAll(userId: UUID) async throws -> [Goal] { [] }
    func delete(id: UUID) async throws {}
}

private actor InMemoryInsightRepository: FinancialInsightRepository {
    func upsert(_ insight: FinancialInsight) async throws {}
    func fetch(id: UUID) async throws -> FinancialInsight? { nil }
    func fetchAll(userId: UUID) async throws -> [FinancialInsight] { [] }
    func delete(id: UUID) async throws {}
}

private actor InMemoryUserRepository: UserRepository {
    func upsert(_ user: User) async throws {}
    func fetch(id: UUID) async throws -> User? { nil }
    func fetchAll() async throws -> [User] { [] }
    func delete(id: UUID) async throws {}
}
