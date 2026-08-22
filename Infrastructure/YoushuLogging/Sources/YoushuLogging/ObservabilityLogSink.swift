import Foundation
import YoushuFoundation

/// Local structured production-safe log for canonical observability events.
/// This is **not** remote aggregation (no vendor, no network shipping).
/// Encoding/print failure is swallowed and cannot fail AI or financial work.
public enum ObservabilityLogSink {
    public static func install() {
        ObservabilityEmission.install { event in
            emit(event)
        }
    }

    public static func emit(_ event: ObservabilityEvent) {
        guard let payload = try? event.encodedJSON(),
              let text = String(data: payload, encoding: .utf8)
        else { return }
        let safe = LogRedactor.redact(text)
        print("[youshu.observability] \(safe)")
    }
}
