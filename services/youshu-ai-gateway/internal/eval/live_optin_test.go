package eval

import (
	"context"
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/config"
	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/provider"
)

type recordingDiagnoser struct {
	calls int
}

func (r *recordingDiagnoser) DiagnoseMonthlySummary(
	_ context.Context,
	_ contract.RequestEnvelope,
) (contract.AssistantAnswerDraftDTO, provider.DecodeDiagnostics, error) {
	r.calls++
	return contract.AssistantAnswerDraftDTO{}, provider.DecodeDiagnostics{}, nil
}

func TestRunEvaluationNoHTTPWithoutLiveOptIn(t *testing.T) {
	t.Setenv(EnvEvalLive, "")
	t.Setenv(EnvEvalSmokeV2, "1")

	cfg := config.Config{
		UpstreamAIProvider:          config.UpstreamBailian,
		BailianAPIKey:               "test-key",
		BailianBaseURL:              "https://example.test",
		BailianModel:                "qwen3.7-plus",
		BailianStructuredOutputMode: config.StructuredOutputJSONSchemaStrict,
	}

	rec := &recordingDiagnoser{}
	report, err := RunEvaluation(context.Background(), cfg, rec, SmokeV2FilterOptions())
	if err != nil {
		t.Fatalf("RunEvaluation: %v", err)
	}
	if rec.calls != 0 {
		t.Fatalf("expected 0 provider calls, got %d", rec.calls)
	}
	if report.RunStatus != RunStatusNotRequested {
		t.Fatalf("runStatus=%s want %s", report.RunStatus, RunStatusNotRequested)
	}
}

func TestRunEvaluationConfigurationBlockedWithLiveOptInMissingCreds(t *testing.T) {
	t.Setenv(EnvEvalLive, "1")
	t.Setenv(EnvEvalSmokeV2, "1")

	cfg := config.Config{UpstreamAIProvider: config.UpstreamBailian}
	rec := &recordingDiagnoser{}
	report, err := RunEvaluation(context.Background(), cfg, rec, SmokeV2FilterOptions())
	if err != nil {
		t.Fatalf("RunEvaluation: %v", err)
	}
	if rec.calls != 0 {
		t.Fatalf("expected 0 provider calls, got %d", rec.calls)
	}
	if report.RunStatus != RunStatusConfigurationBlocked {
		t.Fatalf("runStatus=%s want %s", report.RunStatus, RunStatusConfigurationBlocked)
	}
}

func TestResolveLiveRunGateSmokeEligibleWithoutHTTP(t *testing.T) {
	t.Setenv(EnvEvalLive, "1")
	t.Setenv(EnvEvalSmokeV2, "1")

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
	gate := ResolveLiveRunGate(cfg, plan)
	if !gate.Eligible {
		t.Fatalf("expected eligible smoke gate, got status=%s reason=%s", gate.RunStatus, gate.BlockReason)
	}
}

func TestResolveLiveRunGateSmokeRequiresSmokeFlag(t *testing.T) {
	t.Setenv(EnvEvalLive, "1")
	t.Setenv(EnvEvalSmokeV2, "")

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
	gate := ResolveLiveRunGate(cfg, plan)
	if gate.Eligible || gate.RunStatus != RunStatusNotRequested {
		t.Fatalf("gate=%+v", gate)
	}
}

func TestResolveLiveRunGateConnectivityRequiresBothFlags(t *testing.T) {
	t.Setenv(EnvEvalLive, "1")
	t.Setenv(EnvEvalConnectivityProbe, "")

	plan, _, err := BuildRunPlan(ConnectivityProbeFilterOptions())
	if err != nil {
		t.Fatal(err)
	}
	gate := ResolveLiveRunGate(config.Config{UpstreamAIProvider: config.UpstreamBailian, BailianAPIKey: "k", BailianBaseURL: "u", BailianModel: "m", BailianStructuredOutputMode: config.StructuredOutputJSONSchemaStrict}, plan)
	if gate.Eligible {
		t.Fatal("expected connectivity gate blocked without probe flag")
	}
}

func TestResolveLiveRunGateFullRequiresFullFlag(t *testing.T) {
	t.Setenv(EnvEvalLive, "1")
	t.Setenv(EnvEvalFull, "")

	plan, err := BuildFullRunPlan()
	if err != nil {
		t.Fatal(err)
	}
	gate := ResolveLiveRunGate(config.Config{UpstreamAIProvider: config.UpstreamBailian, BailianAPIKey: "k", BailianBaseURL: "u", BailianModel: "m", BailianStructuredOutputMode: config.StructuredOutputJSONSchemaStrict}, plan)
	if gate.Eligible {
		t.Fatal("expected full eval gate blocked without YOUSHU_EVAL_FULL=1")
	}
}

func TestResolveLiveRunGateNotRequestedWithoutLiveFlag(t *testing.T) {
	t.Setenv(EnvEvalLive, "")

	plan, err := BuildSmokeV2RunPlan()
	if err != nil {
		t.Fatal(err)
	}
	gate := ResolveLiveRunGate(config.Config{UpstreamAIProvider: config.UpstreamBailian}, plan)
	if gate.RunStatus != RunStatusNotRequested {
		t.Fatalf("runStatus=%s", gate.RunStatus)
	}
}

func TestEvaluatorFixturesZeroFalsePositives(t *testing.T) {
	result := EvaluateClassifierFixtures()
	if result.EvaluatorFalsePositives != 0 {
		t.Fatalf("evaluatorFalsePositives=%d failures=%v", result.EvaluatorFalsePositives, result.Failures)
	}
}

func TestEvaluationDiagnosticSnapshotContractFields(t *testing.T) {
	c, err := findCaseByID("E01_partial_debt_data")
	if err != nil {
		t.Fatal(err)
	}
	snap := BuildDiagnosticSnapshotFromAssessment(c, c.Envelope.MonthlySummaryFacts)
	if len(snap.ExpectedRiskReasons) != 1 || snap.ExpectedRiskReasons[0] != "highDebtPaymentToIncome" {
		t.Fatalf("expectedRiskReasons=%v", snap.ExpectedRiskReasons)
	}
	if snap.ExpectedPrimarySource != "debtPaymentToIncomePercent" {
		t.Fatalf("expectedPrimarySource=%s", snap.ExpectedPrimarySource)
	}
	if !containsSecretDiagnostic("sk-test-key") {
		t.Fatal("secret helper should detect sk- patterns")
	}
}
