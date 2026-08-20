import Foundation
import Testing
import YoushuAI
import YoushuData
import YoushuDomain
import YoushuFoundation

@Suite("Home overview consent lifecycle (ADR-032 Step 4)")
struct HomeOverviewConsentLifecycleTests {
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

    private func seedLedger(container: RepositoryContainer, userId: UUID) async throws -> Account {
        try await container.users.upsert(User(id: userId, displayName: "ConsentHome"))
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
            assistant: MockAIProvider(),
            consentService: AIDataConsentService(consents: container.aiDataConsents)
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

    @Test("fresh stored summary with consent denied returns deterministic and preserves stored record")
    func freshStoredSummaryConsentDenied() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        _ = try await seedLedger(container: container, userId: userId)
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        _ = try await consentService.acceptAssistantPrivacy(userId: userId)
        let assistant = makeAssistantService(container: container)
        let persisted = try await assistant.generateMonthlySummary(userId: userId)

        let transport = RecordingTransport()
        let home = makeRemoteHome(container: container, transport: transport, consentService: consentService)
        _ = try await consentService.revokeAssistantPrivacy(userId: userId)

        let overview = try await home.loadOverview(userId: userId)

        #expect(transport.performCount == 0)
        #expect(overview.aiSummary?.modelName == "deterministic")
        #expect(overview.aiSummary?.body != persisted.body)
        let stored = try await summaryInsights(userId: userId, container: container)
        #expect(stored.count == 1)
        #expect(stored[0].id == persisted.id)
        #expect(stored[0].body == persisted.body)
        #expect(stored[0].freshnessMetadata == persisted.freshnessMetadata)
    }

    @Test("stale stored summary with consent denied skips provider and returns deterministic")
    func staleStoredSummaryConsentDenied() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        let account = try await seedLedger(container: container, userId: userId)
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        _ = try await consentService.acceptAssistantPrivacy(userId: userId)
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
        let home = makeRemoteHome(container: container, transport: transport, consentService: consentService)
        _ = try await consentService.revokeAssistantPrivacy(userId: userId)

        let overview = try await home.loadOverview(userId: userId)

