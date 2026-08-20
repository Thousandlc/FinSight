package eval_test

import (
	"context"
	"encoding/json"
	"os"
	"strings"
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/config"
	"github.com/youshu/youshu-ai-gateway/internal/eval"
	"github.com/youshu/youshu-ai-gateway/internal/prompt"
	"github.com/youshu/youshu-ai-gateway/internal/provider"
)

// TestLiveE01TargetedDiagnostic runs E01_partial_debt_data × 2 against Bailian.
// Requires YOUSHU_EVAL_LIVE=1 and YOUSHU_EVAL_E01_DIAGNOSTIC=1.
func TestLiveE01TargetedDiagnostic(t *testing.T) {
	if reason := eval.RequireLiveEvalOptIn(); reason != "" {
		t.Skip(reason)
	}
	if !eval.IsE01DiagnosticModeEnv() {
		t.Skip("YOUSHU_EVAL_E01_DIAGNOSTIC=1 required for E01 targeted diagnostic")
	}

	cfg := config.Load()
	cfg.UpstreamAIProvider = config.UpstreamBailian
	opts := eval.LoadFilterOptions()
	if !opts.E01DiagnosticMode || opts.CaseID != eval.E01DiagnosticCaseID || opts.RepeatOverride != 2 {
		t.Fatalf("unexpected filter opts: %+v", opts)
	}

	plan, cases, err := eval.BuildRunPlan(opts)
	if err != nil {
		t.Fatalf("BuildRunPlan: %v", err)
	}
	if plan.Type != eval.RunPlanTypeE01Diagnostic || plan.ExpectedRunCount != 2 {
		t.Fatalf("unexpected plan: %+v", plan)
	}
	if len(cases) != 1 || cases[0].ID != eval.E01DiagnosticCaseID {
		t.Fatalf("unexpected cases: %+v", cases)
	}

	cred := eval.CheckLiveCredentials(cfg)
	if !cred.Configured {
		t.Skipf("blocked: runStatus=%s missing=%v", eval.RunStatusConfigurationBlocked, cred.Missing)
	}
	if err := cfg.ValidateUpstream(); err != nil {
		t.Fatalf("config: %v", err)
	}

	upstream, err := provider.NewUpstream(cfg)
	if err != nil {
		t.Fatalf("upstream: %v", err)
	}
	bailian, ok := upstream.(*provider.BailianProvider)
	if !ok {
		t.Fatalf("expected *BailianProvider, got %T", upstream)
	}

	preflight, err := eval.RunLivePreflight(cfg, plan)
	if err != nil {
		t.Fatalf("RunLivePreflight: %v", err)
	}
	t.Log(eval.FormatRunSummary(cfg, plan, preflight))
	if !preflight.Passed {
		t.Fatalf("preflight failed: %s", preflight.BlockReason)
	}

	report, err := eval.RunEvaluation(context.Background(), cfg, bailian, opts)
	if err != nil {
		t.Fatalf("RunEvaluation: %v", err)
	}
	if report.Metadata.TotalRuns != 2 {
		t.Fatalf("totalRuns=%d want 2", report.Metadata.TotalRuns)
	}

	eval.SetUpstreamModel(&report, cfg.BailianModel)
	writeResult, err := eval.WriteReport(report, eval.DefaultOutputDir)
	if err != nil {
		t.Fatalf("WriteReport: %v", err)
	}

	fp, err := prompt.MonthlySummaryPromptContractFingerprint()
	if err != nil {
		t.Fatalf("prompt fingerprint: %v", err)
	}
	t.Logf("promptVersion=%s promptFingerprint=%s", prompt.MonthlySummaryPromptContractVersion, fp)
	t.Logf("artifact=%s", writeResult.TimestampedPath)
	t.Logf("E01TargetedDiagnosticReadiness=%s", report.E01TargetedReadiness.Verdict)
	t.Logf("E01PostArchitectureReadiness=%s", report.E01PostArchitectureReadiness.Verdict)

	for _, r := range report.Results {
		snap := r.DiagnosticSnapshot
		analysis := eval.ClassifyE01StructuredFailure(snap, r.ExplanationAlignmentPass)
		t.Logf("run=%d transport=http2xx:%t status=%d latencyMs=%d timeout=%t",
			r.RunIndex, r.Transport.HTTP2xxSuccess, r.Transport.HTTPStatus, r.LatencyMs, r.Timeout)
		t.Logf("run=%d pipeline dto=%s schema=%s alignment=%s fact=%s",
			r.RunIndex,
			r.ContractStages.DraftDTODecode,
			r.ContractStages.GatewaySchemaValidation,
			r.ContractStages.ExplanationAlignment,
			r.ContractStages.FactValidation,
		)
		t.Logf("run=%d alignmentCode=%s expectedRisk=%v actualRisk=%v expectedSources=%v actualCited=%v primaryPresent=%t",
			r.RunIndex, snap.AlignmentFailureCode, snap.ExpectedRiskReasons, snap.ActualRiskExplanationReasons,
			snap.ExpectedSignalSourceFactKeys, snap.ActualCitedFactKeys, snap.PrimarySourcePresent)
		t.Logf("run=%d riskExplanations=%s failureType=%s",
			r.RunIndex, formatRiskExplanationSnapshot(snap.RiskExplanations), analysis.FailureType)
		t.Logf("run=%d tokens prompt=%d completion=%d total=%d",
			r.RunIndex, r.PromptTokens, r.CompletionTokens, r.TotalTokens)
	}

	if report.E01PostArchitectureReadiness.Verdict == eval.ReadinessNotAssessed {
		t.Fatal("expected post-architecture readiness verdict")
	}
}

