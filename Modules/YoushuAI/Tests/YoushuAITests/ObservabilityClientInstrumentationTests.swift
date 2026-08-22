import Foundation
import Testing
import YoushuAI
import YoushuDomain
import YoushuFoundation

@Suite("iOS AIGatewayClient observability instrumentation")
struct ObservabilityClientInstrumentationTests {
    private struct MockTransport: GatewayHTTPTransport {
        let handler: @Sendable (GatewayHTTPRequest) throws -> GatewayHTTPResponse

        func perform(_ request: GatewayHTTPRequest) async throws -> GatewayHTTPResponse {
            try handler(request)
        }
    }

    private struct CanaryTokenStore: SecureTokenStoring {
        func save(token: String, account: String) throws {}
        func load(account: String) throws -> String? { "AUTH_SECRET_CANARY" }
        func delete(account: String) throws {}
    }

    private func sampleFacts() -> MonthlySummaryFacts {
        MonthlySummaryFacts(
            availableCash: Money(amount: 1_000, currencyCode: "CNY"),
            monthlyIncome: Money(amount: 5_000, currencyCode: "CNY"),
            monthlyExpense: Money(amount: 3_000, currencyCode: "CNY"),
            monthlyDebtPayment: Money(amount: 500, currencyCode: "CNY"),
            debtPaymentToIncomePercent: nil,
            primaryPressure: "FINANCIAL_CONTEXT_SECRET_CANARY",
            estimatedMonthEndBalance: Money(amount: 1_500, currencyCode: "CNY"),
            sourceLabels: ["Account", "Transaction"]
        )
    }

    private func sampleRiskAssessment() -> FinancialRiskAssessment {
        FinancialRiskGatewayTestFixtures.safeKnownNoDebt()
    }

