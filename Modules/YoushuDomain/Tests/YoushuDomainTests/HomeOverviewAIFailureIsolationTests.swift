import Foundation
import Testing
import YoushuAI
import YoushuData
import YoushuDomain
import YoushuFoundation

@Suite("Home overview AI failure isolation (ADR-020)")
struct HomeOverviewAIFailureIsolationTests {
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
        try await container.users.upsert(User(id: userId, displayName: "Home"))
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

    @Test("T1 remote AI success keeps deterministic metrics and uses AI summary")
    func remoteAISuccess() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        let account = try await seedLedger(container: container, userId: userId)
        let transport = RecordingTransport()
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        _ = try await consentService.acceptAssistantPrivacy(userId: userId)
        let home = makeRemoteHome(container: container, transport: transport, consentService: consentService)

        let overview = try await home.loadOverview(userId: userId)

        #expect(transport.performCount == 1)
        #expect(overview.aiSummary?.modelName == "youshu-gateway")
        #expect(overview.hasAccounts)
        #expect(overview.hasTransactions)
        let txs = try await container.transactions.fetchAll(userId: userId)
        let expectedAvailable = AccountBalanceEngine.availableFunds(
            accounts: [account],
            transactions: txs
        )
        #expect(overview.availableFunds == expectedAvailable)
        #expect(overview.monthlyIncome.amount == 5_000)
    }

    @Test("T2 remote AI failure with consent still loads Home with deterministic fallback")
    func remoteAIFailureWithConsentFallsBack() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        let account = try await seedLedger(container: container, userId: userId)
        let transport = FailingTransport()
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        _ = try await consentService.acceptAssistantPrivacy(userId: userId)
        let home = makeRemoteHome(container: container, transport: transport, consentService: consentService)

        let overview = try await home.loadOverview(userId: userId)

        #expect(transport.performCount == 1)
        #expect(overview.aiSummary?.modelName == "deterministic")
        #expect(overview.aiSummary?.body.isEmpty == false)
        let txs = try await container.transactions.fetchAll(userId: userId)
        let expectedAvailable = AccountBalanceEngine.availableFunds(
            accounts: [account],
            transactions: txs
        )
        #expect(overview.availableFunds == expectedAvailable)
        #expect(overview.monthlyIncome.amount == 5_000)
        #expect(overview.cashFlowProjections.count == CashFlowHorizon.allCases.count)
    }

    @Test("T3 consent denied skips remote and uses deterministic summary")
    func consentDeniedUsesDeterministic() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        _ = try await seedLedger(container: container, userId: userId)
        let transport = FailingTransport()
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        let home = makeRemoteHome(container: container, transport: transport, consentService: consentService)

        let overview = try await home.loadOverview(userId: userId)

        #expect(transport.performCount == 0)
        #expect(overview.aiSummary?.modelName == "deterministic")
        #expect(overview.hasTransactions)
    }

    @Test("T4 core repository failure still surfaces Home load error")
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

    @Test("T5 mock provider monthly summary succeeds without blocking Home")
    func mockProviderRegression() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        _ = try await seedLedger(container: container, userId: userId)
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        _ = try await consentService.acceptAssistantPrivacy(userId: userId)
        let home = HomeOverviewService(
            accounts: container.accounts,
            transactions: container.transactions,
            debts: container.debts,
            repaymentPlans: container.repaymentPlans,
            assets: container.assets,
            budgets: container.budgets,
            goals: container.goals,
            insights: container.insights,
            users: container.users,
            financialAssistant: MockAIProvider(),
            consentService: consentService
        )

        let overview = try await home.loadOverview(userId: userId)

        #expect(overview.aiSummary?.modelName == "mock")
        #expect(overview.hasAccounts)
        let txs = try await container.transactions.fetchAll(userId: userId)
        let accounts = try await container.accounts.fetchAll(userId: userId)
        let expectedAvailable = AccountBalanceEngine.availableFunds(
            accounts: accounts,
            transactions: txs
        )
        #expect(overview.availableFunds == expectedAvailable)
    }

    @Test("T6 optional AI failure emits degraded while Home stays available")
    func remoteAIFailureEmitsDegraded() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        let account = try await seedLedger(container: container, userId: userId)
        let transport = FailingTransport()
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        _ = try await consentService.acceptAssistantPrivacy(userId: userId)
        let home = makeRemoteHome(container: container, transport: transport, consentService: consentService)
        let collector = ObservabilityEventCollector()

        let overview = try await ObservabilityEmission.$collector.withValue(collector) {
            try await home.loadOverview(userId: userId)
        }

        #expect(transport.performCount == 1)
        #expect(overview.aiSummary?.modelName == "deterministic")
        #expect(overview.hasAccounts)
        #expect(overview.hasTransactions)
        let txs = try await container.transactions.fetchAll(userId: userId)
        let expectedAvailable = AccountBalanceEngine.availableFunds(
            accounts: [account],
            transactions: txs
        )
        #expect(overview.availableFunds == expectedAvailable)
        let event = try #require(collector.last)
        #expect(event.outcome == .degraded)
        #expect(event.operation == .monthlySummary)
        #expect(event.errorCode == .unauthorized)
        #expect(event.retryCount == 0)
        #expect(ObservabilityRequestID.isWellFormed(event.requestId))
        let text = try collector.encodedProductionOutput()
        #expect(!text.contains("localizedDescription"))
        #expect(!text.contains("RAW_RESPONSE_SECRET_CANARY"))
    }

    @Test("T7 consent denied Home skip emits no remote/consent observability event")
    func consentDeniedDoesNotEmitRemoteEvent() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        _ = try await seedLedger(container: container, userId: userId)
        let transport = FailingTransport()
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        let home = makeRemoteHome(container: container, transport: transport, consentService: consentService)
        let collector = ObservabilityEventCollector()

        let overview = try await ObservabilityEmission.$collector.withValue(collector) {
            try await home.loadOverview(userId: userId)
        }

        #expect(transport.performCount == 0)
        #expect(overview.aiSummary?.modelName == "deterministic")
        #expect(collector.events.isEmpty)
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
