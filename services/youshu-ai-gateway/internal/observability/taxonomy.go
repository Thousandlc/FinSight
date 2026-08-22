package observability

// Production observability taxonomy.
// Distinct from eval-only transport diagnostics (provider/http-5xx, etc.).
const (
	StageClientPreflight          = "clientPreflight"
	StageConsent                  = "consent"
	StageRequestSerialization     = "requestSerialization"
	StageClientTransport          = "clientTransport"
	StageGatewayAuth              = "gatewayAuth"
	StageGatewayRequestValidation = "gatewayRequestValidation"
	StageProviderTransport        = "providerTransport"
	StageProviderHTTP             = "providerHTTP"
	StageProviderStructuredOutput = "providerStructuredOutput"
	StageFactMaterialization      = "factMaterialization"
	StageGatewayResponseEncoding  = "gatewayResponseEncoding"
	StageClientResponseDecode     = "clientResponseDecode"
	StageAssistantValidation      = "assistantValidation"
	StageInsightPersistence       = "insightPersistence"
	StageUnknown                  = "unknown"
)

const (
	CodeCancelled                     = "cancelled"
	CodeTimeout                       = "timeout"
	CodeNetworkUnavailable            = "networkUnavailable"
	CodeTransportFailure              = "transportFailure"
	CodeInvalidRequest                = "invalidRequest"
	CodeSerializationFailure          = "serializationFailure"
	CodeUnauthorized                  = "unauthorized"
	CodeForbidden                     = "forbidden"
	CodeRateLimited                   = "rateLimited"
	CodeGatewayRateLimited            = "gatewayRateLimited"
	CodeProviderRateLimited           = "providerRateLimited"
	CodeProviderUnavailable           = "providerUnavailable"
	CodeProviderTimeout               = "providerTimeout"
	CodeInvalidProviderResponse       = "invalidProviderResponse"
	CodeProviderRejectedRequest       = "providerRejectedRequest"
	CodeUnsupportedSchemaVersion      = "unsupportedSchemaVersion"
	CodeUnsupportedOperation          = "unsupportedOperation"
	CodeStructuredOutputDecodeFailure = "structuredOutputDecodeFailure"
	CodeUnknownFactSource             = "unknownFactSource"
	CodeMaterializationFailure        = "materializationFailure"
	CodeResponseDecodeFailure         = "responseDecodeFailure"
	CodeValidationRejected            = "validationRejected"
	CodePersistenceFailure            = "persistenceFailure"
	CodeConsentRequired               = "consentRequired"
	CodeInternalError                 = "internalError"
	CodeUnknown                       = "unknown"
)

const (
	ClassTransient     = "transient"
	ClassPermanent     = "permanent"
	ClassPolicy        = "policy"
	ClassDataIntegrity = "dataIntegrity"
	ClassSecurity      = "security"
)

const (
	Retryable    = "retryable"
	NotRetryable = "notRetryable"
)

const (
	OutcomeSuccess   = "success"
	OutcomeDegraded  = "degraded"
	OutcomeFailed    = "failed"
	OutcomeCancelled = "cancelled"
)

const (
	OperationMonthlySummary   = "monthlySummary"
	OperationAsk              = "ask"
	OperationInsight          = "insight"
	OperationPurchaseScenario = "purchaseScenario"
	OperationUnknown          = "unknown"
)

const (
	EventAIRequest = "ai_request"
)

const (
	SchemaRequestEnvelope = "requestEnvelope"
	SchemaModelDraft      = "modelDraft"
	SchemaGatewayDraft    = "gatewayDraft"
	SchemaClientDraft     = "clientDraft"
	SchemaUnknown         = "unknown"
)

const (
	ProviderBailian = "bailian"
	ProviderMock    = "mock"
	ProviderUnknown = "unknown"
)
