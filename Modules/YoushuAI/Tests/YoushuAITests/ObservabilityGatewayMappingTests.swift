import Foundation
import Testing
import YoushuAI
import YoushuFoundation

@Suite("Observability Gateway error mapping")
struct ObservabilityGatewayMappingTests {
    @Test("AIGatewayError codes map to taxonomy while preserving retryability")
    func gatewayErrorMapping() {
        let timeout = AIGatewayError.providerTimeout.observabilityClassification
        #expect(timeout.stage == .unknown)
        #expect(timeout.errorCode == .providerTimeout)
        #expect(timeout.retryability == .retryable)

        let unauthorized = AIGatewayError.unauthorized.observabilityClassification
        #expect(unauthorized.stage == .unknown)
        #expect(unauthorized.errorCode == .unauthorized)
        #expect(unauthorized.retryability == .notRetryable)

        let rateLimited = AIGatewayError.rateLimited(retryAfterSeconds: 2).observabilityClassification
        #expect(rateLimited.errorCode == .rateLimited)
        #expect(rateLimited.retryability == .notRetryable)

        let unavailable = AIGatewayError.providerUnavailable.observabilityClassification
        #expect(unavailable.errorCode == .providerUnavailable)
        #expect(unavailable.retryability == .retryable)

        let malformed = AIGatewayError.invalidProviderResponse.observabilityClassification
        #expect(malformed.stage == .unknown)
        #expect(malformed.errorCode == .invalidProviderResponse)
        #expect(malformed.retryability == .notRetryable)

        let decode = AIGatewayError.decodingFailed.observabilityClassification
        #expect(decode.stage == .clientResponseDecode)
        #expect(decode.errorCode == .responseDecodeFailure)

        let cancelledTransport = AIGatewayError.networkFailure("ignored localized text")
        let transport = cancelledTransport.observabilityClassification
        #expect(transport.stage == .clientTransport)
        #expect(transport.errorCode == .transportFailure)
        #expect(transport.retryability == .notRetryable)
    }

    @Test("gateway mapping does not copy arbitrary error text into events")
    func gatewayMappingOmitsRawText() throws {
        let error = AIGatewayError.networkFailure("prompt dump user question merchant note")
        let classified = error.observabilityClassification
        let event = ObservabilityEvent(
            requestId: ObservabilityRequestID.generate(),
            operation: .monthlySummary,
            outcome: .degraded,
            failureStage: classified.stage,
            errorCode: classified.errorCode,
            failureClass: classified.failureClass,
            retryability: classified.retryability
        )
        let text = String(decoding: try event.encodedJSON(), as: UTF8.self)
        #expect(!text.contains("prompt dump"))
        #expect(!text.contains("user question"))
        #expect(!text.contains("merchant"))
    }

    @Test("stable Gateway envelope codes map to client errors and retryability")
    func gatewayEnvelopeCodeMapping() {
        let gatewayLimited = AIGatewayError.mapGatewayErrorCode("gatewayRateLimited", retryAfter: 5)
        #expect(gatewayLimited == .gatewayRateLimited(retryAfterSeconds: 5))
        #expect(gatewayLimited.isRetryable == false)
        #expect(gatewayLimited.observabilityClassification.errorCode == .gatewayRateLimited)
        #expect(gatewayLimited.observabilityClassification.retryability == .notRetryable)

        let providerLimited = AIGatewayError.mapGatewayErrorCode("providerRateLimited", retryAfter: 8)
        #expect(providerLimited == .providerRateLimited(retryAfterSeconds: 8))
        #expect(providerLimited.isRetryable == false)
        #expect(providerLimited.observabilityClassification.errorCode == .providerRateLimited)

        let timeout = AIGatewayError.mapGatewayErrorCode("providerTimeout", retryAfter: nil)
        #expect(timeout == .providerTimeout)
        #expect(timeout.isRetryable)

        let unavailable = AIGatewayError.mapGatewayErrorCode("providerUnavailable", retryAfter: nil)
        #expect(unavailable == .providerUnavailable)
        #expect(unavailable.isRetryable)

        let rejected = AIGatewayError.mapGatewayErrorCode("providerRejectedRequest", retryAfter: nil)
        #expect(rejected == .invalidProviderResponse)
        #expect(rejected.isRetryable == false)

        let structured = AIGatewayError.mapGatewayErrorCode("structuredOutputDecodeFailure", retryAfter: nil)
        #expect(structured == .invalidProviderResponse)
        #expect(structured.isRetryable == false)

        let invalid = AIGatewayError.mapGatewayErrorCode("invalidProviderResponse", retryAfter: nil)
        #expect(invalid == .invalidProviderResponse)

        let internalError = AIGatewayError.mapGatewayErrorCode("internalError", retryAfter: nil)
        #expect(internalError == .internalError)
        #expect(internalError.isRetryable)

        let unknown = AIGatewayError.mapGatewayErrorCode("notAStableCode", retryAfter: nil)
        #expect(unknown == .invalidProviderResponse)
        #expect(unknown.isRetryable == false)
        #expect(unknown.observabilityClassification.errorCode == .invalidProviderResponse)
        #expect(unknown.observabilityClassification.retryability == .notRetryable)
        #expect(unknown.observabilityClassification.stage == .unknown)
    }

    @Test("Gateway envelope codes do not invent Gateway-internal stages")
    func envelopeDoesNotInventGatewayStages() {
        let forbiddenStages: Set<ObservabilityFailureStage> = [
            .providerTransport,
            .providerHTTP,
            .providerStructuredOutput,
            .factMaterialization,
            .gatewayResponseEncoding,
            .gatewayAuth,
            .gatewayRequestValidation,
        ]
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
            let mapped = AIGatewayError.mapGatewayErrorCode(code, retryAfter: nil)
            #expect(mapped.observabilityClassification.stage == .unknown, "code \(code)")
            #expect(!forbiddenStages.contains(mapped.observabilityClassification.stage))
        }
    }
}
