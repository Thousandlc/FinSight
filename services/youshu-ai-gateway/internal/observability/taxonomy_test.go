package observability_test

import (
	"encoding/json"
	"reflect"
	"strings"
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/observability"
)

func TestClassifyRepresentativeFailures(t *testing.T) {
	timeout := observability.Classify(observability.CodeTimeout, observability.StageClientTransport)
	if timeout.ErrorCode != observability.CodeTimeout || timeout.Retryability != observability.Retryable {
		t.Fatalf("timeout=%+v", timeout)
	}

	auth := observability.ClassifyHTTP(401)
	if auth.Stage != observability.StageGatewayAuth || auth.FailureClass != observability.ClassSecurity {
		t.Fatalf("401=%+v", auth)
	}
	forbidden := observability.ClassifyHTTP(403)
	if forbidden.ErrorCode != observability.CodeForbidden || forbidden.Retryability != observability.NotRetryable {
		t.Fatalf("403=%+v", forbidden)
	}

	limited := observability.ClassifyHTTP(429)
	if limited.ErrorCode != observability.CodeRateLimited || limited.Retryability != observability.NotRetryable {
		t.Fatalf("429=%+v", limited)
	}

	unavailable := observability.ClassifyHTTP(503)
	if unavailable.ErrorCode != observability.CodeProviderUnavailable {
		t.Fatalf("503=%+v", unavailable)
	}

	structured := observability.Classify(observability.CodeStructuredOutputDecodeFailure, observability.StageProviderStructuredOutput)
	materialized := observability.Classify(observability.CodeMaterializationFailure, observability.StageFactMaterialization)
	unknownFact := observability.Classify(observability.CodeUnknownFactSource, observability.StageFactMaterialization)
	validation := observability.Classify(observability.CodeValidationRejected, observability.StageAssistantValidation)
	if structured.Stage == materialized.Stage || structured.Stage == validation.Stage {
		t.Fatal("trust-boundary stages collapsed")
	}
	if unknownFact.Stage != observability.StageFactMaterialization {
		t.Fatalf("unknown fact source stage=%s", unknownFact.Stage)
	}

	decode := observability.Classify(observability.CodeResponseDecodeFailure, observability.StageClientResponseDecode)
	if decode.FailureClass != observability.ClassDataIntegrity {
		t.Fatalf("decode=%+v", decode)
	}

	persist := observability.Classify(observability.CodePersistenceFailure, observability.StageInsightPersistence)
	if persist.Retryability != observability.NotRetryable {
		t.Fatalf("persist=%+v", persist)
	}

	cancelled := observability.Classify(observability.CodeCancelled, observability.StageClientPreflight)
	if cancelled.Retryability != observability.NotRetryable {
		t.Fatalf("cancelled=%+v", cancelled)
	}

	unknown := observability.Classify("", "")
	if unknown.ErrorCode != observability.CodeUnknown || unknown.Retryability != observability.NotRetryable {
		t.Fatalf("unknown=%+v", unknown)
	}
}

func TestRateLimitRetryabilityFollowUp(t *testing.T) {
	for _, code := range []string{
		observability.CodeRateLimited,
		observability.CodeGatewayRateLimited,
		observability.CodeProviderRateLimited,
	} {
		got := observability.Classify(code, observability.StageProviderHTTP)
		if got.Retryability != observability.NotRetryable {
			t.Fatalf("%s retryability=%s", code, got.Retryability)
		}
		if got.FailureClass != observability.ClassTransient {
			t.Fatalf("%s class=%s", code, got.FailureClass)
		}
	}
	timeout := observability.Classify(observability.CodeProviderTimeout, observability.StageProviderTransport)
	if timeout.Retryability != observability.Retryable {
		t.Fatalf("providerTimeout retryability=%s", timeout.Retryability)
	}
	unavailable := observability.Classify(observability.CodeProviderUnavailable, observability.StageProviderHTTP)
	if unavailable.Retryability != observability.Retryable {
		t.Fatalf("providerUnavailable retryability=%s", unavailable.Retryability)
	}
}