        #expect(transport.performCount == 0)
        #expect(overview.aiSummary?.modelName == "deterministic")
        #expect(overview.aiSummary?.body != persisted.body)
        #expect(try await summaryInsights(userId: userId, container: container).count == 1)
    }

    @Test("unsupported-schema stored summary with consent denied uses deterministic without provider")
    func unsupportedSchemaSummaryConsentDenied() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        _ = try await seedLedger(container: container, userId: userId)
        let unsupported = FinancialInsight(
            userId: userId,
            type: .summary,
            title: "unsupported schema",
            body: "unsupported body",
            modelName: "mock",
            freshnessMetadata: FinancialInsightFreshnessMetadata(
                schemaVersion: "v0-unsupported",
                policyVersion: FinancialRiskPolicyVersion.current,
                digest: String(repeating: "b", count: 64)
            )
        )
        try await container.insights.upsert(unsupported)

        let transport = RecordingTransport()
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        let home = makeRemoteHome(container: container, transport: transport, consentService: consentService)

        let overview = try await home.loadOverview(userId: userId)

        #expect(transport.performCount == 0)
        #expect(overview.aiSummary?.modelName == "deterministic")
        #expect(overview.aiSummary?.body != unsupported.body)
    }

    @Test("re-enabled consent reuses still-fresh stored summary without provider call")
    func consentReenableReusesFreshStoredSummary() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        _ = try await seedLedger(container: container, userId: userId)
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        _ = try await consentService.acceptAssistantPrivacy(userId: userId)
        let assistant = makeAssistantService(container: container)
        let persisted = try await assistant.generateMonthlySummary(userId: userId)

        let transport = RecordingTransport()
        let home = makeRemoteHome(container: container, transport: transport, consentService: consentService)
        _ = try await consentService.revokeAssistantPrivacy(userId: userId)
        let deniedOverview = try await home.loadOverview(userId: userId)
        #expect(deniedOverview.aiSummary?.modelName == "deterministic")

        _ = try await consentService.acceptAssistantPrivacy(userId: userId)
        let restoredOverview = try await home.loadOverview(userId: userId)

        #expect(transport.performCount == 0)
        #expect(restoredOverview.aiSummary?.id == persisted.id)
        #expect(restoredOverview.aiSummary?.body == persisted.body)
    }

    @Test("re-enabled consent regenerates when facts changed while consent was denied")
    func consentReenableAfterFactChangeWhileDenied() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        let account = try await seedLedger(container: container, userId: userId)
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        _ = try await consentService.acceptAssistantPrivacy(userId: userId)
        let assistant = makeAssistantService(container: container)
        let persisted = try await assistant.generateMonthlySummary(userId: userId)

        _ = try await consentService.revokeAssistantPrivacy(userId: userId)

        let txService = TransactionService(
            accounts: container.accounts,
            transactions: container.transactions
        )
        _ = try await txService.record(
            RecordTransactionInput(
                amount: 800,
                merchant: "额外支出",
                category: "生活",
                accountId: account.id,
                formType: .expense
            ),
            userId: userId
        )

        let transport = RecordingTransport()
        let home = makeRemoteHome(container: container, transport: transport, consentService: consentService)
        _ = try await consentService.acceptAssistantPrivacy(userId: userId)
        let overview = try await home.loadOverview(userId: userId)

        #expect(transport.performCount == 1)
        #expect(overview.aiSummary?.body.contains("remote regenerated current summary") == true)
        #expect(overview.aiSummary?.id != persisted.id)
    }

    @Test("consent denied deterministic fallback is not persisted")
    func consentDeniedFallbackNotPersisted() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        _ = try await seedLedger(container: container, userId: userId)
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        _ = try await consentService.acceptAssistantPrivacy(userId: userId)
        let assistant = makeAssistantService(container: container)
        _ = try await assistant.generateMonthlySummary(userId: userId)

        let transport = RecordingTransport()
        let home = makeRemoteHome(container: container, transport: transport, consentService: consentService)
        _ = try await consentService.revokeAssistantPrivacy(userId: userId)
        _ = try await home.loadOverview(userId: userId)

        #expect(try await summaryInsights(userId: userId, container: container).count == 1)
    }

    @Test("consent revoke does not delete or modify proactive historical insights")
    func consentRevokePreservesProactiveInsights() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        _ = try await seedLedger(container: container, userId: userId)
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        _ = try await consentService.acceptAssistantPrivacy(userId: userId)
        let assistant = makeAssistantService(container: container)
        let proactive = try await assistant.refreshProactiveInsights(userId: userId)
        #expect(!proactive.isEmpty)

        let transport = RecordingTransport()
        let home = makeRemoteHome(container: container, transport: transport, consentService: consentService)
        _ = try await consentService.revokeAssistantPrivacy(userId: userId)
        _ = try await home.loadOverview(userId: userId)

        let allInsights = try await container.insights.fetchAll(userId: userId)
        for original in proactive {
            let current = allInsights.first(where: { $0.id == original.id })
            #expect(current != nil)
            #expect(current?.title == original.title)
            #expect(current?.body == original.body)
            #expect(current?.freshnessMetadata == nil)
        }
    }

    @Test("AI generation failure with consent allowed still uses deterministic fallback")
    func aiFailureWithConsentAllowedUsesDeterministicFallback() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        _ = try await seedLedger(container: container, userId: userId)
        let transport = FailingTransport()
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        _ = try await consentService.acceptAssistantPrivacy(userId: userId)
        let home = makeRemoteHome(container: container, transport: transport, consentService: consentService)

        let overview = try await home.loadOverview(userId: userId)

        #expect(transport.performCount == 1)
        #expect(overview.aiSummary?.modelName == "deterministic")
        #expect(try await summaryInsights(userId: userId, container: container).isEmpty)
    }
}
