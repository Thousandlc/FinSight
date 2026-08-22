import Foundation
import Testing
import YoushuData
import YoushuFoundation

@Suite("Observability persistence mapping")
struct ObservabilityPersistenceMappingTests {
    @Test("persistence failure maps to insightPersistence")
    func persistenceMapping() {
        let classified = DataError.persistenceFailed("store").observabilityClassification
        #expect(classified.stage == .insightPersistence)
        #expect(classified.errorCode == .persistenceFailure)
        #expect(classified.failureClass == .permanent)
        #expect(classified.retryability == .notRetryable)
    }

    @Test("persistence classification does not copy repository diagnostic text")
    func persistenceMappingOmitsAssociatedText() throws {
        let classified = DataError.persistenceFailed("SOURCE_ID_CANARY").observabilityClassification
        let event = ObservabilityEvent(
            requestId: ObservabilityRequestID.generate(),
            operation: .insight,
            outcome: .failed,
            failureStage: classified.stage,
            errorCode: classified.errorCode,
            failureClass: classified.failureClass,
            retryability: classified.retryability
        )
        let text = String(decoding: try event.encodedJSON(), as: UTF8.self)
        #expect(!text.contains("SOURCE_ID_CANARY"))
        #expect(text.contains("insightPersistence"))
        #expect(text.contains("persistenceFailure"))
    }
}