func TestExistingGatewayCodesRemainCanonical(t *testing.T) {
	if observability.CodeInvalidRequest != contract.ErrInvalidRequest {
		t.Fatalf("invalidRequest drifted: %s vs %s", observability.CodeInvalidRequest, contract.ErrInvalidRequest)
	}
	if observability.CodeProviderTimeout != contract.ErrProviderTimeout {
		t.Fatal("providerTimeout drifted")
	}
	if observability.CodeInvalidProviderResponse != contract.ErrInvalidProviderResponse {
		t.Fatal("invalidProviderResponse drifted")
	}
}

func TestOutcomeSemantics(t *testing.T) {
	if observability.HomeAIEnrichmentOutcome(false, true) != observability.OutcomeSuccess {
		t.Fatal("expected success")
	}
	if observability.HomeAIEnrichmentOutcome(true, true) != observability.OutcomeDegraded {
		t.Fatal("expected degraded")
	}
	if observability.HomeAIEnrichmentOutcome(true, false) != observability.OutcomeFailed {
		t.Fatal("expected failed")
	}
}

func TestEntryJSONOmitsSensitiveFields(t *testing.T) {
	entry := observability.Entry{
		RequestID:            "11111111-1111-1111-1111-111111111111",
		Operation:            observability.OperationMonthlySummary,
		Outcome:              observability.OutcomeDegraded,
		FailureStage:         observability.StageAssistantValidation,
		ErrorCode:            observability.CodeValidationRejected,
		FailureClass:         observability.ClassDataIntegrity,
		Retryability:         observability.NotRetryable,
		ValidatorFailureType: "inventedAmount",
		PromptTokens:         observability.Int(10),
		CompletionTokens:     observability.Int(4),
		TotalTokens:          observability.Int(14),
	}
	payload, err := json.Marshal(entry)
	if err != nil {
		t.Fatal(err)
	}
	var decoded map[string]any
	if err := json.Unmarshal(payload, &decoded); err != nil {
		t.Fatal(err)
	}
	forbidden := []string{
		"rawError", "errorDescription", "responseBody", "requestBody",
		"prompt", "question", "financialContext", "factPack",
		"merchant", "note", "imageData", "authorizationHeader",
		"authorization", "apiKey", "token", "userId", "sourceIds",
		"cost", "costAmount",
	}
	for _, key := range forbidden {
		if _, ok := decoded[key]; ok {
			t.Fatalf("forbidden key present: %s", key)
		}
	}
	text := string(payload)
	if strings.Contains(text, "Bearer ") || strings.Contains(text, "sk-") {
		t.Fatalf("secret leaked: %s", text)
	}

	typ := reflect.TypeOf(observability.Entry{})
	for i := 0; i < typ.NumField(); i++ {
		tag := typ.Field(i).Tag.Get("json")
		name, _, _ := strings.Cut(tag, ",")
		for _, key := range forbidden {
			if name == key {
				t.Fatalf("Entry defines forbidden json field %s", name)
			}
		}
	}
}

func TestMissingTokenUsageAndAbsentCost(t *testing.T) {
	entry := observability.Entry{
		RequestID: "req-1",
		Outcome:   observability.OutcomeSuccess,
	}
	payload, err := json.Marshal(entry)
	if err != nil {
		t.Fatal(err)
	}
	var decoded map[string]any
	if err := json.Unmarshal(payload, &decoded); err != nil {
		t.Fatal(err)
	}
	if _, ok := decoded["promptTokens"]; ok {
		t.Fatal("missing usage should omit promptTokens")
	}
	if _, ok := decoded["costSource"]; ok {
		t.Fatal("cost must stay absent without a trustworthy source")
	}
}

func TestZeroTokenUsageIsEmitted(t *testing.T) {
	zero := 0
	entry := observability.Entry{
		Event:        observability.EventAIRequest,
		PromptTokens: &zero,
	}
	payload, err := json.Marshal(entry)
	if err != nil {
		t.Fatal(err)
	}
	var decoded map[string]any
	if err := json.Unmarshal(payload, &decoded); err != nil {
		t.Fatal(err)
	}
	v, ok := decoded["promptTokens"]
	if !ok {
		t.Fatal("zero tokens must not be omitted")
	}
	if v.(float64) != 0 {
		t.Fatalf("promptTokens=%v", v)
	}
}