    private func sampleRequest() -> AssistantRequestDTO {
        AssistantRequestDTO(
            question: "QUESTION_SECRET_CANARY MERCHANT_SECRET_CANARY NOTE_SECRET_CANARY",
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
                spending: .init(topCategories: [
                    .init(
                        category: "FINANCIAL_CONTEXT_SECRET_CANARY",
                        amount: MoneyDTO(amount: 100, currencyCode: "CNY")
                    ),
                ]),
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
        {"schemaVersion":"v1","requestId":"ignored","error":{"code":"\(code)","message":"RAW_RESPONSE_SECRET_CANARY"\(retry)}}
        """
        return Data(json.utf8)
    }

    private func makeClient(
        transport: MockTransport,
        maxRetryCount: Int = 0,
        tokenStore: (any SecureTokenStoring)? = nil
    ) -> AIGatewayClient {
        AIGatewayClient(
            configuration: AIGatewayConfiguration(baseURL: URL(string: "http://127.0.0.1:8080")!),
            transport: transport,
            tokenStore: tokenStore,
            maxRetryCount: maxRetryCount,
            retryDelaySeconds: 0
        )
    }

    private func requestId(from request: GatewayHTTPRequest) -> String {
        request.headers["X-Youshu-Request-Id"] ?? ""
    }

    private func collect<T>(
        _ work: () async throws -> T
    ) async -> (result: Result<T, Error>, collector: ObservabilityEventCollector) {
        let collector = ObservabilityEventCollector()
        let result: Result<T, Error>
        do {
            let value = try await ObservabilityEmission.$collector.withValue(collector) {
                try await work()
            }
            result = .success(value)
        } catch {
            result = .failure(error)
        }
        return (result, collector)
    }

    private func assertNoCanaries(_ text: String) {
        for canary in [
            "QUESTION_SECRET_CANARY",
            "FINANCIAL_CONTEXT_SECRET_CANARY",
            "MERCHANT_SECRET_CANARY",
            "NOTE_SECRET_CANARY",
            "AUTH_SECRET_CANARY",
            "RAW_RESPONSE_SECRET_CANARY",
            "VALIDATOR_AMOUNT_CANARY",
            "localizedDescription",
        ] {
            #expect(!text.contains(canary), "telemetry leaked \(canary)")
        }
    }

    @Test("gatewayRateLimited is not retryable and does not fall through to internalError")
    func gatewayRateLimitedMapping() async throws {
        final class Counter: @unchecked Sendable { var value = 0 }
        let counter = Counter()
        let transport = MockTransport { _ in
            counter.value += 1
            return GatewayHTTPResponse(statusCode: 429, data: self.errorResponseJSON(code: "gatewayRateLimited", retryAfter: 9))
        }
        let collected = await collect {
            try await self.makeClient(transport: transport, maxRetryCount: 1).completeMonthlySummary(
                request: self.sampleRequest(),
                facts: self.sampleFacts(),
                riskAssessment: self.sampleRiskAssessment()
            )
        }
        #expect(counter.value == 1)
        guard case .failure(let error as AIGatewayError) = collected.result else {
            Issue.record("expected AIGatewayError")
            return
        }
        #expect(error == .gatewayRateLimited(retryAfterSeconds: 9))
        #expect(error.isRetryable == false)
        let event = try #require(collected.collector.last)
        #expect(event.errorCode == .gatewayRateLimited)
        #expect(event.retryability == .notRetryable)
        #expect(event.retryCount == 0)
        #expect(event.outcome == .failed)
        #expect(event.failureStage == .unknown)
        #expect(event.failureStage != .providerStructuredOutput)
        #expect(event.failureStage != .factMaterialization)
        assertNoCanaries(try collected.collector.encodedProductionOutput())
    }

    @Test("providerRateLimited is not retryable")
    func providerRateLimitedMapping() async throws {
        final class Counter: @unchecked Sendable { var value = 0 }
        let counter = Counter()
        let transport = MockTransport { _ in
            counter.value += 1
            return GatewayHTTPResponse(statusCode: 429, data: self.errorResponseJSON(code: "providerRateLimited"))
        }
        let collected = await collect {
            try await self.makeClient(transport: transport, maxRetryCount: 1).completeMonthlySummary(
                request: self.sampleRequest(),
                facts: self.sampleFacts(),
                riskAssessment: self.sampleRiskAssessment()
            )
        }
        #expect(counter.value == 1)
        guard case .failure(let error as AIGatewayError) = collected.result else {
            Issue.record("expected AIGatewayError")
            return
        }
        #expect(error == .providerRateLimited(retryAfterSeconds: nil))
        #expect(error.isRetryable == false)
        let event = try #require(collected.collector.last)
        #expect(event.errorCode == .providerRateLimited)
        #expect(event.retryability == .notRetryable)
        #expect(event.retryCount == 0)
        #expect(event.failureStage == .unknown)
    }

    @Test("Gateway envelopes do not invent providerTransport/providerHTTP/materialization stages")
    func gatewayEnvelopesUseUnknownStage() async throws {
        let codes = [
            "providerTimeout",
            "providerUnavailable",
            "providerRateLimited",
            "gatewayRateLimited",
            "structuredOutputDecodeFailure",
            "unknownFactSource",
            "materializationFailure",
        ]
        for code in codes {
            let transport = MockTransport { _ in
                GatewayHTTPResponse(statusCode: 502, data: self.errorResponseJSON(code: code))
            }
            let collected = await collect {
                try await self.makeClient(transport: transport, maxRetryCount: 0).completeMonthlySummary(
                    request: self.sampleRequest(),
                    facts: self.sampleFacts(),
                    riskAssessment: self.sampleRiskAssessment()
                )
            }
            let event = try #require(collected.collector.last)
            #expect(event.failureStage == .unknown, "code \(code)")
            #expect(event.failureStage != .providerTransport)
            #expect(event.failureStage != .providerHTTP)
            #expect(event.failureStage != .providerStructuredOutput)
            #expect(event.failureStage != .factMaterialization)
            let parsed = ObservabilityErrorCode(rawValue: code)
            if let parsed {
                #expect(event.errorCode == parsed, "code \(code)")
            }
            assertNoCanaries(try collected.collector.encodedProductionOutput())
        }
    }

    @Test("structuredOutputDecodeFailure stays invalidProviderResponse and not retryable")
    func structuredOutputEnvelope() async throws {
        let transport = MockTransport { _ in
            GatewayHTTPResponse(statusCode: 502, data: self.errorResponseJSON(code: "structuredOutputDecodeFailure"))
        }
        let collected = await collect {
            try await self.makeClient(transport: transport, maxRetryCount: 1).completeMonthlySummary(
                request: self.sampleRequest(),
                facts: self.sampleFacts(),
                riskAssessment: self.sampleRiskAssessment()
            )
        }
        guard case .failure(let error as AIGatewayError) = collected.result else {
            Issue.record("expected AIGatewayError")
            return
        }
        #expect(error == .invalidProviderResponse)
        #expect(error.isRetryable == false)
        let event = try #require(collected.collector.last)
        #expect(event.errorCode == .structuredOutputDecodeFailure)
        #expect(event.failureStage == .unknown)
        #expect(event.retryability == .notRetryable)
        #expect(event.retryCount == 0)
    }

    @Test("unknown envelope code is not retryable internalError")
    func unknownEnvelopeCode() async throws {
        final class Counter: @unchecked Sendable { var value = 0 }
        let counter = Counter()
        let transport = MockTransport { _ in
            counter.value += 1
            return GatewayHTTPResponse(statusCode: 500, data: self.errorResponseJSON(code: "totallyUnknownCode"))
        }
        let collected = await collect {
            try await self.makeClient(transport: transport, maxRetryCount: 1).completeMonthlySummary(
                request: self.sampleRequest(),
                facts: self.sampleFacts(),
                riskAssessment: self.sampleRiskAssessment()
            )
        }
        #expect(counter.value == 1)
        guard case .failure(let error as AIGatewayError) = collected.result else {
            Issue.record("expected AIGatewayError")
            return
        }
        #expect(error == .invalidProviderResponse)
        #expect(error.isRetryable == false)
        let event = try #require(collected.collector.last)
        #expect(event.errorCode == .invalidProviderResponse)
        #expect(event.retryability == .notRetryable)
    }

    @Test("timeout transport classifies as clientTransport without localized text")
    func timeoutTransport() async throws {
        struct TimeoutTransport: GatewayHTTPTransport {
            func perform(_ request: GatewayHTTPRequest) async throws -> GatewayHTTPResponse {
                throw URLError(.timedOut, userInfo: [NSLocalizedDescriptionKey: "localizedDescription timeout dump"])
            }
        }
        let client = AIGatewayClient(
            configuration: AIGatewayConfiguration(baseURL: URL(string: "http://127.0.0.1:8080")!),
            transport: TimeoutTransport(),
            maxRetryCount: 0,
            retryDelaySeconds: 0
        )
        let collector = ObservabilityEventCollector()
        do {
            _ = try await ObservabilityEmission.$collector.withValue(collector) {
                try await client.completeMonthlySummary(
                    request: sampleRequest(),
                    facts: sampleFacts(),
                    riskAssessment: sampleRiskAssessment()
                )
            }
            Issue.record("expected timeout")
        } catch let error as AIGatewayError {
            #expect(error == .providerTimeout)
        }
        let event = try #require(collector.last)
        #expect(event.failureStage == .clientTransport)
        #expect(event.errorCode == .timeout)
        #expect(event.outcome == .failed)
        assertNoCanaries(try collector.encodedProductionOutput())
        let timeoutText = try collector.encodedProductionOutput()
        #expect(!timeoutText.contains("timeout dump"))
    }

    @Test("network unavailable classifies without arbitrary error text")
    func networkUnavailable() async throws {
        struct OfflineTransport: GatewayHTTPTransport {
            func perform(_ request: GatewayHTTPRequest) async throws -> GatewayHTTPResponse {
                throw URLError(.notConnectedToInternet, userInfo: [
                    NSLocalizedDescriptionKey: "localizedDescription QUESTION_SECRET_CANARY",
                ])
            }
        }
        let client = AIGatewayClient(
            configuration: AIGatewayConfiguration(baseURL: URL(string: "http://127.0.0.1:8080")!),
            transport: OfflineTransport(),
            maxRetryCount: 0
        )
        let collector = ObservabilityEventCollector()
        do {
            _ = try await ObservabilityEmission.$collector.withValue(collector) {
                try await client.completeMonthlySummary(
                    request: sampleRequest(),
                    facts: sampleFacts(),
                    riskAssessment: sampleRiskAssessment()
                )
            }
            Issue.record("expected network failure")
        } catch let error as AIGatewayError {
            #expect(error == .networkFailure("transportFailure"))
        }
        let event = try #require(collector.last)
        #expect(event.failureStage == .clientTransport)
        #expect(event.errorCode == .networkUnavailable)
        #expect(event.retryability == .notRetryable)
        assertNoCanaries(try collector.encodedProductionOutput())
    }

    @Test("cancellation maps to cancelled and does not retry")
    func cancelledTransport() async throws {
        final class Counter: @unchecked Sendable { var value = 0 }
        let counter = Counter()
        struct CancelTransport: GatewayHTTPTransport {
            let counter: Counter
            func perform(_ request: GatewayHTTPRequest) async throws -> GatewayHTTPResponse {
                counter.value += 1
                throw URLError(.cancelled)
            }
        }
        let client = AIGatewayClient(
            configuration: AIGatewayConfiguration(baseURL: URL(string: "http://127.0.0.1:8080")!),
            transport: CancelTransport(counter: counter),
            maxRetryCount: 1,
            retryDelaySeconds: 0
        )
        let collector = ObservabilityEventCollector()
        do {
            _ = try await ObservabilityEmission.$collector.withValue(collector) {
                try await client.completeMonthlySummary(
                    request: sampleRequest(),
                    facts: sampleFacts(),
                    riskAssessment: sampleRiskAssessment()
                )
            }
            Issue.record("expected cancellation")
        } catch is CancellationError {
            // expected
        }
        #expect(counter.value == 1)
        let event = try #require(collector.last)
        #expect(event.outcome == .cancelled)
        #expect(event.errorCode == .cancelled)
        #expect(event.failureStage == .clientTransport)
        #expect(event.retryCount == 0)
    }

    @Test("malformed success body is clientResponseDecode and does not retry")
    func responseDecodeFailure() async throws {
        final class Counter: @unchecked Sendable { var value = 0 }
        let counter = Counter()
        let transport = MockTransport { _ in
            counter.value += 1
            return GatewayHTTPResponse(
                statusCode: 200,
                data: Data("{\"RAW_RESPONSE_SECRET_CANARY\":true".utf8)
            )
        }
        let collected = await collect {
            try await self.makeClient(transport: transport, maxRetryCount: 1).completeMonthlySummary(
                request: self.sampleRequest(),
                facts: self.sampleFacts(),
                riskAssessment: self.sampleRiskAssessment()
            )
        }
        #expect(counter.value == 1)
        guard case .failure(let error as AIGatewayError) = collected.result else {
            Issue.record("expected decode failure")
            return
        }
        #expect(error == .decodingFailed)
        let event = try #require(collected.collector.last)
        #expect(event.failureStage == .clientResponseDecode)
        #expect(event.errorCode == .responseDecodeFailure)
        #expect(event.retryCount == 0)
        #expect(event.schemaStage == .clientDraft)
        assertNoCanaries(try collected.collector.encodedProductionOutput())
    }

    @Test("retryCount is 0 when the first attempt succeeds")
    func noRetryOnSuccess() async throws {
        let transport = MockTransport { request in
            GatewayHTTPResponse(statusCode: 200, data: self.successResponseJSON(requestId: self.requestId(from: request)))
        }
        let collected = await collect {
            try await self.makeClient(transport: transport, maxRetryCount: 1).completeMonthlySummary(
                request: self.sampleRequest(),
                facts: self.sampleFacts(),
                riskAssessment: self.sampleRiskAssessment()
            )
        }
        let value = try collected.result.get()
        let event = try #require(collected.collector.last)
        #expect(event.outcome == .success)
        #expect(event.retryCount == 0)
        #expect(event.requestId == value.requestId)
        #expect(ObservabilityRequestID.isWellFormed(event.requestId))
    }

    @Test("one retry then success reuses requestId and counts one client retry")
    func retryThenSuccessSameRequestId() async throws {
        final class State: @unchecked Sendable {
            var count = 0
            var ids: [String] = []
        }
        let state = State()
        let transport = MockTransport { request in
            state.count += 1
            let id = self.requestId(from: request)
            state.ids.append(id)
            if state.count == 1 {
                return GatewayHTTPResponse(statusCode: 503, data: self.errorResponseJSON(code: "providerUnavailable"))
            }
            return GatewayHTTPResponse(statusCode: 200, data: self.successResponseJSON(requestId: id))
        }
        let collected = await collect {
            try await self.makeClient(transport: transport, maxRetryCount: 1).completeMonthlySummary(
                request: self.sampleRequest(),
                facts: self.sampleFacts(),
                riskAssessment: self.sampleRiskAssessment()
            )
        }
        let value = try collected.result.get()
        #expect(state.count == 2)
        #expect(state.ids.count == 2)
        #expect(state.ids[0] == state.ids[1])
        #expect(value.requestId == state.ids[0])
        let event = try #require(collected.collector.last)
        #expect(event.outcome == .success)
        #expect(event.retryCount == 1)
        #expect(event.requestId == state.ids[0])
        assertNoCanaries(try collected.collector.encodedProductionOutput())
    }

    @Test("one retry then terminal failure reports retryCount 1")
    func retryThenFailure() async throws {
        final class Counter: @unchecked Sendable { var value = 0 }
        let counter = Counter()
        let transport = MockTransport { request in
            counter.value += 1
            return GatewayHTTPResponse(statusCode: 500, data: self.errorResponseJSON(code: "internalError"))
        }
        let collected = await collect {
            try await self.makeClient(transport: transport, maxRetryCount: 1).completeMonthlySummary(
                request: self.sampleRequest(),
                facts: self.sampleFacts(),
                riskAssessment: self.sampleRiskAssessment()
            )
        }
        #expect(counter.value == 2)
        guard case .failure(let error as AIGatewayError) = collected.result else {
            Issue.record("expected internalError")
            return
        }
        #expect(error == .internalError)
        let event = try #require(collected.collector.last)
        #expect(event.outcome == .failed)
        #expect(event.retryCount == 1)
        #expect(event.errorCode == .internalError)
        #expect(event.retryability == .retryable)
    }

    @Test("requestId is sent on X-Youshu-Request-Id and matches the local event")
    func requestIdCorrelation() async throws {
        final class Header: @unchecked Sendable { var value = "" }
        let header = Header()
        let transport = MockTransport { request in
            header.value = request.headers["X-Youshu-Request-Id"] ?? ""
            #expect(request.headers["Authorization"] == "Bearer AUTH_SECRET_CANARY")
            return GatewayHTTPResponse(statusCode: 200, data: self.successResponseJSON(requestId: header.value))
        }
        let collected = await collect {
            try await self.makeClient(
                transport: transport,
                tokenStore: CanaryTokenStore()
            ).completeMonthlySummary(
                request: self.sampleRequest(),
                facts: self.sampleFacts(),
                riskAssessment: self.sampleRiskAssessment()
            )
        }
        let value = try collected.result.get()
        let event = try #require(collected.collector.last)
        #expect(header.value == value.requestId)
        #expect(event.requestId == header.value)
        #expect(ObservabilityRequestID.isWellFormed(event.requestId))
        assertNoCanaries(try collected.collector.encodedProductionOutput())
    }

    @Test("providerTimeout envelope remains retryable")
    func providerTimeoutRetryable() async throws {
        final class Counter: @unchecked Sendable { var value = 0 }
        let counter = Counter()
        let transport = MockTransport { _ in
            counter.value += 1
            return GatewayHTTPResponse(statusCode: 504, data: self.errorResponseJSON(code: "providerTimeout"))
        }
        let collected = await collect {
            try await self.makeClient(transport: transport, maxRetryCount: 1).completeMonthlySummary(
                request: self.sampleRequest(),
                facts: self.sampleFacts(),
                riskAssessment: self.sampleRiskAssessment()
            )
        }
        #expect(counter.value == 2)
        guard case .failure(let error as AIGatewayError) = collected.result else {
            Issue.record("expected providerTimeout")
            return
        }
        #expect(error == .providerTimeout)
        #expect(error.isRetryable)
        let event = try #require(collected.collector.last)
        #expect(event.retryCount == 1)
        #expect(event.errorCode == .providerTimeout)
        #expect(event.failureStage == .unknown)
    }
}
