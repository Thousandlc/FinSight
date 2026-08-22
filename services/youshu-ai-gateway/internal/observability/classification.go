package observability

// Classification is the stable production failure mapping.
// Unknown/unclassified errors default to notRetryable.
type Classification struct {
	Stage                string
	ErrorCode            string
	FailureClass         string
	Retryability         string
	ValidatorFailureType string
}

func Classify(code, stage string) Classification {
	class, retry := attributes(code)
	if stage == "" {
		stage = StageUnknown
	}
	if code == "" {
		code = CodeUnknown
	}
	return Classification{
		Stage:        stage,
		ErrorCode:    code,
		FailureClass: class,
		Retryability: retry,
	}
}

func ClassifyHTTP(status int) Classification {
	switch status {
	case 401:
		return Classify(CodeUnauthorized, StageGatewayAuth)
	case 403:
		return Classify(CodeForbidden, StageGatewayAuth)
	case 429:
		return Classify(CodeRateLimited, StageProviderHTTP)
	case 408, 504:
		return Classify(CodeTimeout, StageProviderHTTP)
	case 400:
		return Classify(CodeInvalidRequest, StageGatewayRequestValidation)
	default:
		if status >= 500 && status <= 599 {
			return Classify(CodeProviderUnavailable, StageProviderHTTP)
		}
		return Classify(CodeUnknown, StageUnknown)
	}
}

func InferFromHTTPStatus(status int) Classification {
	switch status {
	case 401:
		return Classify(CodeUnauthorized, StageGatewayAuth)
	case 403:
		return Classify(CodeForbidden, StageGatewayAuth)
	case 429:
		return Classify(CodeGatewayRateLimited, StageGatewayRequestValidation)
	case 400, 405:
		return Classify(CodeInvalidRequest, StageGatewayRequestValidation)
	case 408, 504:
		return Classify(CodeProviderTimeout, StageProviderHTTP)
	case 503:
		return Classify(CodeProviderUnavailable, StageProviderHTTP)
	case 502:
		return Classify(CodeInvalidProviderResponse, StageProviderStructuredOutput)
	default:
		if status >= 500 && status <= 599 {
			return Classify(CodeInternalError, StageUnknown)
		}
		return Classify(CodeUnknown, StageUnknown)
	}
}

func HomeAIEnrichmentOutcome(remoteFailed, homeAvailable bool) string {
	if !homeAvailable {
		return OutcomeFailed
	}
	if remoteFailed {
		return OutcomeDegraded
	}
	return OutcomeSuccess
}

func attributes(code string) (failureClass, retryability string) {
	switch code {
	case CodeCancelled:
		return ClassPolicy, NotRetryable
	case CodeTimeout:
		// iOS maps URL timeouts to providerTimeout and may retry once.
		return ClassTransient, Retryable
	case CodeNetworkUnavailable, CodeTransportFailure:
		// iOS does not auto-retry networkFailure. Gateway counts internal
		// transport retries via retryCount, not this flag.
		return ClassTransient, NotRetryable
	case CodeInvalidRequest, CodeSerializationFailure, CodeUnsupportedSchemaVersion, CodeUnsupportedOperation:
		return ClassPermanent, NotRetryable
	case CodeUnauthorized, CodeForbidden:
		return ClassSecurity, NotRetryable
	case CodeRateLimited, CodeGatewayRateLimited, CodeProviderRateLimited:
		// Conservative: these codes are not auto-retried on the emitting path.
		// Gateway may already have exhausted provider 429 retries (see retryCount).
		// iOS AIGatewayError.rateLimited.isRetryable is false. Do not claim retryable
		// merely because a rate-limit class is theoretically transient.
		return ClassTransient, NotRetryable
	case CodeProviderUnavailable, CodeProviderTimeout, CodeInternalError:
		return ClassTransient, Retryable
	case CodeInvalidProviderResponse, CodeStructuredOutputDecodeFailure, CodeUnknownFactSource,
		CodeMaterializationFailure, CodeResponseDecodeFailure, CodeValidationRejected:
		return ClassDataIntegrity, NotRetryable
	case CodeConsentRequired:
		return ClassPolicy, NotRetryable
	case CodeProviderRejectedRequest, CodePersistenceFailure:
		return ClassPermanent, NotRetryable
	default:
		return ClassPermanent, NotRetryable
	}
}
