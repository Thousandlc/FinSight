import Foundation

/// Operation-scoped recorder for one remote AI operation.
/// Holds only allowlisted metadata — never payloads, prompts, or financial values.
public final class ObservabilityOperationRecorder: @unchecked Sendable {
    public let requestId: String
    public let operation: ObservabilityOperation
    private let started: ContinuousClock.Instant
    private let lock = NSLock()
    private var retryCountValue = 0
    private var classification: ObservabilityClassification?
    private var provider: String?
    private var model: String?
    private var providerStatus: String?
    private var schemaStage: ObservabilitySchemaStage?
    private var terminalOutcome: ObservabilityOutcome?
    private var emitted = false

    public init(
        operation: ObservabilityOperation,
        requestId: String = ObservabilityRequestID.generate()
    ) {
        self.operation = operation
        self.requestId = requestId
        self.started = ContinuousClock.now
    }

    public var retryCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return retryCountValue
    }

    public var hasFailure: Bool {
        lock.lock()
        defer { lock.unlock() }
        return classification != nil
    }

    public func noteClientRetry() {
        lock.lock()
        defer { lock.unlock() }
        retryCountValue += 1
    }

    public func noteProvider(name: String?, model: String? = nil, status: String? = nil) {
        lock.lock()
        defer { lock.unlock() }
        if let name, self.provider == nil { self.provider = name }
        if let model, self.model == nil { self.model = model }
        if let status { self.providerStatus = status }
    }

    public func noteSchemaStage(_ stage: ObservabilitySchemaStage) {
        lock.lock()
        defer { lock.unlock() }
        schemaStage = stage
    }

    /// First failure wins so an inner client-visible classification is not overwritten
    /// by a coarser outer mapping of the thrown error.
    public func noteFailure(_ next: ObservabilityClassification) {
        lock.lock()
        defer { lock.unlock() }
        if classification == nil {
            classification = next
        }
    }

    public func noteSuccess() {
        lock.lock()
        defer { lock.unlock() }
        if terminalOutcome == nil {
            terminalOutcome = .success
            classification = nil
        }
    }

    public func consumeFinish(outcome: ObservabilityOutcome) -> ObservabilityEvent? {
        lock.lock()
        if emitted {
            lock.unlock()
            return nil
        }
        emitted = true
        terminalOutcome = outcome
        let classified = classification
        let retries = retryCountValue
        let providerName = provider
        let modelName = model
        let status = providerStatus
        let schema = schemaStage
        lock.unlock()

        let elapsed = started.duration(to: ContinuousClock.now)
        let duration = max(0, Int(elapsed.components.seconds * 1000)
            + Int(elapsed.components.attoseconds / 1_000_000_000_000_000))
        let success = outcome == .success
        return ObservabilityEvent(
            requestId: requestId,
            operation: operation,
            outcome: outcome,
            failureStage: success ? nil : classified?.stage,
            errorCode: success ? nil : classified?.errorCode,
            failureClass: success ? nil : classified?.failureClass,
            retryability: success ? nil : classified?.retryability,
            durationMs: duration,
            retryCount: retries,
            provider: providerName,
            model: modelName,
            providerStatus: status,
            schemaStage: schema,
            validatorFailureType: success ? nil : classified?.validatorFailureType
        )
    }
}
