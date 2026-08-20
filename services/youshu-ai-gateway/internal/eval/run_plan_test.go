package eval_test

import (
	"context"
	"strings"
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/config"
	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/eval"
	"github.com/youshu/youshu-ai-gateway/internal/provider"
)

func TestSmokeRunPlanSixCasesTwelveRuns(t *testing.T) {
	plan, err := eval.BuildSmokeV2RunPlan()
	if err != nil {
		t.Fatal(err)
	}
	if plan.ExpectedCaseCount != 6 {
		t.Fatalf("expected 6 cases, got %d", plan.ExpectedCaseCount)
	}
	if plan.ExpectedRunCount != 12 {
		t.Fatalf("expected 12 runs, got %d", plan.ExpectedRunCount)
	}
	if plan.RepeatCount != eval.SmokeV2RepeatCount {
		t.Fatalf("repeat count=%d want %d", plan.RepeatCount, eval.SmokeV2RepeatCount)
	}
}

func TestSmokeRunPlanExactCaseIDs(t *testing.T) {
	plan, err := eval.BuildSmokeV2RunPlan()
	if err != nil {
		t.Fatal(err)
	}
	if !eval.SmokeCaseIDsMatchGolden(plan) {
		t.Fatalf("smoke case IDs mismatch: %v", plan.SelectedCaseIDs)
	}
	want := []string{
		"A01_healthy_cashflow",
		"C03_high_monthly_payment",
		"B04_short_term_negative_balance",
		"C01_no_debt",
		"E05_missing_debt_data",
		"E01_partial_debt_data",
	}
	for i, id := range want {
		if plan.SelectedCaseIDs[i] != id {
			t.Fatalf("case[%d]=%s want %s", i, plan.SelectedCaseIDs[i], id)
		}
	}
}

func TestFullV2RunPlanDerivedFromDataset(t *testing.T) {
	plan, err := eval.BuildFullRunPlan()
	if err != nil {
		t.Fatal(err)
	}
	summary, err := eval.BuildDatasetSummary()
	if err != nil {
		t.Fatal(err)
	}
	if plan.ExpectedCaseCount != summary.DatasetCases {
		t.Fatalf("full case count: got %d want %d", plan.ExpectedCaseCount, summary.DatasetCases)
	}
	if plan.ExpectedRunCount != summary.FullRuns {
		t.Fatalf("full run count: got %d want %d", plan.ExpectedRunCount, summary.FullRuns)
	}
	if plan.Type != eval.RunPlanTypeFull {
		t.Fatalf("plan type=%s", plan.Type)
	}
	if plan.ArtifactPrefix != "full-v2" {
		t.Fatalf("artifact prefix=%s", plan.ArtifactPrefix)
	}
}

func TestPilotRunPlanRegression(t *testing.T) {
	plan, err := eval.BuildPilotRunPlan()
	if err != nil {
		t.Fatal(err)
	}
	summary, err := eval.BuildDatasetSummary()
	if err != nil {
		t.Fatal(err)
	}
	if plan.ExpectedCaseCount != summary.PilotCases {
		t.Fatalf("pilot cases: got %d want %d", plan.ExpectedCaseCount, summary.PilotCases)
	}
	if plan.ExpectedRunCount != summary.PilotRuns {
		t.Fatalf("pilot runs: got %d want %d", plan.ExpectedRunCount, summary.PilotRuns)
	}
}

func TestValidateRunPlanCompletionSmokeAcceptsSixTwelve(t *testing.T) {
	plan, err := eval.BuildSmokeV2RunPlan()
	if err != nil {
		t.Fatal(err)
	}
	report := eval.BuildReport(
		eval.RunMetadata{TotalCases: 6, TotalRuns: 12},
		make([]eval.RunResult, 12),
		eval.ComputeMetrics(make([]eval.RunResult, 12), eval.EvaluationModeExplanationAlignmentV2),
		eval.EvaluationModeExplanationAlignmentV2,
	)
	if err := eval.ValidateRunPlanCompletion(plan, report); err != nil {
		t.Fatalf("expected 6/12 to pass: %v", err)
	}
}

func TestValidateRunPlanCompletionSmokeRejectsSixEleven(t *testing.T) {
	plan, err := eval.BuildSmokeV2RunPlan()
	if err != nil {
		t.Fatal(err)
	}
	report := eval.BuildReport(
		eval.RunMetadata{TotalCases: 6, TotalRuns: 11},
		make([]eval.RunResult, 11),
		eval.ComputeMetrics(make([]eval.RunResult, 11), eval.EvaluationModeExplanationAlignmentV2),
		eval.EvaluationModeExplanationAlignmentV2,
	)
	if err := eval.ValidateRunPlanCompletion(plan, report); err == nil {
		t.Fatal("expected 6/11 to fail validation")
	}
}

func TestValidateRunPlanCompletionSmokeRejectsSevenTwelve(t *testing.T) {
	plan, err := eval.BuildSmokeV2RunPlan()
	if err != nil {
		t.Fatal(err)
	}
	report := eval.BuildReport(
		eval.RunMetadata{TotalCases: 7, TotalRuns: 12},
		make([]eval.RunResult, 12),
		eval.ComputeMetrics(make([]eval.RunResult, 12), eval.EvaluationModeExplanationAlignmentV2),
		eval.EvaluationModeExplanationAlignmentV2,
	)
	if err := eval.ValidateRunPlanCompletion(plan, report); err == nil {
		t.Fatal("expected 7/12 to fail validation")
	}
}

