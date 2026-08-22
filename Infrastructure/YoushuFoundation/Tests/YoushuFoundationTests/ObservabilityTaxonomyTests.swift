import Foundation
import Testing
import YoushuFoundation

@Suite("Observability taxonomy contract")
struct ObservabilityTaxonomyTests {
    @Test("timeout maps to client/provider transport taxonomy")
    func timeoutClassification() {
        let classified = ObservabilityErrorMapping.classify(
            URLError(.timedOut)
        )
        #expect(classified.stage == .clientTransport)
        #expect(classified.errorCode == .timeout)
        #expect(classified.failureClass == .transient)
        #expect(classified.retryability == .retryable)
    }

    @Test("401/403-style auth failures are security and not retryable")
    func authFailureClassification() {
        let unauthorized = ObservabilityErrorMapping.classifyHTTPStatus(401)
        #expect(unauthorized.stage == .gatewayAuth)
        #expect(unauthorized.errorCode == .unauthorized)
        #expect(unauthorized.failureClass == .security)
        #expect(unauthorized.retryability == .notRetryable)

        let forbidden = ObservabilityErrorMapping.classifyHTTPStatus(403)
        #expect(forbidden.errorCode == .forbidden)
        #expect(forbidden.failureClass == .security)
        #expect(forbidden.retryability == .notRetryable)
    }

    @Test("429 rate limit is transient and not auto-retryable")
    func rateLimitClassification() {
        let classified = ObservabilityErrorMapping.classifyHTTPStatus(429)
        #expect(classified.stage == .providerHTTP)
        #expect(classified.errorCode == .rateLimited)
        #expect(classified.failureClass == .transient)
        #expect(classified.retryability == .notRetryable)
    }

    @Test("rate-limit codes match actual non-retry policy")
    func rateLimitRetryabilityFollowUp() {
        for code in [ObservabilityErrorCode.rateLimited, .gatewayRateLimited, .providerRateLimited] {
            let attributes = ObservabilityErrorMapping.attributes(for: code)
            #expect(attributes.failureClass == .transient)
            #expect(attributes.retryability == .notRetryable)
        }
        #expect(ObservabilityErrorMapping.attributes(for: .providerTimeout).retryability == .retryable)
        #expect(ObservabilityErrorMapping.attributes(for: .providerUnavailable).retryability == .retryable)
        #expect(ObservabilityErrorMapping.attributes(for: .unknown).retryability == .notRetryable)
        #expect(ObservabilityErrorMapping.attributes(for: .networkUnavailable).retryability == .notRetryable)
        #expect(ObservabilityErrorMapping.attributes(for: .transportFailure).retryability == .notRetryable)
        #expect(ObservabilityErrorMapping.attributes(for: .timeout).retryability == .retryable)
        #expect(ObservabilityErrorMapping.attributes(for: .internalError).retryability == .retryable)
        #expect(ObservabilityErrorMapping.attributes(for: .cancelled).retryability == .notRetryable)
    }

    @Test("provider 5xx/unavailable is transient and retryable")
    func providerUnavailableClassification() {
        let classified = ObservabilityErrorMapping.classifyHTTPStatus(503)
        #expect(classified.stage == .providerHTTP)
        #expect(classified.errorCode == .providerUnavailable)
        #expect(classified.failureClass == .transient)
        #expect(classified.retryability == .retryable)
    }

