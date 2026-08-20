import Foundation
import Testing
import YoushuAI
import YoushuData
import YoushuDomain
import YoushuFoundation

@Suite("Stored insight trust boundary")
struct StoredInsightTrustBoundaryTests {
    private final class RecordingTransport: GatewayHTTPTransport, @unchecked Sendable {
        private(set) var performCount = 0

        func perform(_ request: GatewayHTTPRequest) async throws -> GatewayHTTPResponse {
            performCount += 1
            let requestId = request.headers["X-Youshu-Request-Id"] ?? "req-test"
            let json = """
            {"schemaVersion":"v1","requestId":"\(requestId)","modelAlias":"mock-qwen","draft":{"title":"不应被调用","body":"remote regenerated","answer":"remote regenerated","citedFactKeys":["primaryPressure"],"unknowns":[],"confidence":0.9,"keyFacts":[],"warnings":[],"actions":[],"references":[]}}
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

    private func seedLedger(container: RepositoryContainer, userId: UUID) async throws -> Account {
        try await container.users.upsert(User(id: userId, displayName: "TrustBoundary"))
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

    private func makeAssistantService(
        container: RepositoryContainer,
        assistant: any FinancialAssisting = MockAIProvider()
    ) -> FinancialAssistantService {
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
            assistant: assistant
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

    @Test("Contract A: validated monthly summary persists validated snapshot to repository")
    func validatedMonthlySummaryPersists() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        _ = try await seedLedger(container: container, userId: userId)
        let service = makeAssistantService(container: container)

        #expect(try await summaryInsights(userId: userId, container: container).isEmpty)

        let insight = try await service.generateMonthlySummary(userId: userId)

        #expect(insight.type == .summary)
        #expect(!insight.title.isEmpty)
        #expect(!insight.body.isEmpty)
        #expect(insight.modelName == "mock")
        #expect(!insight.body.contains("888888"))

        let persisted = try await summaryInsights(userId: userId, container: container)
        #expect(persisted.count == 1)
        #expect(persisted[0].id == insight.id)
        #expect(persisted[0].title == insight.title)
        #expect(persisted[0].body == insight.body)
        #expect(persisted[0].modelName == "mock")
        #expect(persisted[0].freshnessMetadata != nil)
        #expect(persisted[0].freshnessMetadata?.schemaVersion == StoredInsightFreshnessSchemaVersion.current)
        #expect(persisted[0].freshnessMetadata?.policyVersion == FinancialRiskPolicyVersion.current)
        #expect(persisted[0].freshnessMetadata?.digest.count == 64)
        #expect(persisted[0].freshnessMetadata?.digest.contains("amount.monthlyIncome") == false)
    }

    @Test("Contract B: invalid monthly summary draft is rejected and not persisted")
    func invalidMonthlySummaryNotPersisted() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        _ = try await seedLedger(container: container, userId: userId)
        let service = makeAssistantService(
            container: container,
            assistant: MockAIProvider(assistantBehavior: .inventAmount)
        )

        #expect(try await summaryInsights(userId: userId, container: container).isEmpty)

        await #expect(throws: AssistantValidationError.inventedAmount("888888")) {
            _ = try await service.generateMonthlySummary(userId: userId)
        }

        #expect(try await summaryInsights(userId: userId, container: container).isEmpty)
    }

    @Test("Contract C: Home reuses persisted validated summary without remote regeneration")
    func homeReusesPersistedSummary() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        let account = try await seedLedger(container: container, userId: userId)
        let assistant = makeAssistantService(container: container)
        let persisted = try await assistant.generateMonthlySummary(userId: userId)

        let transport = RecordingTransport()
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        _ = try await consentService.acceptAssistantPrivacy(userId: userId)
        let home = makeRemoteHome(
            container: container,
            transport: transport,
            consentService: consentService
        )

        let overview = try await home.loadOverview(userId: userId)

        #expect(transport.performCount == 0)
        #expect(overview.aiSummary?.id == persisted.id)
        #expect(overview.aiSummary?.title == persisted.title)
        #expect(overview.aiSummary?.body == persisted.body)
        #expect(overview.aiSummary?.modelName == "mock")
        #expect(overview.hasAccounts)
        #expect(overview.hasTransactions)
        let txs = try await container.transactions.fetchAll(userId: userId)
        let expectedAvailable = AccountBalanceEngine.availableFunds(
            accounts: [account],
            transactions: txs
        )
        #expect(overview.availableFunds == expectedAvailable)
    }

    @Test("Contract D: ADR-020 deterministic fallback is not persisted")
    func deterministicFallbackNotPersisted() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        _ = try await seedLedger(container: container, userId: userId)
        let transport = FailingTransport()
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        _ = try await consentService.acceptAssistantPrivacy(userId: userId)
        let home = makeRemoteHome(
            container: container,
            transport: transport,
            consentService: consentService
        )

        #expect(try await summaryInsights(userId: userId, container: container).isEmpty)

        let overview = try await home.loadOverview(userId: userId)

        #expect(transport.performCount == 1)
        #expect(overview.aiSummary?.modelName == "deterministic")
        #expect(overview.aiSummary?.body.isEmpty == false)
        #expect(try await summaryInsights(userId: userId, container: container).isEmpty)
    }

    @Test("Proactive insight persistence does not require monthly-summary freshness metadata")
    func proactiveInsightPersistenceUnaffected() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        _ = try await seedLedger(container: container, userId: userId)
        let service = makeAssistantService(container: container)

        let created = try await service.refreshProactiveInsights(userId: userId)
        #expect(!created.isEmpty)
        for insight in created {
            #expect(insight.type != .summary)
            #expect(insight.freshnessMetadata == nil)
        }
    }
}
