import Foundation
import YoushuFoundation

extension AssistantValidationError: ObservabilityClassifiable {
    /// Allowlisted telemetry kind. Associated strings are never copied into events.
    public var observabilityFailureType: ObservabilityValidatorFailureType {
        switch self {
        case .emptyBody: return .emptyBody
        case .emptyTitle: return .emptyTitle
        case .emptyAnswer: return .emptyAnswer
        case .missingDisclaimer: return .missingDisclaimer
        case .citedUnknownFact: return .citedUnknownFact
        case .inventedAmount: return .inventedAmount
        case .dataInsufficient: return .dataInsufficient
        case .cannotAnswer: return .cannotAnswer
        case .invalidKeyFactSource: return .invalidKeyFactSource
        case .invalidKeyFactValue: return .invalidKeyFactValue
        case .invalidWarningSource: return .invalidWarningSource
        case .invalidActionDestination: return .invalidActionDestination
        case .invalidReference: return .invalidReference
        case .forbiddenIdentifier: return .forbiddenIdentifier
        }
    }

    public var observabilityClassification: ObservabilityClassification {
        ObservabilityErrorMapping.classify(
            code: .validationRejected,
            stage: .assistantValidation,
            validatorFailureType: observabilityFailureType
        )
    }
}

extension PrivacyError: ObservabilityClassifiable {
    public var observabilityClassification: ObservabilityClassification {
        switch self {
        case .consentRequired:
            return ObservabilityErrorMapping.classify(code: .consentRequired, stage: .consent)
        default:
            return .unclassified
        }
    }
}