    @Test("structured output failure stays distinct from materialization and validation")
    func structuredOutputDistinct() {
        let structured = ObservabilityErrorMapping.classify(
            code: .structuredOutputDecodeFailure,
            stage: .providerStructuredOutput
        )
        let materialization = ObservabilityErrorMapping.classify(
            code: .materializationFailure,
            stage: .factMaterialization
        )
        let unknownFact = ObservabilityErrorMapping.classify(
            code: .unknownFactSource,
            stage: .factMaterialization
        )
        let validation = ObservabilityErrorMapping.classify(
            code: .validationRejected,
            stage: .assistantValidation,
            validatorFailureType: .inventedAmount
        )
        #expect(structured.stage == .providerStructuredOutput)
        #expect(materialization.stage == .factMaterialization)
        #expect(unknownFact.stage == .factMaterialization)
        #expect(validation.stage == .assistantValidation)
        #expect(Set([structured.stage, materialization.stage, validation.stage]).count == 3)
        #expect(structured.errorCode != materialization.errorCode)
        #expect(validation.validatorFailureType == .inventedAmount)
        #expect(structured.retryability == .notRetryable)
        #expect(materialization.retryability == .notRetryable)
    }

    @Test("client response decode failure is data integrity and not retryable")
    func clientDecodeClassification() {
        let classified = ObservabilityErrorMapping.classify(
            code: .responseDecodeFailure,
            stage: .clientResponseDecode
        )
        #expect(classified.stage == .clientResponseDecode)
        #expect(classified.errorCode == .responseDecodeFailure)
        #expect(classified.failureClass == .dataIntegrity)
        #expect(classified.retryability == .notRetryable)
    }

    @Test("validator rejection uses allowlisted failure type")
    func validatorRejectionClassification() {
        let classified = ObservabilityErrorMapping.classify(
            code: .validationRejected,
            stage: .assistantValidation,
            validatorFailureType: .citedUnknownFact
        )
        #expect(classified.stage == .assistantValidation)
        #expect(classified.errorCode == .validationRejected)
        #expect(classified.validatorFailureType == .citedUnknownFact)
        #expect(classified.retryability == .notRetryable)
    }

    @Test("persistence failure is permanent and not retryable")
    func persistenceClassification() {
        let classified = ObservabilityErrorMapping.classify(
            code: .persistenceFailure,
            stage: .insightPersistence
        )
        #expect(classified.stage == .insightPersistence)
        #expect(classified.errorCode == .persistenceFailure)
        #expect(classified.failureClass == .permanent)
        #expect(classified.retryability == .notRetryable)
    }

    @Test("cancellation is not retryable")
    func cancellationClassification() {
        let classified = ObservabilityErrorMapping.classify(CancellationError())
        #expect(classified.errorCode == .cancelled)
        #expect(classified.retryability == .notRetryable)
        #expect(classified.failureClass == .policy)
    }

    @Test("unknown error is conservative and not retryable")
    func unknownErrorClassification() {
        struct UnclassifiedError: Error {}
        let classified = ObservabilityErrorMapping.classify(UnclassifiedError())
        #expect(classified == .unclassified)
        #expect(classified.retryability == .notRetryable)
        #expect(classified.errorCode == .unknown)
    }

    @Test("existing Gateway codes parse without renaming")
    func existingGatewayCodesPreserved() {
        #expect(ObservabilityErrorMapping.parseErrorCode("invalidRequest") == .invalidRequest)
        #expect(ObservabilityErrorMapping.parseErrorCode("providerTimeout") == .providerTimeout)
        #expect(ObservabilityErrorMapping.parseErrorCode("invalidProviderResponse") == .invalidProviderResponse)
        #expect(ObservabilityErrorMapping.parseErrorCode("not-a-code") == .unknown)
    }

    @Test("outcomes distinguish success, degraded, failed, and cancelled")
    func outcomeSemantics() {
        #expect(ObservabilityOutcome.homeAIEnrichment(remoteFailed: false, homeAvailable: true) == .success)
        #expect(ObservabilityOutcome.homeAIEnrichment(remoteFailed: true, homeAvailable: true) == .degraded)
        #expect(ObservabilityOutcome.homeAIEnrichment(remoteFailed: true, homeAvailable: false) == .failed)
        #expect(ObservabilityOutcome.cancelled != .failed)
        #expect(ObservabilityOutcome.degraded != .failed)
    }
}
