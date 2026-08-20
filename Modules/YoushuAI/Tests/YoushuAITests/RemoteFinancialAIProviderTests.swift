import Foundation
import Testing
import YoushuAI
import YoushuDomain
import YoushuFoundation

@Suite("Remote financial AI provider")
struct RemoteFinancialAIProviderTests {
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
            sourceLabels: ["Account", "Transaction"]
        )
    }

    private func sampleRiskAssessment() -> FinancialRiskAssessment {
        FinancialRiskGatewayTestFixtures.safeKnownNoDebt()
    }

    private func sampleRequest() -> AssistantRequestDTO {
        AssistantRequestDTO(
            question: "",
            intent: .unknown,
            context: FinancialAssistantContextDTO(
                meta: .init(asOf: Date(timeIntervalSince1970: 1_700_000_000), currencyCode: "CNY"),
                balance: .init(
                    availableCash: MoneyDTO(amount: 1_000, currencyCode: "CNY"),
                    estimatedMonthEnd: MoneyDTO(amount: 1_500, currencyCode: "CNY")
                ),
                monthly: .init(
                    income: MoneyDTO(amount: 5_000, currencyCode: "CNY"),
                    expense: MoneyDTO(amount: 3_000, currencyCode: "CNY"),
                    debtPayment: MoneyDTO(amount: 500, currencyCode: "CNY"),
                    debtToIncomePercent: nil
                ),
                debt: .init(
                    totalOutstanding: MoneyDTO(amount: 0, currencyCode: "CNY"),
                    estimatedMonthlyRepayment: MoneyDTO(amount: 0, currencyCode: "CNY"),
                    debtFreeMonth: nil
                ),
                cashFlow30: nil,
                spending: .init(topCategories: []),
                goals: [],
                budgets: []
            )
        )
    }

    private func successResponseJSON(requestId: String) -> Data {
        let body = "本月主要压力来自生活支出。预计月底结余约 ¥1500。数据来自 Account / Transaction。"
        let json = """
        {
          "schemaVersion": "v1",
          "requestId": "\(requestId)",
          "modelAlias": "mock-qwen",
          "draft": {
            "title": "本月财务摘要",
            "body": "\(body)",
            "answer": "\(body)",
            "citedFactKeys": ["primaryPressure", "estimatedMonthEndBalance"],
            "unknowns": [],
            "confidence": 0.9,
            "keyFacts": [
              {
                "label": "可用资金",
                "kind": "balance",
                "source": "availableCash",
                "value": { "type": "money", "amount": 1000, "currencyCode": "CNY" }
              },
              {
                "label": "预计月底结余",
                "kind": "balance",
                "source": "estimatedMonthEndBalance",
                "value": { "type": "money", "amount": 1500, "currencyCode": "CNY" }
              },
              {
                "label": "主要压力",
                "kind": "other",
                "source": "primaryPressure",
                "value": { "type": "text", "value": "生活支出" }
              }
            ],
            "warnings": [],
            "actions": [{ "title": "查看未来现金流", "destination": "cashFlow" }],
            "references": [
              { "key": "availableCash" },
              { "key": "estimatedMonthEndBalance" },
              { "key": "primaryPressure" }
            ]
          }
        }
        """
        return Data(json.utf8)
    }

    private func errorResponseJSON(code: String, retryAfter: Int? = nil) -> Data {
        let retry = retryAfter.map { ",\"retryAfterSeconds\":\($0)" } ?? ""
        let json = """
        {"schemaVersion":"v1","requestId":"ignored","error":{"code":"\(code)","message":"error"\(retry)}}
        """
        return Data(json.utf8)
    }

    private func makeClient(transport: MockTransport, maxRetryCount: Int = 0) -> AIGatewayClient {
        AIGatewayClient(
            configuration: AIGatewayConfiguration(baseURL: URL(string: "http://127.0.0.1:8080")!),
            transport: transport,
            maxRetryCount: maxRetryCount,
            retryDelaySeconds: 0
        )
    }

    private func requestId(from request: GatewayHTTPRequest) -> String {
        request.headers["X-Youshu-Request-Id"] ?? ""
    }

    @Test("monthly summary success")
    func monthlySummarySuccess() async throws {
        let transport = MockTransport { request in
            GatewayHTTPResponse(statusCode: 200, data: self.successResponseJSON(requestId: self.requestId(from: request)))
        }
        let provider = RemoteFinancialAIProvider(client: makeClient(transport: transport))
        let draft = try await provider.phraseMonthlySummary(
            request: sampleRequest(),
            facts: sampleFacts(),
            riskAssessment: FinancialRiskGatewayTestFixtures.safeKnownNoDebt()
        )
        _ = try AssistantAnswerValidator.validateSummary(draft: draft, facts: sampleFacts())
        #expect(draft.title == "本月财务摘要")
    }

    @Test("decode structured draft")
    func decodeStructuredDraft() async throws {
        let transport = MockTransport { request in
            GatewayHTTPResponse(statusCode: 200, data: self.successResponseJSON(requestId: self.requestId(from: request)))
        }
        let result = try await makeClient(transport: transport).completeMonthlySummary(
            request: sampleRequest(),
            facts: sampleFacts(),
            riskAssessment: sampleRiskAssessment()
        )
        #expect(result.modelAlias == "mock-qwen")
        #expect(!result.draft.keyFacts.isEmpty)
    }

    @Test("invalid schema version")
    func invalidSchemaVersion() async throws {
        let transport = MockTransport { request in
            let body = "本月主要压力来自生活支出。预计月底结余约 ¥1500。数据来自 Account / Transaction。"
            let json = """
            {
              "schemaVersion": "v99",
              "requestId": "\(self.requestId(from: request))",
              "modelAlias": "mock-qwen",
              "draft": {
                "title": "本月财务摘要",
                "body": "\(body)",
                "answer": "\(body)",
                "citedFactKeys": [],
                "unknowns": [],
                "confidence": 0.9,
                "keyFacts": [],
                "warnings": [],
                "actions": [],
                "references": []
              }
            }
            """
            return GatewayHTTPResponse(statusCode: 200, data: Data(json.utf8))
        }
        await #expect(throws: AIGatewayError.unsupportedSchemaVersion) {
            _ = try await makeClient(transport: transport).completeMonthlySummary(
                request: sampleRequest(),
                facts: sampleFacts(),
                riskAssessment: sampleRiskAssessment()
            )
        }
    }

    @Test("400 invalidRequest")
    func invalidRequest() async {
        let transport = MockTransport { _ in
            GatewayHTTPResponse(statusCode: 400, data: self.errorResponseJSON(code: "invalidRequest"))
        }
        await #expect(throws: AIGatewayError.invalidRequest) {
            _ = try await makeClient(transport: transport).completeMonthlySummary(
                request: sampleRequest(),
                facts: sampleFacts(),
                riskAssessment: sampleRiskAssessment()
            )
        }
    }

    @Test("401 unauthorized")
    func unauthorized() async {
        let transport = MockTransport { _ in
            GatewayHTTPResponse(statusCode: 401, data: self.errorResponseJSON(code: "unauthorized"))
        }
        await #expect(throws: AIGatewayError.unauthorized) {
            _ = try await makeClient(transport: transport).completeMonthlySummary(
                request: sampleRequest(),
                facts: sampleFacts(),
                riskAssessment: sampleRiskAssessment()
            )
        }
    }

    @Test("429 rateLimited")
    func rateLimited() async {
        let transport = MockTransport { _ in
            GatewayHTTPResponse(statusCode: 429, data: self.errorResponseJSON(code: "rateLimited", retryAfter: 30))
        }
        do {
            _ = try await makeClient(transport: transport).completeMonthlySummary(
                request: sampleRequest(),
                facts: sampleFacts(),
                riskAssessment: sampleRiskAssessment()
            )
            Issue.record("expected rateLimited")
        } catch let error as AIGatewayError {
            if case .rateLimited(let retryAfter) = error {
                #expect(retryAfter == 30)
            } else {
                Issue.record("unexpected error \(error)")
            }
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test("503 providerUnavailable")
    func providerUnavailable() async {
        let transport = MockTransport { _ in
            GatewayHTTPResponse(statusCode: 503, data: self.errorResponseJSON(code: "providerUnavailable"))
        }
        await #expect(throws: AIGatewayError.providerUnavailable) {
            _ = try await makeClient(transport: transport).completeMonthlySummary(
                request: sampleRequest(),
                facts: sampleFacts(),
                riskAssessment: sampleRiskAssessment()
            )
        }
    }

    @Test("504 providerTimeout")
    func providerTimeout() async {
        let transport = MockTransport { _ in
            GatewayHTTPResponse(statusCode: 504, data: self.errorResponseJSON(code: "providerTimeout"))
        }
        await #expect(throws: AIGatewayError.providerTimeout) {
            _ = try await makeClient(transport: transport).completeMonthlySummary(
                request: sampleRequest(),
                facts: sampleFacts(),
                riskAssessment: sampleRiskAssessment()
            )
        }
    }

    @Test("invalid provider response")
    func invalidProviderResponse() async {
        let transport = MockTransport { _ in
            GatewayHTTPResponse(statusCode: 502, data: self.errorResponseJSON(code: "invalidProviderResponse"))
        }
        await #expect(throws: AIGatewayError.invalidProviderResponse) {
            _ = try await makeClient(transport: transport).completeMonthlySummary(
                request: sampleRequest(),
                facts: sampleFacts(),
                riskAssessment: sampleRiskAssessment()
            )
        }
    }

    @Test("timeout maps to providerTimeout")
    func timeout() async {
        struct TimeoutTransport: GatewayHTTPTransport {
            func perform(_ request: GatewayHTTPRequest) async throws -> GatewayHTTPResponse {
                throw URLError(.timedOut)
            }
        }
        let client = AIGatewayClient(
            configuration: AIGatewayConfiguration(baseURL: URL(string: "http://127.0.0.1:8080")!, timeout: 0.01),
            transport: TimeoutTransport(),
            maxRetryCount: 0
        )
        await #expect(throws: AIGatewayError.self) {
            _ = try await client.completeMonthlySummary(
                request: sampleRequest(),
                facts: sampleFacts(),
                riskAssessment: sampleRiskAssessment()
            )
        }
    }

    @Test("requestId echo")
    func requestIdEcho() async throws {
        let transport = MockTransport { request in
            let requestId = self.requestId(from: request)
            #expect(!requestId.isEmpty)
            return GatewayHTTPResponse(statusCode: 200, data: self.successResponseJSON(requestId: requestId))
        }
        let result = try await makeClient(transport: transport).completeMonthlySummary(
            request: sampleRequest(),
            facts: sampleFacts(),
            riskAssessment: sampleRiskAssessment()
        )
        #expect(!result.requestId.isEmpty)
    }

    @Test("retryable error retries at most once")
    func retryOnce() async throws {
        final class Counter: @unchecked Sendable { var value = 0 }
        let counter = Counter()
        let transport = MockTransport { request in
            counter.value += 1
            if counter.value == 1 {
                return GatewayHTTPResponse(statusCode: 503, data: self.errorResponseJSON(code: "providerUnavailable"))
            }
            return GatewayHTTPResponse(statusCode: 200, data: self.successResponseJSON(requestId: self.requestId(from: request)))
        }
        _ = try await makeClient(transport: transport, maxRetryCount: 1).completeMonthlySummary(
            request: sampleRequest(),
            facts: sampleFacts(),
            riskAssessment: sampleRiskAssessment()
        )
        #expect(counter.value == 2)
    }

    @Test("decoding failure does not retry")
    func decodingFailureNoRetry() async {
        final class Counter: @unchecked Sendable { var value = 0 }
        let counter = Counter()
        let transport = MockTransport { _ in
            counter.value += 1
            return GatewayHTTPResponse(statusCode: 200, data: Data("{".utf8))
        }
        await #expect(throws: AIGatewayError.decodingFailed) {
            _ = try await makeClient(transport: transport, maxRetryCount: 1).completeMonthlySummary(
                request: sampleRequest(),
                facts: sampleFacts(),
                riskAssessment: sampleRiskAssessment()
            )
        }
        #expect(counter.value == 1)
    }

    @Test("network DTO maps to domain draft")
    func mapper() {
        let dto = GatewayAssistantAnswerDraftDTO(
            title: "T",
            body: "B",
            answer: "A",
            citedFactKeys: [],
            disclaimer: nil,
            unknowns: [],
            confidence: 0.5,
            keyFacts: [],
            warnings: [],
            actions: [],
            references: []
        )
        let domain = GatewayAnswerDraftMapper.toDomain(dto)
        #expect(domain.title == "T")
        #expect(domain.answer == "A")
    }
}
