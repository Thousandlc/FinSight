package eval

import (
	"errors"
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/config"
	"github.com/youshu/youshu-ai-gateway/internal/contract"
)

var errDynamicSchemaBlocked = errors.New("dynamic schema blocked for test")

func TestRunSmokeOfflinePreflightPasses(t *testing.T) {
	plan, err := BuildSmokeV2RunPlan()
	if err != nil {
		t.Fatal(err)
	}
	status, err := RunSmokeOfflinePreflight(plan)
	if err != nil {
		t.Fatal(err)
	}
	if !status.Passed {
		t.Fatalf("offline preflight failed: %s", status.BlockReason)
	}
	if status.GoldenBackedCases != 6 || status.DynamicSchemaOfflinePassed != 6 {
		t.Fatalf("unexpected offline status: %+v", status)
	}
}

func TestRunSmokeOfflinePreflightFailsOnWrongRunCount(t *testing.T) {
	plan := EvaluationRunPlan{
		Type:              RunPlanTypeSmokeV2,
		ExpectedCaseCount: 6,
		ExpectedRunCount:  11,
		SelectedCaseIDs:   append([]string(nil), SmokeGoldenCaseIDs...),
	}
	status, err := RunSmokeOfflinePreflight(plan)
	if err != nil {
		t.Fatal(err)
	}
	if status.Passed {
		t.Fatal("expected preflight failure for 6/11 plan")
	}
}

func TestRunSmokeOfflinePreflightFailsOnLegacyGoldenFallback(t *testing.T) {
	plan := EvaluationRunPlan{
		Type:              RunPlanTypeSmokeV2,
		ExpectedCaseCount: len(SmokeGoldenCaseIDs),
		ExpectedRunCount:  len(SmokeGoldenCaseIDs) * SmokeV2RepeatCount,
		SelectedCaseIDs:   []string{"A01_healthy_cashflow", "legacy_case_x"},
	}
	status, err := RunSmokeOfflinePreflight(plan)
	if err != nil {
		t.Fatal(err)
	}
	if status.Passed {
		t.Fatal("expected golden case ID mismatch to fail")
	}
}

func TestRunSmokeOfflinePreflightFailsOnDynamicSchemaHook(t *testing.T) {
	old := validateDynamicSchemaOfflineFn
	t.Cleanup(func() { validateDynamicSchemaOfflineFn = old })
	validateDynamicSchemaOfflineFn = func(EvaluationCase, contract.FinancialRiskAssessmentDTO) error {
		return errDynamicSchemaBlocked
	}

	plan, err := BuildSmokeV2RunPlan()
	if err != nil {
		t.Fatal(err)
	}
	status, err := RunSmokeOfflinePreflight(plan)
	if err != nil {
		t.Fatal(err)
	}
	if status.Passed {
		t.Fatal("expected dynamic schema failure")
	}
}

func TestRunSmokeOfflinePreflightFailsOnEvaluatorFP(t *testing.T) {
	old := evaluateClassifierFixturesFn
	t.Cleanup(func() { evaluateClassifierFixturesFn = old })
	evaluateClassifierFixturesFn = func() ClassifierFixtureResult {
		return ClassifierFixtureResult{EvaluatorFalsePositives: 1}
	}

	plan, err := BuildSmokeV2RunPlan()
	if err != nil {
		t.Fatal(err)
	}
	status, err := RunSmokeOfflinePreflight(plan)
	if err != nil {
		t.Fatal(err)
	}
	if status.Passed {
		t.Fatal("expected evaluator FP preflight failure")
	}
}

func TestRunFullOfflinePreflightPasses(t *testing.T) {
	plan, err := BuildFullRunPlan()
	if err != nil {
		t.Fatal(err)
	}
	status, err := RunFullOfflinePreflight(plan)
	if err != nil {
		t.Fatal(err)
	}
	if !status.Passed {
		t.Fatalf("full offline preflight failed: %s", status.BlockReason)
	}
	if status.GoldenCoverage != 29 || status.PlannedRuns != 37 {
		t.Fatalf("unexpected status: %+v", status)
	}
}

