import Foundation

/// Stable classification for one failure. Unknown errors are never auto-retryable.
public struct ObservabilityClassification: Equatable, Sendable {
    public var stage: ObservabilityFailureStage
    public var errorCode: ObservabilityErrorCode
    public var failureClass: ObservabilityFailureClass
    public var retryability: ObservabilityRetryability
    public var validatorFailureType: ObservabilityValidatorFailureType?

    public init(
        stage: ObservabilityFailureStage,
        errorCode: ObservabilityErrorCode,
        failureClass: ObservabilityFailureClass,
        retryability: ObservabilityRetryability,
        validatorFailureType: ObservabilityValidatorFailureType? = nil
    ) {
        self.stage = stage
        self.errorCode = errorCode
        self.failureClass = failureClass
        self.retryability = retryability
        self.validatorFailureType = validatorFailureType
    }

    public static let unclassified = ObservabilityClassification(
        stage: .unknown,
        errorCode: .unknown,
        failureClass: .permanent,
        retryability: .notRetryable
    )
}

public enum ObservabilityErrorMapping: Sendable {
    public static func attributes(for code: ObservabilityErrorCode) -> (
        failureClass: ObservabilityFailureClass,
        retryability: ObservabilityRetryability
    ) {
        switch code {
        case .cancelled:
            return (.policy, .notRetryable)
        case .timeout:
            // iOS maps URL timeouts to providerTimeout and may retry once.
            return (.transient, .retryable)
        case .networkUnavailable, .transportFailure:
            // iOS does not auto-retry networkFailure. Do not advertise retryable.
            return (.transient, .notRetryable)
        case .invalidRequest, .serializationFailure, .unsupportedSchemaVersion, .unsupportedOperation:
            return (.permanent, .notRetryable)
        case .unauthorized, .forbidden:
            return (.security, .notRetryable)
        case .rateLimited, .gatewayRateLimited, .providerRateLimited:
            // Conservative: emitted retryability matches actual path policy.
            // iOS AIGatewayError.rateLimited is not auto-retried; Gateway 429
            // retries are counted separately as retryCount, not this flag.
            return (.transient, .notRetryable)
        case .providerUnavailable, .providerTimeout, .internalError:
            return (.transient, .retryable)
        case .invalidProviderResponse, .structuredOutputDecodeFailure, .unknownFactSource,
             .materializationFailure, .responseDecodeFailure, .validationRejected:
            return (.dataIntegrity, .notRetryable)
        case .providerRejectedRequest, .persistenceFailure, .unknown:
            return (.permanent, .notRetryable)
        case .consentRequired:
            return (.policy, .notRetryable)
        }
    }

    public static func classify(
        code: ObservabilityErrorCode,
        stage: ObservabilityFailureStage,
        validatorFailureType: ObservabilityValidatorFailureType? = nil
    ) -> ObservabilityClassification {
        let attributes = attributes(for: code)
        return ObservabilityClassification(
            stage: stage,
            errorCode: code,
            failureClass: attributes.failureClass,
            retryability: attributes.retryability,
            validatorFailureType: validatorFailureType
        )
    }

    public static func classifyHTTPStatus(_ statusCode: Int) -> ObservabilityClassification {
        switch statusCode {
        case 401:
            return classify(code: .unauthorized, stage: .gatewayAuth)
        case 403:
            return classify(code: .forbidden, stage: .gatewayAuth)
        case 429:
            return classify(code: .rateLimited, stage: .providerHTTP)
        case 408, 504:
            return classify(code: .timeout, stage: .providerHTTP)
        case 500...599:
            return classify(code: .providerUnavailable, stage: .providerHTTP)
        case 400:
            return classify(code: .invalidRequest, stage: .gatewayRequestValidation)
        default:
            return .unclassified
        }
    }

    /// Conservative mapping for untyped errors. Does not copy `localizedDescription`.
    public static func classify(_ error: Error) -> ObservabilityClassification {
        if error is CancellationError {
            return classify(code: .cancelled, stage: .clientPreflight)
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return classify(code: .timeout, stage: .clientTransport)
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
                return classify(code: .networkUnavailable, stage: .clientTransport)
            case .cancelled:
                return classify(code: .cancelled, stage: .clientTransport)
            default:
                return classify(code: .transportFailure, stage: .clientTransport)
            }
        }
        return .unclassified
    }

    public static func parseErrorCode(_ raw: String) -> ObservabilityErrorCode {
        ObservabilityErrorCode(rawValue: raw) ?? .unknown
    }
}

/// Types that expose a privacy-safe classification without copying associated values.
public protocol ObservabilityClassifiable: Error {
    var observabilityClassification: ObservabilityClassification { get }
}

extension Error {
    /// Resolves a privacy-safe classification. Does not copy `localizedDescription`.
    public var observabilityClassification: ObservabilityClassification {
        if let classified = self as? any ObservabilityClassifiable {
            return classified.observabilityClassification
        }
        return ObservabilityErrorMapping.classify(self)
    }
}
