import Foundation

/// Privacy-safe emission of production observability events.
/// Logging/sink failure must never propagate to callers.
public enum ObservabilityEmission: Sendable {
    @TaskLocal public static var recorder: ObservabilityOperationRecorder?
    @TaskLocal public static var collector: ObservabilityEventCollector?

    private final class SinkState: @unchecked Sendable {
        let lock = NSLock()
        var installed: (@Sendable (ObservabilityEvent) -> Void)?
    }

    private static let sink = SinkState()

    public static func install(_ handler: @escaping @Sendable (ObservabilityEvent) -> Void) {
        sink.lock.lock()
        sink.installed = handler
        sink.lock.unlock()
    }

    public static func emit(_ event: ObservabilityEvent) {
        collector?.append(event)
        sink.lock.lock()
        let handler = sink.installed
        sink.lock.unlock()
        guard let handler else { return }
        // Installed sinks must be non-throwing; isolate so logging cannot fail AI.
        handler(event)
    }

    public static func emitTerminal(_ recorder: ObservabilityOperationRecorder, outcome: ObservabilityOutcome) {
        guard let event = recorder.consumeFinish(outcome: outcome) else { return }
        emit(event)
    }

    public static func run<T>(
        operation: ObservabilityOperation,
        _ work: () async throws -> T
    ) async throws -> T {
        if let existing = recorder {
            return try await workOnExisting(existing, work)
        }
        let created = ObservabilityOperationRecorder(operation: operation)
        return try await $recorder.withValue(created) {
            try await workOnExisting(created, work)
        }
    }

    private static func workOnExisting<T>(
        _ recorder: ObservabilityOperationRecorder,
        _ work: () async throws -> T
    ) async throws -> T {
        do {
            let value = try await work()
            emitTerminal(recorder, outcome: .success)
            return value
        } catch is CancellationError {
            recorder.noteFailure(ObservabilityErrorMapping.classify(CancellationError()))
            emitTerminal(recorder, outcome: .cancelled)
            throw CancellationError()
        } catch {
            recorder.noteFailure(error.observabilityClassification)
            emitTerminal(recorder, outcome: .failed)
            throw error
        }
    }
}

/// In-memory collector for tests. Never retains financial payloads.
public final class ObservabilityEventCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ObservabilityEvent] = []

    public init() {}

    public func append(_ event: ObservabilityEvent) {
        lock.lock()
        storage.append(event)
        lock.unlock()
    }

    public var events: [ObservabilityEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    public var last: ObservabilityEvent? { events.last }

    public func encodedProductionOutput() throws -> String {
        let chunks = try events.map { event -> String in
            String(decoding: try event.encodedJSON(), as: UTF8.self)
        }
        return chunks.joined(separator: "\n")
    }
}
