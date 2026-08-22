import Foundation

/// Canonical AI/Gateway failure stage. Trust-boundary stages must stay distinct:
/// `providerStructuredOutput` ≠ `factMaterialization` ≠ `assistantValidation`.
public enum ObservabilityFailureStage: String, Codable, Sendable, CaseIterable {
    case clientPreflight
    case consent
    case requestSerialization
    case clientTransport
    case gatewayAuth
    case gatewayRequestValidation
    case providerTransport
    case providerHTTP
    case providerStructuredOutput
    case factMaterialization
    case gatewayResponseEncoding
    case clientResponseDecode
    case assistantValidation
    case insightPersistence
    case unknown
}

/// Compact stable production error codes.
/// Existing Gateway/iOS codes are preserved; new codes are additive.
public enum ObservabilityErrorCode: String, Codable, Sendable, CaseIterable {
    case cancelled
    case timeout
    case networkUnavailable
    case transportFailure
    case invalidRequest
    case serializationFailure
    case unauthorized
    case forbidden
    case rateLimited
    case gatewayRateLimited
    case providerRateLimited
    case providerUnavailable
    case providerTimeout
    case invalidProviderResponse
    case providerRejectedRequest
    case unsupportedSchemaVersion
    case unsupportedOperation
    case structuredOutputDecodeFailure
    case unknownFactSource
    case materializationFailure
    case responseDecodeFailure
    case validationRejected
    case persistenceFailure
    case consentRequired
    case internalError
    case unknown
}

public enum ObservabilityFailureClass: String, Codable, Sendable, CaseIterable {
    case transient
    case permanent
    case policy
    case dataIntegrity
    case security
}

public enum ObservabilityRetryability: String, Codable, Sendable, CaseIterable {
    case retryable
    case notRetryable
}

/// Final user-visible operation outcome. Distinct from whether an internal stage failed.
public enum ObservabilityOutcome: String, Codable, Sendable, CaseIterable {
    case success
    case degraded
    case failed
    case cancelled
}

/// Allowlisted AI operations. Matches existing `GatewayOperation` raw values.
public enum ObservabilityOperation: String, Codable, Sendable, CaseIterable {
    case monthlySummary
    case ask
    case insight
    case purchaseScenario
    case unknown
}

/// Allowlisted Validator failure kinds. Associated validator strings never enter telemetry.
public enum ObservabilityValidatorFailureType: String, Codable, Sendable, CaseIterable {
    case emptyBody
    case emptyTitle
    case emptyAnswer
    case missingDisclaimer
    case citedUnknownFact
    case inventedAmount
    case dataInsufficient
    case cannotAnswer
    case invalidKeyFactSource
    case invalidKeyFactValue
    case invalidWarningSource
    case invalidActionDestination
    case invalidReference
    case forbiddenIdentifier
}

public enum ObservabilitySchemaStage: String, Codable, Sendable, CaseIterable {
    case requestEnvelope
    case modelDraft
    case gatewayDraft
    case clientDraft
    case unknown
}