func TestValidateRunPlanCompletionFullRejectsSmokeSizedReport(t *testing.T) {
	plan, err := eval.BuildFullRunPlan()
	if err != nil {
		t.Fatal(err)
	}
	report := eval.BuildReport(
		eval.RunMetadata{TotalCases: 6, TotalRuns: 12},
		make([]eval.RunResult, 12),
		eval.ComputeMetrics(make([]eval.RunResult, 12), eval.EvaluationModeExplanationAlignmentV2),
		eval.EvaluationModeExplanationAlignmentV2,
	)
	if err := eval.ValidateRunPlanCompletion(plan, report); err == nil {
		t.Fatal("full plan must reject 6/12 report")
	}
}

func TestBuildRunPlanFromSmokeEnv(t *testing.T) {
	t.Setenv("YOUSHU_EVAL_SMOKE_V2", "1")
	opts := eval.LoadFilterOptions()
	plan, _, err := eval.BuildRunPlan(opts)
	if err != nil {
		t.Fatal(err)
	}
	if plan.Type != eval.RunPlanTypeSmokeV2 || plan.ExpectedCaseCount != 6 || plan.ExpectedRunCount != 12 {
		t.Fatalf("unexpected smoke plan: %+v", plan)
	}
}

type countingUpstream struct {
	calls int
}

func (c *countingUpstream) DiagnoseMonthlySummary(context.Context, contract.RequestEnvelope) (contract.AssistantAnswerDraftDTO, provider.DecodeDiagnostics, error) {
	c.calls++
	return contract.AssistantAnswerDraftDTO{}, provider.DecodeDiagnostics{}, nil
}

func TestMissingCredentialsZeroHTTPAttempts(t *testing.T) {
	t.Setenv(eval.EnvEvalLive, "1")
	t.Setenv(eval.EnvEvalSmokeV2, "1")
	cfg := config.Config{
		UpstreamAIProvider:          config.UpstreamBailian,
		BailianStructuredOutputMode: config.StructuredOutputJSONSchemaStrict,
	}
	upstream := &countingUpstream{}
	opts := eval.SmokeV2FilterOptions()
	report, err := eval.RunEvaluation(context.Background(), cfg, upstream, opts)
	if err != nil {
		t.Fatal(err)
	}
	if upstream.calls != 0 {
		t.Fatalf("expected 0 HTTP attempts, got %d", upstream.calls)
	}
	if report.RunStatus != eval.RunStatusConfigurationBlocked {
		t.Fatalf("runStatus=%s want %s", report.RunStatus, eval.RunStatusConfigurationBlocked)
	}
	if len(report.Results) != 0 {
		t.Fatalf("expected 0 results, got %d", len(report.Results))
	}
}

func TestCredentialPreflightNeverExposesSecret(t *testing.T) {
	cfg := config.Config{
		UpstreamAIProvider:          config.UpstreamBailian,
		BailianAPIKey:               "sk-live-secret-token",
		BailianBaseURL:              "https://example.test",
		BailianModel:                "qwen3.7-plus",
		BailianStructuredOutputMode: config.StructuredOutputJSONSchemaStrict,
	}
	status := eval.CheckLiveCredentials(cfg)
	if status.APIKey != "configured" {
		t.Fatalf("apiKey status=%s", status.APIKey)
	}
	if status.Configured != true {
		t.Fatal("expected configured=true")
	}
	summary := eval.FormatRunSummary(cfg, eval.EvaluationRunPlan{Type: eval.RunPlanTypeSmokeV2}, eval.LivePreflightResult{
		Credentials: status,
		RunStatus:   eval.RunStatusExecuted,
	})
	if strings.Contains(summary, "sk-live-secret-token") {
		t.Fatal("preflight summary leaked API key")
	}
}

func TestWriteReportSmokeTimestampArtifact(t *testing.T) {
	dir := t.TempDir()
	report := eval.BuildReport(
		eval.RunMetadata{TotalCases: 6, TotalRuns: 12},
		make([]eval.RunResult, 12),
		eval.ComputeMetrics(make([]eval.RunResult, 12), eval.EvaluationModeExplanationAlignmentV2),
		eval.EvaluationModeExplanationAlignmentV2,
	)
	report.RunPlan = eval.EvaluationRunPlan{ArtifactPrefix: "smoke-v2"}
	report.RunStatus = eval.RunStatusExecuted

	writeResult, err := eval.WriteReport(report, dir)
	if err != nil {
		t.Fatal(err)
	}
	if writeResult.LatestPath == "" {
		t.Fatal("latest path missing")
	}
	if writeResult.TimestampedPath == "" {
		t.Fatal("timestamped smoke artifact missing")
	}
}

func TestWriteReportBlockedRunDoesNotWriteTimestampArtifact(t *testing.T) {
	dir := t.TempDir()
	report := eval.BuildReport(
		eval.RunMetadata{TotalCases: 6, TotalRuns: 0},
		nil,
		eval.ComputeMetrics(nil, eval.EvaluationModeExplanationAlignmentV2),
		eval.EvaluationModeExplanationAlignmentV2,
	)
	report.RunPlan = eval.EvaluationRunPlan{ArtifactPrefix: "smoke-v2"}
	report.RunStatus = eval.RunStatusConfigurationBlocked

	writeResult, err := eval.WriteReport(report, dir)
	if err != nil {
		t.Fatal(err)
	}
	if writeResult.TimestampedPath != "" {
		t.Fatal("blocked run should not write timestamp artifact")
	}
}