func formatRiskExplanationSnapshot(items []eval.EvalRiskExplanationSnapshot) string {
	data, err := json.Marshal(items)
	if err != nil {
		return "[]"
	}
	return string(data)
}

func TestE01TargetedDiagnosticFilterOptions(t *testing.T) {
	opts := eval.E01TargetedDiagnosticFilterOptions()
	if !opts.E01DiagnosticMode || opts.CaseID != eval.E01DiagnosticCaseID || opts.RepeatOverride != 2 {
		t.Fatalf("unexpected opts: %+v", opts)
	}
	plan, cases, err := eval.BuildRunPlan(opts)
	if err != nil {
		t.Fatal(err)
	}
	if plan.ExpectedRunCount != 2 || plan.ArtifactPrefix != "e01-diagnostic-v2" {
		t.Fatalf("plan=%+v", plan)
	}
	if len(cases) != 1 {
		t.Fatalf("cases=%d", len(cases))
	}
}

func TestE01TargetedDiagnosticGateRequiresExplicitFlag(t *testing.T) {
	t.Setenv(eval.EnvEvalLive, "1")
	t.Setenv(eval.EnvEvalE01Diagnostic, "")
	cfg := config.Config{
		UpstreamAIProvider:          config.UpstreamBailian,
		BailianAPIKey:               "test-key",
		BailianBaseURL:              "https://example.test",
		BailianModel:                "qwen3.7-plus",
		BailianStructuredOutputMode: config.StructuredOutputJSONSchemaStrict,
	}
	plan, _, err := eval.BuildRunPlan(eval.E01TargetedDiagnosticFilterOptions())
	if err != nil {
		t.Fatal(err)
	}
	gate := eval.ResolveLiveRunGate(cfg, plan)
	if gate.Eligible {
		t.Fatal("expected gate blocked without YOUSHU_EVAL_E01_DIAGNOSTIC=1")
	}
}

func TestClassifyE01SignalOmission(t *testing.T) {
	analysis := eval.ClassifyE01StructuredFailure(eval.EvaluationDiagnosticSnapshot{
		AlignmentFailureCode: "riskExplanationCoverageMismatch",
		ExpectedRiskReasons:  []string{"highDebtPaymentToIncome"},
	}, false)
	if analysis.FailureType != eval.E01FailureSignalOmission {
		t.Fatalf("type=%s", analysis.FailureType)
	}
}

func TestClassifyE01CitationMissing(t *testing.T) {
	analysis := eval.ClassifyE01StructuredFailure(eval.EvaluationDiagnosticSnapshot{
		AlignmentFailureCode: "riskExplanation missingPrimarySource",
		ExpectedRiskReasons:  []string{"highDebtPaymentToIncome"},
		ActualRiskExplanationReasons: []string{"highDebtPaymentToIncome"},
		RiskExplanations: []eval.EvalRiskExplanationSnapshot{{
			ReasonCode: "highDebtPaymentToIncome", CitedFactKeys: []string{"availableCash"},
		}},
	}, false)
	if analysis.FailureType != eval.E01FailureCitationMissing {
		t.Fatalf("type=%s", analysis.FailureType)
	}
}

func TestFrozenSmokeArtifactUntouched(t *testing.T) {
	path := eval.DefaultOutputDir + "/smoke-v2-20260817-022459.json"
	if _, err := os.Stat(path); err != nil {
		t.Skip("frozen smoke artifact unavailable")
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(data), "smoke-v2") {
		t.Fatal("unexpected artifact content")
	}
}
