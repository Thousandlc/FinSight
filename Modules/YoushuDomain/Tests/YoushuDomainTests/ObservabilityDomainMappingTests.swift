import Foundation
import Testing
import YoushuDomain
import YoushuFoundation

@Suite("Observability Domain error mapping")
struct ObservabilityDomainMappingTests {
    @Test("validator rejection maps to assistantValidation without associated strings")
    func validatorMappingOmitsAssociatedValues() throws {
        let error = AssistantValidationError.inventedAmount("VALIDATOR_AMOUNT_CANARY")
        let classified = error.observabilityClassification
        #expect(classified.stage == .assistantValidation)
        #expect(classified.errorCode == .validationRejected)
        #expect(classified.validatorFailureType == .inventedAmount)
        #expect(classified.retryability == .notRetryable)

        let event = ObservabilityEvent(
            requestId: ObservabilityRequestID.generate(),
            operation: .monthlySummary,
            outcome: .degraded,
            failureStage: classified.stage,
            errorCode: classified.errorCode,
            failureClass: classified.failureClass,
            retryability: classified.retryability,
            validatorFailureType: classified.validatorFailureType
        )
        let text = String(decoding: try event.encodedJSON(), as: UTF8.self)
        #expect(!text.contains("VALIDATOR_AMOUNT_CANARY"))
        #expect(!text.contains("12.50"))
        #expect(text.contains("inventedAmount"))
    }

    @Test("consent required maps to consent stage")
    func consentMapping() {
        let classified = PrivacyError.consentRequired("财务助手 Context").observabilityClassification
        #expect(classified.stage == .consent)
        #expect(classified.errorCode == .consentRequired)
        #expect(classified.failureClass == .policy)
        #expect(classified.retryability == .notRetryable)
    }
}
