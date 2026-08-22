import Foundation
import Testing
import YoushuAI
import YoushuData
import YoushuDomain
import YoushuFoundation

@Suite("Home monthly-summary cache persistence isolation (ADR-020 / ADR-032)")
struct HomeOverviewCachePersistenceIsolationTests {
    private final class RecordingTransport: GatewayHTTPTransport, @unchecked Sendable {
        private(set) var performCount = 0

        func perform(_ request: GatewayHTTPRequest) async throws -> GatewayHTTPResponse {
            performCount += 1
            let requestId = request.headers["X-Youshu-Request-Id"] ?? "req-test"
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let envelope = try decoder.decode(GatewayRequestEnvelope.self, from: request.body ?? Data())
            let facts = envelope.monthlySummaryFacts
            let available = facts?.availableCash.amount ?? "0"
            let monthEnd = facts?.estimatedMonthEndBalance.amount ?? "0"
            let pressure = facts?.primaryPressure ?? "生活支出"
            let body = "本月主要压力来自\(pressure)。预计月底结余约 ¥\(monthEnd)。数据来自 Account。"
            let json = """
            {"schemaVersion":"v1","requestId":"\(requestId)","modelAlias":"mock-qwen","draft":{"title":"本月财务摘要","body":"\(body)","answer":"\(body)","citedFactKeys":["primaryPressure"],"unknowns":[],"confidence":0.9,"keyFacts":[{"label":"可用资金","kind":"balance","source":"availableCash","value":{"type":"money","amount":\(available),"currencyCode":"CNY"}},{"label":"预计月底结余","kind":"balance","source":"estimatedMonthEndBalance","value":{"type":"money","amount":\(monthEnd),"currencyCode":"CNY"}},{"label":"主要压力","kind":"other","source":"primaryPressure","value":{"type":"text","value":"\(pressure)"}}],"warnings":[],"actions":[{"title":"查看未来现金流","destination":"cashFlow"}],"references":[{"key":"availableCash"},{"key":"estimatedMonthEndBalance"},{"key":"primaryPressure"}]}}
            """
            return GatewayHTTPResponse(statusCode: 200, data: Data(json.utf8))
        }
    }

    private actor FailingUpsertInsightRepository: FinancialInsightRepository {
        private let inner: any FinancialInsightRepository

        init(inner: any FinancialInsightRepository) {
            self.inner = inner
        }

        func upsert(_ insight: FinancialInsight) async throws {
            throw DataError.persistenceFailed("SOURCE_ID_CANARY \(insight.id.uuidString) \(insight.title)")
        }

        func fetchAll(userId: UUID) async throws -> [FinancialInsight] {
            try await inner.fetchAll(userId: userId)
        }

        func delete(id: UUID) async throws {
            try await inner.delete(id: id)
        }
    }

    private actor RecordingInsightRepository: FinancialInsightRepository {
        private let inner: any FinancialInsightRepository
        private(set) var upsertCount = 0

        init(inner: any FinancialInsightRepository) {
            self.inner = inner
        }

        func upsert(_ insight: FinancialInsight) async throws {
            upsertCount += 1
            try await inner.upsert(insight)
        }

        func fetchAll(userId: UUID) async throws -> [FinancialInsight] {
            try await inner.fetchAll(userId: userId)
        }

        func delete(id: UUID) async throws {
            try await inner.delete(id: id)
        }
    }

    private func seedLedger(container: RepositoryContainer, userId: UUID) async throws -> Account {
        try await container.users.upsert(User(id: userId, displayName: "CacheHome"))
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

    private func persistThenStale(
        container: RepositoryContainer,
        userId: UUID,
        accountId: UUID
    ) async throws -> FinancialInsight {
        let assistant = FinancialAssistantService(
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
                accountId: accountId,
                formType: .expense
            ),
            userId: userId
        )
        return persisted
    }

