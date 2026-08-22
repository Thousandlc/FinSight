import Foundation
import Testing
import YoushuFoundation

@Suite("Observability event privacy and token contract")
struct ObservabilityEventContractTests {
    private static let forbiddenKeys: Set<String> = [
        "rawError", "errorDescription", "responseBody", "requestBody",
        "prompt", "question", "financialContext", "factPack",
        "merchant", "note", "imageData", "authorizationHeader",
        "authorization", "apiKey", "token", "userId", "sourceIds",
        "rawPayload", "localizedDescription",
    ]

    @Test("production event coding keys omit sensitive/raw fields")
    func encodedEventOmitsSensitiveKeys() throws {
        let event = ObservabilityEvent(
            requestId: ObservabilityRequestID.generate(),
            operation: .monthlySummary,
            outcome: .degraded,
            failureStage: .assistantValidation,
            errorCode: .validationRejected,
            failureClass: .dataIntegrity,
            retryability: .notRetryable,
            durationMs: 42,
            retryCount: 1,
            provider: "bailian",
            model: "qwen",
            providerStatus: "200",
            schemaStage: .gatewayDraft,
            validatorFailureType: .inventedAmount,
            tokenUsage: ObservabilityTokenUsage(inputTokens: 11, outputTokens: 7, totalTokens: 18),
            cost: nil,
            appVersion: "0.1.0",
            gatewayVersion: "dev"
        )
        let data = try event.encodedJSON()
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let keys = Set(json.keys)
        for forbidden in Self.forbiddenKeys {
            #expect(!keys.contains(forbidden), "unexpected key \(forbidden)")
        }
        #expect(keys.contains("requestId"))
        #expect(keys.contains("operation"))
        #expect(keys.contains("outcome"))
        #expect(keys.contains("validatorFailureType"))
        #expect(json["cost"] == nil)
        let text = String(decoding: data, as: UTF8.self)
        #expect(!text.contains("invented amount 12.00"))
        #expect(!text.contains("Bearer "))
        #expect(!text.contains("sk-"))
    }

    @Test("request id is opaque UUID and independent of user/financial ids")
    func requestIDContract() {
        let userId = UUID()
        let accountId = UUID()
        let requestId = ObservabilityRequestID.generate()
        #expect(ObservabilityRequestID.isWellFormed(requestId))
        #expect(requestId != userId.uuidString)
        #expect(requestId != accountId.uuidString)
        #expect(ObservabilityRequestID.generate() != requestId)
    }

    @Test("missing and partial token usage are valid; cost stays absent")
    func tokenUsageContract() throws {
        let missing = ObservabilityEvent(
            requestId: ObservabilityRequestID.generate(),
            operation: .ask,
            outcome: .success,
            tokenUsage: nil,
            cost: nil
        )
        let missingJSON = try JSONSerialization.jsonObject(with: try missing.encodedJSON()) as? [String: Any]
        #expect(missingJSON?["tokenUsage"] == nil)
        #expect(missingJSON?["cost"] == nil)

        let emptyUsage = ObservabilityEvent(
            requestId: ObservabilityRequestID.generate(),
            operation: .ask,
            outcome: .success,
            tokenUsage: ObservabilityTokenUsage(),
            cost: nil
        )
        let emptyJSON = try JSONSerialization.jsonObject(with: try emptyUsage.encodedJSON()) as? [String: Any]
        #expect(emptyJSON?["tokenUsage"] == nil)

        let partial = ObservabilityTokenUsage(inputTokens: 4, outputTokens: nil, totalTokens: nil)
        #expect(partial.inputTokens == 4)
        #expect(partial.outputTokens == nil)
        #expect(partial.totalTokens == nil)
        #expect(!partial.isEmpty)

        let known = ObservabilityTokenUsage(inputTokens: 10, outputTokens: 5, totalTokens: 15)
        #expect(known.totalTokens == 15)
        #expect(ObservabilityCostMetadata(source: .providerReported).source == .providerReported)
    }
}