func TestRunFullOfflinePreflightFailsOnWrongRunCount(t *testing.T) {
	plan := EvaluationRunPlan{
		Type:              RunPlanTypeFull,
		ExpectedCaseCount: 29,
		ExpectedRunCount:  36,
	}
	status, err := RunFullOfflinePreflight(plan)
	if err != nil {
		t.Fatal(err)
	}
	if status.Passed {
		t.Fatal("expected failure for 36 runs")
	}
}

func TestRunLivePreflightFullEvalSchemaFailureZeroHTTPPath(t *testing.T) {
	old := validateDynamicSchemaOfflineFn
	t.Cleanup(func() { validateDynamicSchemaOfflineFn = old })
	validateDynamicSchemaOfflineFn = func(EvaluationCase, contract.FinancialRiskAssessmentDTO) error {
		return errDynamicSchemaBlocked
	}

	plan, err := BuildFullRunPlan()
	if err != nil {
		t.Fatal(err)
	}
	cfg := config.Config{
		UpstreamAIProvider:          config.UpstreamBailian,
		BailianAPIKey:               "test-key",
		BailianBaseURL:              "https://example.test",
		BailianModel:                "qwen3.7-plus",
		BailianStructuredOutputMode: config.StructuredOutputJSONSchemaStrict,
	}
	t.Setenv(EnvEvalLive, "1")
	t.Setenv(EnvEvalFull, "1")
	result, err := RunLivePreflight(cfg, plan)
	if err != nil {
		t.Fatal(err)
	}
	if result.Passed {
		t.Fatal("expected preflight failure before HTTP")
	}
	if result.RunStatus != RunStatusPreflightFailed {
		t.Fatalf("runStatus=%s", result.RunStatus)
	}
}

func TestRunLivePreflightBlocksMissingCredentials(t *testing.T) {
	t.Setenv(EnvEvalLive, "1")
	t.Setenv(EnvEvalSmokeV2, "1")
	plan, err := BuildSmokeV2RunPlan()
	if err != nil {
		t.Fatal(err)
	}
	result, err := RunLivePreflight(config.Config{UpstreamAIProvider: config.UpstreamBailian}, plan)
	if err != nil {
		t.Fatal(err)
	}
	if result.Passed {
		t.Fatal("expected blocked preflight")
	}
	if result.RunStatus != RunStatusConfigurationBlocked {
		t.Fatalf("runStatus=%s", result.RunStatus)
	}
	if result.Credentials.APIKey != "missing" {
		t.Fatalf("apiKey status=%s", result.Credentials.APIKey)
	}
}

func TestBuildLiveExecutionReadinessSeparatesOfflineAndCredentials(t *testing.T) {
	readiness, err := BuildLiveExecutionReadiness(config.Config{UpstreamAIProvider: config.UpstreamBailian})
	if err != nil {
		t.Fatal(err)
	}
	if !readiness.OfflineReadyForLiveSmoke {
		t.Fatal("expected offline readiness true")
	}
	if readiness.LiveConfigurationReady {
		t.Fatal("expected live configuration false without secrets")
	}
	if readiness.ReadyForLiveExecution {
		t.Fatal("readyForLiveExecution must require credentials")
	}
}

func TestRunLivePreflightDynamicSchemaFailureZeroHTTPPath(t *testing.T) {
	old := validateDynamicSchemaOfflineFn
	t.Cleanup(func() { validateDynamicSchemaOfflineFn = old })
	validateDynamicSchemaOfflineFn = func(EvaluationCase, contract.FinancialRiskAssessmentDTO) error {
		return errDynamicSchemaBlocked
	}

	plan, err := BuildSmokeV2RunPlan()
	if err != nil {
		t.Fatal(err)
	}
	cfg := config.Config{
		UpstreamAIProvider:          config.UpstreamBailian,
		BailianAPIKey:               "test-key",
		BailianBaseURL:              "https://example.test",
		BailianModel:                "qwen3.7-plus",
		BailianStructuredOutputMode: config.StructuredOutputJSONSchemaStrict,
	}
	t.Setenv(EnvEvalLive, "1")
	t.Setenv(EnvEvalSmokeV2, "1")
	result, err := RunLivePreflight(cfg, plan)
	if err != nil {
		t.Fatal(err)
	}
	if result.Passed {
		t.Fatal("expected preflight failure before HTTP")
	}
	if result.RunStatus != RunStatusPreflightFailed {
		t.Fatalf("runStatus=%s", result.RunStatus)
	}
}