    private func makeRemoteHome(
        container: RepositoryContainer,
        transport: any GatewayHTTPTransport,
        consentService: AIDataConsentService,
        insights: (any FinancialInsightRepository)? = nil
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
            insights: insights ?? container.insights,
            users: container.users,
            financialAssistant: router,
            consentService: consentService
        )
    }

    @Test("T1 cache persist failure does not fail Home and keeps validated AI ephemerally")
    func cachePersistFailureKeepsHomeAvailable() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        let account = try await seedLedger(container: container, userId: userId)
        let persisted = try await persistThenStale(container: container, userId: userId, accountId: account.id)
        let transport = RecordingTransport()
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        _ = try await consentService.acceptAssistantPrivacy(userId: userId)
        let failingInsights = FailingUpsertInsightRepository(inner: container.insights)
        let home = makeRemoteHome(
            container: container,
            transport: transport,
            consentService: consentService,
            insights: failingInsights
        )
        let collector = ObservabilityEventCollector()

        let overview = try await ObservabilityEmission.$collector.withValue(collector) {
            try await home.loadOverview(userId: userId)
        }

        #expect(transport.performCount == 1)
        #expect(overview.hasAccounts)
        #expect(overview.hasTransactions)
        #expect(overview.aiSummary?.modelName == "youshu-gateway")
        #expect(overview.aiSummary?.body != persisted.body)
        #expect(overview.aiSummary?.id != persisted.id)
        let event = try #require(collector.last)
        #expect(event.outcome == .degraded)
        #expect(event.failureStage == .insightPersistence)
        #expect(event.errorCode == .persistenceFailure)
        #expect(collector.events.count == 1)
    }

    @Test("T2 persistence failure is observable without repository strings")
    func persistFailureTelemetryIsSanitized() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        let account = try await seedLedger(container: container, userId: userId)
        _ = try await persistThenStale(container: container, userId: userId, accountId: account.id)
        let transport = RecordingTransport()
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        _ = try await consentService.acceptAssistantPrivacy(userId: userId)
        let home = makeRemoteHome(
            container: container,
            transport: transport,
            consentService: consentService,
            insights: FailingUpsertInsightRepository(inner: container.insights)
        )
        let collector = ObservabilityEventCollector()
        _ = try await ObservabilityEmission.$collector.withValue(collector) {
            try await home.loadOverview(userId: userId)
        }
        let text = try collector.encodedProductionOutput()
        #expect(text.contains("insightPersistence"))
        #expect(text.contains("persistenceFailure"))
        #expect(text.contains("degraded"))
        #expect(!text.contains("SOURCE_ID_CANARY"))
        #expect(!text.contains("本月财务摘要"))
        #expect(!text.contains("localizedDescription"))
    }

    @Test("T4 validator rejection does not attempt cache write")
    func validatorFailureSkipsPersistAndFallsBack() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        let account = try await seedLedger(container: container, userId: userId)
        _ = try await persistThenStale(container: container, userId: userId, accountId: account.id)
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        _ = try await consentService.acceptAssistantPrivacy(userId: userId)
        let recording = RecordingInsightRepository(inner: container.insights)
        let home = HomeOverviewService(
            accounts: container.accounts,
            transactions: container.transactions,
            debts: container.debts,
            repaymentPlans: container.repaymentPlans,
            assets: container.assets,
            budgets: container.budgets,
            goals: container.goals,
            insights: recording,
            users: container.users,
            financialAssistant: MockAIProvider(assistantBehavior: .inventAmount),
            consentService: consentService
        )
        let collector = ObservabilityEventCollector()
        let overview = try await ObservabilityEmission.$collector.withValue(collector) {
            try await home.loadOverview(userId: userId)
        }
        #expect(overview.aiSummary?.modelName == "deterministic")
        #expect(await recording.upsertCount == 0)
        let event = try #require(collector.last)
        #expect(event.outcome == .degraded)
        #expect(event.failureStage == .assistantValidation)
        #expect(event.errorCode == .validationRejected)
    }

    @Test("T5 successful cache persistence remains reusable")
    func successfulPersistIsReusable() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        let account = try await seedLedger(container: container, userId: userId)
        _ = try await persistThenStale(container: container, userId: userId, accountId: account.id)
        let transport = RecordingTransport()
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        _ = try await consentService.acceptAssistantPrivacy(userId: userId)
        let home = makeRemoteHome(container: container, transport: transport, consentService: consentService)

        let first = try await home.loadOverview(userId: userId)
        #expect(transport.performCount == 1)
        #expect(first.aiSummary?.modelName == "youshu-gateway")
        let persistedBody = try #require(first.aiSummary?.body)

        let second = try await home.loadOverview(userId: userId)
        #expect(transport.performCount == 1)
        #expect(second.aiSummary?.body == persistedBody)
    }

    @Test("T6 failed write does not forge freshness")
    func failedWriteLeavesStaleCacheUnchanged() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        let account = try await seedLedger(container: container, userId: userId)
        let persisted = try await persistThenStale(container: container, userId: userId, accountId: account.id)
        let transport = RecordingTransport()
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        _ = try await consentService.acceptAssistantPrivacy(userId: userId)
        let failingHome = makeRemoteHome(
            container: container,
            transport: transport,
            consentService: consentService,
            insights: FailingUpsertInsightRepository(inner: container.insights)
        )

        let ephemeral = try await failingHome.loadOverview(userId: userId)
        #expect(ephemeral.aiSummary?.id != persisted.id)

        let durable = try await container.insights.fetchAll(userId: userId)
        let stored = durable.filter { $0.type == .summary }
        #expect(stored.count == 1)
        #expect(stored[0].id == persisted.id)
        #expect(stored[0].body == persisted.body)
        #expect(stored[0].freshnessMetadata == persisted.freshnessMetadata)

        let realHome = makeRemoteHome(container: container, transport: transport, consentService: consentService)
        _ = try await realHome.loadOverview(userId: userId)
        #expect(transport.performCount == 2)
    }

    @Test("T7 consent denied does not write cache")
    func consentDeniedDoesNotWriteCache() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        _ = try await seedLedger(container: container, userId: userId)
        let transport = RecordingTransport()
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        let recording = RecordingInsightRepository(inner: container.insights)
        let home = makeRemoteHome(
            container: container,
            transport: transport,
            consentService: consentService,
            insights: recording
        )
        let overview = try await home.loadOverview(userId: userId)
        #expect(transport.performCount == 0)
        #expect(overview.aiSummary?.modelName == "deterministic")
        #expect(await recording.upsertCount == 0)
    }
}
