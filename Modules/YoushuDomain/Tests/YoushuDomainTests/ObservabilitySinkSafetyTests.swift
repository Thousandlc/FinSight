import Foundation
import Testing
import YoushuFoundation
import YoushuLogging

@Suite("Observability production sink safety")
struct ObservabilitySinkSafetyTests {
    @Test("local sink is production-safe log only and cannot throw")
    func sinkDoesNotThrowOrLeak() throws {
        let event = ObservabilityEvent(
            requestId: ObservabilityRequestID.generate(),
            operation: .monthlySummary,
            outcome: .failed,
            failureStage: .clientTransport,
            errorCode: .networkUnavailable,
            failureClass: .transient,
            retryability: .notRetryable
        )
        ObservabilityLogSink.emit(event)
        let text = String(decoding: try event.encodedJSON(), as: UTF8.self)
        for canary in [
            "QUESTION_SECRET_CANARY",
            "AUTH_SECRET_CANARY",
            "CLIENT_TOKEN_SECRET_CANARY",
            "localizedDescription",
            "SOURCE_ID_CANARY",
        ] {
            #expect(!text.contains(canary))
        }
        #expect(!text.contains("\"cost\""))
    }
}
