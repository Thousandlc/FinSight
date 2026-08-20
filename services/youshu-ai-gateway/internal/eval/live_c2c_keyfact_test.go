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

// TestLiveC2CKeyFactTargeted runs C01/C04/E01 × 2 against Bailian for post-C2B keyFact verification.
// Requires YOUSHU_EVAL_LIVE=1 and YOUSHU_EVAL_C2C_TARGETED=1.
func TestLiveC2CKeyFactTargeted(t *testing.T) {
	if reason := eval.RequireLiveEvalOptIn(); reason != "" {
		t.Skip(reason)
	}
	if !eval.IsC2CTargetedModeEnv() {
		t.Skip("YOUSHU_EVAL_C2C_TARGETED=1 required for C2C targeted verification")
	}

	cfg := config.Load()
	cfg.UpstreamAIProvider = config.UpstreamBailian
	opts := eval.LoadFilterOptions()
	if !opts.C2CTargetedMode {
		t.Fatalf("unexpected filter opts: %+v", opts)
	}

	plan, cases, err := eval.BuildRunPlan(opts)
	if err != nil {
		t.Fatalf("BuildRunPlan: %v", err)
	}
	if plan.Type != eval.RunPlanTypeC2CTargeted || plan.ExpectedRunCount != 6 {
		t.Fatalf("unexpected plan: %+v", plan)
	}
	if len(cases) != 3 {
		t.Fatalf("unexpected cases: %d", len(cases))
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

	report, err := eval.RunC2CTargetedEvaluation(context.Background(), cfg, bailian)
	if err != nil {
		t.Fatalf("RunC2CTargetedEvaluation: %v", err)
	}
	if report.RunStatus != eval.RunStatusExecuted {
		t.Fatalf("runStatus=%s", report.RunStatus)
	}

	eval.SetUpstreamModel(&report, cfg.BailianModel)
	writeResult, err := eval.WriteReport(report, eval.DefaultOutputDir)
	if err != nil {
		t.Fatalf("WriteReport: %v", err)
	}

	identity := report.Metadata.ContractIdentity
	t.Logf("promptVersion=%s promptFingerprint=%s", identity.PromptVersion, identity.PromptFingerprint)
	t.Logf("modelSchemaContractMarker=%s modelSchemaFingerprint=%s", identity.ModelSchemaContractMarker, identity.ModelSchemaFingerprint)
	t.Logf("artifact=%s", writeResult.TimestampedPath)
	t.Logf("C2CTargetedReadiness=%s", report.C2CTargetedReadiness.Verdict)

	readiness := report.C2CTargetedReadiness
	t.Logf("plannedRuns=%d actualAttempts=%d assessedSamples=%d e2e=%d/%d",
		readiness.PlannedRuns, readiness.ActualAttempts, readiness.AssessedSamples,
		readiness.EndToEndPassCount, readiness.PlannedRuns)

	for _, r := range report.Results {
		snap := r.DiagnosticSnapshot
		t.Logf("case=%s run=%d http2xx=%t latencyMs=%d assessed=%t e2e=%t",
			r.CaseID, r.RunIndex, r.Transport.HTTP2xxSuccess, r.LatencyMs, r.ModelResponseAssessed, r.EndToEndPass)
		t.Logf("  dto=%s schema=%s fact=%s selection=%t materialization=%t parity=%t",
			r.ContractStages.DraftDTODecode,
			r.ContractStages.GatewaySchemaValidation,
			r.ContractStages.FactValidation,
			snap.KeyFactSelectionPass,
			snap.KeyFactMaterializationPass,
			snap.KeyFactCanonicalParityPass,
		)
		t.Logf("  selected=%v materialized=%s invalidKeyFactSource=%d",
			snap.ModelSelectedKeyFactSources,
			formatMaterializedKeyFacts(snap.MaterializedKeyFacts),
			r.InvalidKeyFactSource,
		)
		if r.CaseID == eval.C2CCaseC01 {
			if containsString(snap.AllowedFactKeys, "monthlyDebtPayment") &&
				containsString(snap.AllowedKeyFactKeys, "monthlyDebtPayment") {
				t.Errorf("C01 AllowedKeyFactKeys must exclude monthlyDebtPayment")
			}
		}
	}

	if readiness.Verdict != eval.ReadinessPass {
		t.Errorf("C2C verdict=%s want PASS", readiness.Verdict)
	}
	if readiness.AssessedSamples < 6 {
		t.Errorf("assessedSamples=%d want >=6", readiness.AssessedSamples)
	}
}

func TestC2CTargetedFilterOptions(t *testing.T) {
	opts := eval.C2CTargetedFilterOptions()
	if !opts.C2CTargetedMode || opts.RepeatOverride != 2 {
		t.Fatalf("unexpected opts: %+v", opts)
	}
	plan, cases, err := eval.BuildRunPlan(opts)
	if err != nil {
		t.Fatal(err)
	}
	if plan.Type != eval.RunPlanTypeC2CTargeted || plan.ExpectedRunCount != 6 {
		t.Fatalf("plan=%+v", plan)
	}
	if len(cases) != 3 {
		t.Fatalf("cases=%d", len(cases))
	}
	want := []string{eval.C2CCaseC01, eval.C2CCaseC04, eval.C2CCaseE01}
	for i, id := range want {
		if cases[i].ID != id {
			t.Fatalf("case[%d]=%s want %s", i, cases[i].ID, id)
		}
		if cases[i].Repeats != 2 {
			t.Fatalf("%s repeats=%d want 2", cases[i].ID, cases[i].Repeats)
		}
	}
}

func TestC2CTargetedGateRequiresExplicitFlag(t *testing.T) {
	t.Setenv(eval.EnvEvalLive, "1")
	t.Setenv(eval.EnvEvalC2CTargeted, "")
	cfg := config.Config{
		UpstreamAIProvider:          config.UpstreamBailian,
		BailianAPIKey:               "test-key",
		BailianBaseURL:              "https://example.test",
		BailianModel:                "qwen3.7-plus",
		BailianStructuredOutputMode: config.StructuredOutputJSONSchemaStrict,
	}
	plan, err := eval.BuildC2CTargetedRunPlan()
	if err != nil {
		t.Fatal(err)
	}
	gate := eval.ResolveLiveRunGate(cfg, plan)
	if gate.Eligible {
		t.Fatal("expected gate blocked without YOUSHU_EVAL_C2C_TARGETED=1")
	}
}

func TestLoadFrozenContractIdentity(t *testing.T) {
	identity := eval.LoadFrozenContractIdentity()
	if identity.PromptVersion != prompt.MonthlySummaryPromptContractVersion {
		t.Fatalf("promptVersion=%s", identity.PromptVersion)
	}
	if identity.ModelSchemaContractMarker != prompt.ModelSchemaContractMarker {
		t.Fatalf("marker=%s", identity.ModelSchemaContractMarker)
	}
	if identity.PromptFingerprint == "" || identity.ModelSchemaFingerprint == "" {
		t.Fatalf("missing fingerprints: %+v", identity)
	}
}

func TestDeriveC2CTargetedReadinessAllPass(t *testing.T) {
	plan, _ := eval.BuildC2CTargetedRunPlan()
	results := make([]eval.RunResult, 0, 6)
	for _, caseID := range eval.C2CTargetedCaseIDs() {
		for run := 1; run <= 2; run++ {
			results = append(results, eval.RunResult{
				CaseID: caseID, RunIndex: run, EndToEndPass: true, ModelResponseAssessed: true,
				ContractStages: eval.ContractStages{
					ContentJSONValid: true, DraftDTODecode: "pass", GatewaySchemaValidation: "pass", FactValidation: "pass",
				},
				DiagnosticSnapshot: eval.EvaluationDiagnosticSnapshot{
					KeyFactSelectionPass: true, KeyFactMaterializationPass: true, KeyFactCanonicalParityPass: true,
				},
			})
		}
	}
	readiness := eval.DeriveC2CTargetedReadiness(plan, results)
	if readiness.Verdict != eval.ReadinessPass {
		t.Fatalf("verdict=%s", readiness.Verdict)
	}
}

func formatMaterializedKeyFacts(items []eval.MaterializedKeyFactSnapshot) string {
	data, err := json.Marshal(items)
	if err != nil {
		return "[]"
	}
	return string(data)
}

func containsString(items []string, target string) bool {
	for _, item := range items {
		if item == target {
			return true
		}
	}
	return false
}

func TestC2CFrozenFullArtifactUntouched(t *testing.T) {
	path := eval.DefaultOutputDir + "/full-v2-20260817-070704.json"
	if _, err := os.Stat(path); err != nil {
		t.Skip("frozen C2 artifact unavailable")
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(data), "full-v2") {
		t.Fatal("unexpected artifact content")
	}
}
