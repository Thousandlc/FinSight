import Foundation
import Testing
import YoushuFoundation

@Suite("Observability operation recorder")
struct ObservabilityRecorderTests {
    @Test("first failure wins and consumeFinish is one-shot")
    func firstFailureAndConsumeOnce() throws {
        let recorder = ObservabilityOperationRecorder(operation: .monthlySummary)
        recorder.noteFailure(
            ObservabilityErrorMapping.classify(code: .timeout, stage: .clientTransport)
        )
        recorder.noteFailure(
            ObservabilityErrorMapping.classify(code: .internalError, stage: .unknown)
        )
        recorder.noteClientRetry()

        let first = recorder.consumeFinish(outcome: .failed)
        let second = recorder.consumeFinish(outcome: .failed)
        #expect(second == nil)
        let event = try #require(first)
        #expect(event.errorCode == .timeout)
        #expect(event.failureStage == .clientTransport)
        #expect(event.retryCount == 1)
        #expect(ObservabilityRequestID.isWellFormed(event.requestId))
    }

    @Test("success clears a prior retryable classification")
    func successClearsClassification() throws {
        let recorder = ObservabilityOperationRecorder(operation: .monthlySummary)
        recorder.noteFailure(
            ObservabilityErrorMapping.classify(code: .providerUnavailable, stage: .providerHTTP)
        )
        recorder.noteClientRetry()
        recorder.noteSuccess()
        let event = try #require(recorder.consumeFinish(outcome: .success))
        #expect(event.outcome == .success)
        #expect(event.errorCode == nil)
        #expect(event.failureStage == nil)
        #expect(event.retryCount == 1)
    }
}
