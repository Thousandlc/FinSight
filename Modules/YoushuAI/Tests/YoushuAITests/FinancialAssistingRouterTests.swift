import Foundation
import Testing
import YoushuAI
import YoushuDomain
import YoushuFoundation

@Suite("Financial assisting router")
struct FinancialAssistingRouterTests {
    private struct MockTransport: GatewayHTTPTransport {
        let handler: @Sendable (GatewayHTTPRequest) throws -> GatewayHTTPResponse

        func perform(_ request: GatewayHTTPRequest) async throws -> GatewayHTTPResponse {
            try handler(request)
        }
    }

    private func sampleFacts() -> MonthlySummaryFacts {
        MonthlySummaryFacts(
            availableCash: Money(amount: 1_000, currencyCode: "CNY"),
            monthlyIncome: Money(amount: 5_000, currencyCode: "CNY"),
            monthlyExpense: Money(amount: 3_000, currencyCode: "CNY"),
            monthlyDebtPayment: Money(amount: 500, currencyCode: "CNY"),
            debtPaymentToIncomePercent: nil,
            primaryPressure: "生活支出",
            estimatedMonthEndBalance: Money(amount: 1_500, currencyCode: "CNY"),
            sourceLabels: ["Account"]
        )
    }

    private func sampleRequest() -> AssistantRequestDTO {
        FinancialAssistantContextMapper.makeRequest(
            question: "我现在有多少钱？",
            intent: .availableCash,
            context: FinancialContext(
                availableCash: Money(amount: 1_000, currencyCode: "CNY"),
                hasAccounts: true,
                currencyCode: "CNY"
            ),
            safeBalance: Money(amount: 2_000, currencyCode: "CNY")
        )
    }

    @Test("mock mode routes all to mock")
    func mockMode() async throws {
        let router = FinancialAssistingRouter(mode: .mock)
        #expect(router.name == "mock")
        let draft = try await router.phraseMonthlySummary(
            request: sampleRequest(),
            facts: sampleFacts(),
            riskAssessment: FinancialRiskGatewayTestFixtures.safeKnownNoDebt()
        )
        #expect(!draft.body.isEmpty)
    }

    @Test("remote monthly summary uses remote provider")
    func remoteMonthlySummary() async throws {
        let transport = MockTransport { request in
            let requestId = request.headers["X-Youshu-Request-Id"] ?? ""
            let body = "本月主要压力来自生活支出。预计月底结余约 ¥1500。数据来自 Account。"
            let json = """
            {"schemaVersion":"v1","requestId":"\(requestId)","modelAlias":"mock-qwen","draft":{"title":"本月财务摘要","body":"\(body)","answer":"\(body)","citedFactKeys":["primaryPressure"],"unknowns":[],"confidence":0.9,"keyFacts":[{"label":"可用资金","kind":"balance","source":"availableCash","value":{"type":"money","amount":1000,"currencyCode":"CNY"}},{"label":"预计月底结余","kind":"balance","source":"estimatedMonthEndBalance","value":{"type":"money","amount":1500,"currencyCode":"CNY"}},{"label":"主要压力","kind":"other","source":"primaryPressure","value":{"type":"text","value":"生活支出"}}],"warnings":[],"actions":[{"title":"查看未来现金流","destination":"cashFlow"}],"references":[{"key":"availableCash"},{"key":"estimatedMonthEndBalance"},{"key":"primaryPressure"}]}}
            """
            return GatewayHTTPResponse(statusCode: 200, data: Data(json.utf8))
        }
        let client = AIGatewayClient(
            configuration: AIGatewayConfiguration(baseURL: URL(string: "http://127.0.0.1:8080")!),
            transport: transport
        )
        let router = FinancialAssistingRouter(
            mode: .remoteMonthlySummaryOnly,
            remote: RemoteFinancialAIProvider(client: client)
        )
        #expect(router.name == "youshu-gateway")
        let draft = try await router.phraseMonthlySummary(
            request: sampleRequest(),
            facts: sampleFacts(),
            riskAssessment: FinancialRiskGatewayTestFixtures.safeKnownNoDebt()
        )
        #expect(draft.title == "本月财务摘要")
    }

    @Test("ask still uses mock under remote mode")
    func askUsesMock() async throws {
        let router = FinancialAssistingRouter(
            mode: .remoteMonthlySummaryOnly,
            remote: RemoteFinancialAIProvider(
                client: AIGatewayClient(
                    configuration: AIGatewayConfiguration(baseURL: URL(string: "http://127.0.0.1:8080")!),
                    transport: MockTransport { _ in GatewayHTTPResponse(statusCode: 500, data: Data()) }
                )
            )
        )
        let pack = AnswerFactPack(
            intent: .availableCash,
            amounts: ["availableCash": Money(amount: 1_000, currencyCode: "CNY")]
        )
        let draft = try await router.phraseAnswer(request: sampleRequest(), facts: pack)
        #expect(draft.body.contains("1000") || draft.body.contains("1,000") || draft.body.contains("¥"))
    }

    @Test("insight still uses mock under remote mode")
    func insightUsesMock() async throws {
        let router = FinancialAssistingRouter(mode: .remoteMonthlySummaryOnly, remote: nil)
        let pack = InsightFactPack(
            type: .cashFlow,
            titleHint: "现金流风险",
            facts: ["explanation": "测试"],
            amounts: ["availableCash": Money(amount: 1_000, currencyCode: "CNY")]
        )
        let draft = try await router.phraseInsight(request: sampleRequest(), facts: pack)
        #expect(!draft.body.isEmpty)
    }

    @Test("purchase scenario still uses mock under remote mode")
    func purchaseUsesMock() async throws {
        let router = FinancialAssistingRouter(mode: .remoteMonthlySummaryOnly, remote: nil)
        let scenario = PurchaseScenario(
            purchaseAmount: Money(amount: 3_000, currencyCode: "CNY"),
            currentCash: Money(amount: 10_000, currencyCode: "CNY"),
            cashAfterPurchase: Money(amount: 7_000, currencyCode: "CNY"),
            safetyReserve: Money(amount: 2_000, currencyCode: "CNY"),
            breachesSafetyReserve: false,
            futureIncome: Money(amount: 5_000, currencyCode: "CNY"),
            fixedExpenses: Money(amount: 2_000, currencyCode: "CNY"),
            debtPayments: Money(amount: 500, currencyCode: "CNY"),
            affordability: .affordable,
            factPack: AnswerFactPack(
                intent: .purchaseAffordability,
                amounts: [
                    "purchaseAmount": Money(amount: 3_000, currencyCode: "CNY"),
                    "currentCash": Money(amount: 10_000, currencyCode: "CNY"),
                    "cashAfterPurchase": Money(amount: 7_000, currencyCode: "CNY"),
                    "safetyReserve": Money(amount: 2_000, currencyCode: "CNY"),
                ],
                requiresDisclaimer: true
            )
        )
        let draft = try await router.phrasePurchaseScenario(request: sampleRequest(), scenario: scenario)
        #expect(draft.disclaimer != nil)
    }

    @Test("remote unconfigured fails safely for monthly summary")
    func remoteUnconfigured() async {
        let router = FinancialAssistingRouter(mode: .remoteMonthlySummaryOnly, remote: nil)
        await #expect(throws: AIGatewayError.notConfigured) {
            _ = try await router.phraseMonthlySummary(
                request: sampleRequest(),
                facts: sampleFacts(),
                riskAssessment: FinancialRiskGatewayTestFixtures.safeKnownNoDebt()
            )
        }
    }
}
