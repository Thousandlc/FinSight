import Foundation
import YoushuDomain
import YoushuFoundation

extension AIGatewayError: ObservabilityClassifiable {
    public var observabilityClassification: ObservabilityClassification {
        let mapped: (ObservabilityErrorCode, ObservabilityFailureStage) = switch self {
        case .notConfigured:
            (.internalError, .clientPreflight)
        case .invalidRequest:
            (.invalidRequest, .unknown)
        case .unauthorized:
            (.unauthorized, .unknown)
        case .rateLimited:
            (.rateLimited, .unknown)
        case .gatewayRateLimited:
            (.gatewayRateLimited, .unknown)
        case .providerRateLimited:
            (.providerRateLimited, .unknown)
        case .providerUnavailable:
            (.providerUnavailable, .unknown)
        case .providerTimeout:
            (.providerTimeout, .unknown)
        case .invalidProviderResponse:
            // iOS decoded a Gateway error envelope; it did not observe Gateway-internal stages.
            (.invalidProviderResponse, .unknown)
        case .unsupportedSchemaVersion:
            (.unsupportedSchemaVersion, .clientResponseDecode)
        case .unsupportedOperation:
            (.unsupportedOperation, .unknown)
        case .internalError:
            (.internalError, .unknown)
        case .networkFailure:
            (.transportFailure, .clientTransport)
        case .decodingFailed:
            (.responseDecodeFailure, .clientResponseDecode)
        case .requestIdMismatch:
            (.responseDecodeFailure, .clientResponseDecode)
        }
        var classified = ObservabilityErrorMapping.classify(code: mapped.0, stage: mapped.1)
        classified.retryability = isRetryable ? .retryable : .notRetryable
        return classified
    }

    public static func mapGatewayErrorCode(_ code: String, retryAfter: Int?) -> AIGatewayError {
        switch code {
        case "invalidRequest":
            return .invalidRequest
        case "unauthorized":
            return .unauthorized
        case "forbidden":
            return .unauthorized
        case "rateLimited":
            return .rateLimited(retryAfterSeconds: retryAfter)
        case "gatewayRateLimited":
            return .gatewayRateLimited(retryAfterSeconds: retryAfter)
        case "providerRateLimited":
            return .providerRateLimited(retryAfterSeconds: retryAfter)
        case "providerUnavailable":
            return .providerUnavailable
        case "providerTimeout":
            return .providerTimeout
        case "invalidProviderResponse",
             "providerRejectedRequest",
             "structuredOutputDecodeFailure",
             "unknownFactSource",
             "materializationFailure":
            return .invalidProviderResponse
        case "unsupportedSchemaVersion":
            return .unsupportedSchemaVersion
        case "unsupportedOperation":
            return .unsupportedOperation
        case "internalError":
            return .internalError
        default:
            // Unknown envelope codes must not become retryable internalError.
            return .invalidProviderResponse
        }
    }
}
