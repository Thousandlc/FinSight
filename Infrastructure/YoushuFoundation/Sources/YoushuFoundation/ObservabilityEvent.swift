import Foundation

/// Opaque correlation identifier for one remote AI operation.
/// Not derived from User ID or financial entity IDs.
public enum ObservabilityRequestID: Sendable {
    public static func generate() -> String {
        UUID().uuidString
    }

    public static func isWellFormed(_ value: String) -> Bool {
        UUID(uuidString: value) != nil
    }
}

/// Provider-reported token counts. Missing usage is valid.
/// `inputTokens` maps to Gateway `promptTokens`; `outputTokens` maps to `completionTokens`.
public struct ObservabilityTokenUsage: Codable, Equatable, Sendable {
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var totalTokens: Int?

    public init(inputTokens: Int? = nil, outputTokens: Int? = nil, totalTokens: Int? = nil) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
    }

    public var isEmpty: Bool {
        inputTokens == nil && outputTokens == nil && totalTokens == nil
    }
}

/// Cost is optional and must declare provenance. Amount is omitted unless a future
/// trustworthy source exists — this step does not invent pricing.
public enum ObservabilityCostSource: String, Codable, Sendable, CaseIterable {
    case providerReported
    case externallyCalculated
    case estimated
}

public struct ObservabilityCostMetadata: Codable, Equatable, Sendable {
    public var source: ObservabilityCostSource

    public init(source: ObservabilityCostSource) {
        self.source = source
    }
}

/// Privacy-safe production observability record.
/// Forbidden by design: raw payloads, prompts, questions, merchant/note, UUIDs/sourceIds,
/// image bytes, Provider bodies, API keys/tokens, Authorization, arbitrary error text.
public struct ObservabilityEvent: Codable, Equatable, Sendable {
    public var requestId: String
    public var operation: ObservabilityOperation
    public var outcome: ObservabilityOutcome
    public var failureStage: ObservabilityFailureStage?
    public var errorCode: ObservabilityErrorCode?
    public var failureClass: ObservabilityFailureClass?
    public var retryability: ObservabilityRetryability?
    public var durationMs: Int?
    public var retryCount: Int?
    public var provider: String?
    public var model: String?
    public var providerStatus: String?
    public var schemaStage: ObservabilitySchemaStage?
    public var validatorFailureType: ObservabilityValidatorFailureType?
    public var tokenUsage: ObservabilityTokenUsage?
    public var cost: ObservabilityCostMetadata?
    public var timestamp: Date
    public var appVersion: String?
    public var gatewayVersion: String?

    public init(
        requestId: String,
        operation: ObservabilityOperation,
        outcome: ObservabilityOutcome,
        failureStage: ObservabilityFailureStage? = nil,
        errorCode: ObservabilityErrorCode? = nil,
        failureClass: ObservabilityFailureClass? = nil,
        retryability: ObservabilityRetryability? = nil,
        durationMs: Int? = nil,
        retryCount: Int? = nil,
        provider: String? = nil,
        model: String? = nil,
        providerStatus: String? = nil,
        schemaStage: ObservabilitySchemaStage? = nil,
        validatorFailureType: ObservabilityValidatorFailureType? = nil,
        tokenUsage: ObservabilityTokenUsage? = nil,
        cost: ObservabilityCostMetadata? = nil,
        timestamp: Date = Date(),
        appVersion: String? = nil,
        gatewayVersion: String? = nil
    ) {
        self.requestId = requestId
        self.operation = operation
        self.outcome = outcome
        self.failureStage = failureStage
        self.errorCode = errorCode
        self.failureClass = failureClass
        self.retryability = retryability
        self.durationMs = durationMs
        self.retryCount = retryCount
        self.provider = provider
        self.model = model
        self.providerStatus = providerStatus
        self.schemaStage = schemaStage
        self.validatorFailureType = validatorFailureType
        self.tokenUsage = tokenUsage?.isEmpty == true ? nil : tokenUsage
        self.cost = cost
        self.timestamp = timestamp
        self.appVersion = appVersion
        self.gatewayVersion = gatewayVersion
    }

    public func encodedJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}

extension ObservabilityOutcome {
    /// ADR-020: optional AI enrichment failure with a successful deterministic Home
    /// is `degraded`, not `failed`.
    public static func homeAIEnrichment(remoteFailed: Bool, homeAvailable: Bool) -> ObservabilityOutcome {
        if !homeAvailable {
            return .failed
        }
        if remoteFailed {
            return .degraded
        }
        return .success
    }
}
