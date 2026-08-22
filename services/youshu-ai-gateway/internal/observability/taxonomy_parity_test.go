package observability_test

import (
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/observability"
)

type taxonomyFixture struct {
	ErrorCodes []struct {
		Code          string `json:"code"`
		FailureClass  string `json:"failureClass"`
		Retryability  string `json:"retryability"`
	} `json:"errorCodes"`
	FailureStages []string `json:"failureStages"`
	Outcomes      []string `json:"outcomes"`
}

func loadTaxonomyFixture(t *testing.T) taxonomyFixture {
	t.Helper()
	_, file, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller failed")
	}
	dir := filepath.Dir(file)
	var fixturePath string
	for i := 0; i < 12; i++ {
		candidate := filepath.Join(dir, "contracts", "observability_taxonomy_defaults.json")
		if _, err := os.Stat(candidate); err == nil {
			fixturePath = candidate
			break
		}
		dir = filepath.Dir(dir)
	}
	if fixturePath == "" {
		t.Fatal("taxonomy fixture not found")
	}
	raw, err := os.ReadFile(fixturePath)
	if err != nil {
		t.Fatal(err)
	}
	var fixture taxonomyFixture
	if err := json.Unmarshal(raw, &fixture); err != nil {
		t.Fatal(err)
	}
	return fixture
}

func TestTaxonomyDefaultsMatchSharedFixture(t *testing.T) {
	fixture := loadTaxonomyFixture(t)
	knownCodes := map[string]struct{}{
		observability.CodeCancelled:                     {},
		observability.CodeTimeout:                       {},
		observability.CodeNetworkUnavailable:            {},
		observability.CodeTransportFailure:              {},
		observability.CodeInvalidRequest:                {},
		observability.CodeSerializationFailure:          {},
		observability.CodeUnauthorized:                  {},
		observability.CodeForbidden:                     {},
		observability.CodeRateLimited:                   {},
		observability.CodeGatewayRateLimited:            {},
		observability.CodeProviderRateLimited:           {},
		observability.CodeProviderUnavailable:           {},
		observability.CodeProviderTimeout:               {},
		observability.CodeInvalidProviderResponse:       {},
		observability.CodeProviderRejectedRequest:       {},
		observability.CodeUnsupportedSchemaVersion:      {},
		observability.CodeUnsupportedOperation:          {},
		observability.CodeStructuredOutputDecodeFailure: {},
		observability.CodeUnknownFactSource:             {},
		observability.CodeMaterializationFailure:        {},
		observability.CodeResponseDecodeFailure:         {},
		observability.CodeValidationRejected:            {},
		observability.CodePersistenceFailure:            {},
		observability.CodeConsentRequired:               {},
		observability.CodeInternalError:                 {},
		observability.CodeUnknown:                       {},
	}
	if len(fixture.ErrorCodes) != len(knownCodes) {
		t.Fatalf("fixture codes=%d go codes=%d", len(fixture.ErrorCodes), len(knownCodes))
	}
	for _, row := range fixture.ErrorCodes {
		if _, ok := knownCodes[row.Code]; !ok {
			t.Fatalf("fixture code missing from Go: %s", row.Code)
		}
		got := observability.Classify(row.Code, observability.StageUnknown)
		if got.FailureClass != row.FailureClass {
			t.Fatalf("%s class=%s want=%s", row.Code, got.FailureClass, row.FailureClass)
		}
		if got.Retryability != row.Retryability {
			t.Fatalf("%s retryability=%s want=%s", row.Code, got.Retryability, row.Retryability)
		}
	}

	wantStages := map[string]struct{}{
		observability.StageClientPreflight:          {},
		observability.StageConsent:                  {},
		observability.StageRequestSerialization:     {},
		observability.StageClientTransport:          {},
		observability.StageGatewayAuth:              {},
		observability.StageGatewayRequestValidation: {},
		observability.StageProviderTransport:        {},
		observability.StageProviderHTTP:             {},
		observability.StageProviderStructuredOutput: {},
		observability.StageFactMaterialization:      {},
		observability.StageGatewayResponseEncoding:  {},
		observability.StageClientResponseDecode:     {},
		observability.StageAssistantValidation:      {},
		observability.StageInsightPersistence:       {},
		observability.StageUnknown:                  {},
	}
	if len(fixture.FailureStages) != len(wantStages) {
		t.Fatalf("fixture stages=%d go stages=%d", len(fixture.FailureStages), len(wantStages))
	}
	for _, stage := range fixture.FailureStages {
		if _, ok := wantStages[stage]; !ok {
			t.Fatalf("fixture stage missing from Go: %s", stage)
		}
	}

	wantOutcomes := map[string]struct{}{
		observability.OutcomeSuccess:   {},
		observability.OutcomeDegraded:  {},
		observability.OutcomeFailed:    {},
		observability.OutcomeCancelled: {},
	}
	if len(fixture.Outcomes) != len(wantOutcomes) {
		t.Fatalf("fixture outcomes=%d", len(fixture.Outcomes))
	}
	for _, outcome := range fixture.Outcomes {
		if _, ok := wantOutcomes[outcome]; !ok {
			t.Fatalf("fixture outcome missing from Go: %s", outcome)
		}
	}
}

func TestNetworkUnavailableAndTransportFailureAreNotRetryable(t *testing.T) {
	net := observability.Classify(observability.CodeNetworkUnavailable, observability.StageClientTransport)
	if net.Retryability != observability.NotRetryable {
		t.Fatalf("networkUnavailable retryability=%s", net.Retryability)
	}
	transport := observability.Classify(observability.CodeTransportFailure, observability.StageProviderTransport)
	if transport.Retryability != observability.NotRetryable {
		t.Fatalf("transportFailure retryability=%s", transport.Retryability)
	}
}
