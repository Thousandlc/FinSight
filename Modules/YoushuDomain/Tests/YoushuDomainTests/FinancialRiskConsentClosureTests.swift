import Foundation
import Testing
import YoushuAI
import YoushuData
import YoushuDomain
import YoushuFoundation

@Suite("Financial risk consent closure")
struct FinancialRiskConsentClosureTests {
    private final class RecordingTransport: GatewayHTTPTransport, @unchecked Sendable {
        private(set) var performCount = 0
        private(set) var lastBody: Data?

        func perform(_ request: GatewayHTTPRequest) async throws -> GatewayHTTPResponse {
            performCount += 1
            lastBody = request.body
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

    private func seedLedger(container: RepositoryContainer, userId: UUID) async throws {
        try await container.users.upsert(User(id: userId, displayName: "Consent"))
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
    }

    private func makeRemoteHomeOverview(
        container: RepositoryContainer,
        transport: RecordingTransport,
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

    private func makeAssistantService(
        container: RepositoryContainer,
        transport: RecordingTransport,
        consentService: AIDataConsentService
    ) -> FinancialAssistantService {
        let client = AIGatewayClient(
            configuration: AIGatewayConfiguration(baseURL: URL(string: "http://127.0.0.1:8080")!),
            transport: transport
        )
        let router = FinancialAssistingRouter(
            mode: .remoteMonthlySummaryOnly,
            remote: RemoteFinancialAIProvider(client: client)
        )
        return FinancialAssistantService(
            accounts: container.accounts,
            transactions: container.transactions,
            debts: container.debts,
            repaymentPlans: container.repaymentPlans,
            assets: container.assets,
            budgets: container.budgets,
            goals: container.goals,
            insights: container.insights,
            users: container.users,
            assistant: router,
            consentService: consentService
        )
    }

    @Test("consent=false does not emit remote monthly summary request")
    func consentDeniedBlocksRemoteTransport() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await seedLedger(container: container, userId: userId)
        let transport = RecordingTransport()
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        let home = makeRemoteHomeOverview(
            container: container,
            transport: transport,
            consentService: consentService
        )

        let overview = try await home.loadOverview(userId: userId)

        #expect(transport.performCount == 0)
        #expect(transport.lastBody == nil)
        #expect(overview.aiSummary?.modelName == "deterministic")
    }

    @Test("consent=true sends valid financialRiskAssessment in gateway envelope")
    func consentGrantedSendsAssessment() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await seedLedger(container: container, userId: userId)
        let transport = RecordingTransport()
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        _ = try await consentService.acceptAssistantPrivacy(userId: userId)
        let home = makeRemoteHomeOverview(
            container: container,
            transport: transport,
            consentService: consentService
        )

        let overview = try await home.loadOverview(userId: userId)

        #expect(transport.performCount == 1)
        let bodyText = String(data: transport.lastBody ?? Data(), encoding: .utf8) ?? ""
        #expect(bodyText.contains("financialRiskAssessment"))
        #expect(bodyText.contains("debtDataState"))
        #expect(overview.aiSummary?.modelName == "youshu-gateway")
    }

    @Test("revoke consent blocks subsequent home overview remote requests")
    func revokeBlocksSubsequentTransport() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await seedLedger(container: container, userId: userId)
        let transport = RecordingTransport()
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        _ = try await consentService.acceptAssistantPrivacy(userId: userId)
        let home = makeRemoteHomeOverview(
            container: container,
            transport: transport,
            consentService: consentService
        )

        _ = try await home.loadOverview(userId: userId)
        #expect(transport.performCount == 1)

        _ = try await consentService.revokeAssistantPrivacy(userId: userId)
        let second = try await home.loadOverview(userId: userId)

        #expect(transport.performCount == 1)
        #expect(second.aiSummary?.modelName == "deterministic")
    }

    @Test("local risk assessment runs when consent=false")
    func localRiskWithoutConsent() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await seedLedger(container: container, userId: userId)
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        let service = FinancialAssistantService(
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
            consentService: consentService
        )

        let assessment = try await service.evaluateMonthlySummaryRisk(userId: userId)
        #expect(assessment.policyVersion == FinancialRiskPolicyVersion.current)
    }

    @Test("explicit monthly summary still requires consent before remote call")
    func explicitMonthlySummaryRequiresConsent() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await seedLedger(container: container, userId: userId)
        let transport = RecordingTransport()
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        let service = makeAssistantService(
            container: container,
            transport: transport,
            consentService: consentService
        )

        do {
            _ = try await service.generateMonthlySummaryWithRiskAssessment(userId: userId)
            Issue.record("Expected consent required")
        } catch let error as PrivacyError {
            #expect(error == .consentRequired("财务助手 Context"))
        }
        #expect(transport.performCount == 0)
    }
}
