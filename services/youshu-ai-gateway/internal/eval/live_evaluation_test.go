package eval_test

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/config"
	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/eval"
	"github.com/youshu/youshu-ai-gateway/internal/provider"
)

// TestLiveEvaluation runs real AI evaluation against Bailian.
// Requires YOUSHU_EVAL_LIVE=1 plus mode flags; credentials alone are insufficient.
func TestLiveEvaluation(t *testing.T) {
	if reason := eval.RequireLiveEvalOptIn(); reason != "" {
		t.Skip(reason)
	}

	cfg := config.Load()
	cfg.UpstreamAIProvider = config.UpstreamBailian

	opts := eval.LoadFilterOptions()
	plan, _, err := eval.BuildRunPlan(opts)
	if err != nil {
		t.Fatalf("BuildRunPlan: %v", err)
	}

	cred := eval.CheckLiveCredentials(cfg)
	if !cred.Configured {
		t.Skipf("Live Evaluation blocked: runStatus=%s missing=%v (not a semantic failure)", eval.RunStatusConfigurationBlocked, cred.Missing)
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
		t.Fatalf("live preflight failed: runStatus=%s reason=%s", preflight.RunStatus, preflight.BlockReason)
	}

	report, err := eval.RunEvaluation(context.Background(), cfg, bailian, opts)
	if err != nil {
		t.Fatalf("RunEvaluation: %v", err)
	}
	if report.RunStatus != eval.RunStatusExecuted {
		t.Fatalf("expected runStatus=%s got %s reason=%s", eval.RunStatusExecuted, report.RunStatus, report.PreflightSummary)
	}
	if err := eval.ValidateRunPlanCompletion(plan, report); err != nil {
		t.Fatalf("run plan completion: %v", err)
	}

	eval.SetUpstreamModel(&report, cfg.BailianModel)

	writeResult, err := eval.WriteReport(report, eval.DefaultOutputDir)
	if err != nil {
		t.Fatalf("WriteReport: %v", err)
	}

	pilotAudit := eval.AuditPilotReport(report, eval.AllCases())
	if !opts.PilotMode && !opts.SmokeV2Mode && !opts.ConnectivityProbeMode {
		t.Log(pilotAudit.SummaryText)
	}

	if !opts.PilotMode && !opts.SmokeV2Mode && !opts.ConnectivityProbeMode {
		summary, err := eval.BuildDatasetSummary()
		if err != nil {
			t.Fatalf("BuildDatasetSummary: %v", err)
		}
		if report.Metadata.TotalCases != summary.DatasetCases {
			t.Errorf("totalCases: got %d want %d", report.Metadata.TotalCases, summary.DatasetCases)
		}
		if report.Metadata.TotalRuns != summary.FullRuns {
			t.Errorf("totalRuns: got %d want %d", report.Metadata.TotalRuns, summary.FullRuns)
		}
		t.Logf("FULL EVAL verdict: %s", report.Analysis.ModelVerdict)
	}

	t.Log(report.Summary)
	t.Logf("report written to %s", writeResult.LatestPath)
	if writeResult.TimestampedPath != "" {
		t.Logf("timestamped artifact written to %s", writeResult.TimestampedPath)
	}

	failures := 0
	for _, r := range report.Results {
		if !r.EndToEndPass {
			failures++
			t.Logf("FAIL case=%s run=%d class=%s detail=%s", r.CaseID, r.RunIndex, r.FailureClass, r.FailureDetail)
		}
	}
	if failures > 0 {
		t.Errorf("%d/%d runs failed", failures, len(report.Results))
	}
}

func TestLiveEvaluationPilotMode(t *testing.T) {
	t.Setenv("YOUSHU_EVAL_PILOT", "1")
	t.Setenv("YOUSHU_EVAL_SMOKE_V2", "")
	opts := eval.LoadFilterOptions()
	if !opts.PilotMode {
		t.Fatal("pilot mode should be enabled")
	}
	cases, err := eval.FilterCases(eval.AllCases(), opts)
	if err != nil {
		t.Fatalf("FilterCases: %v", err)
	}
	if len(cases) != 7 {
		t.Fatalf("pilot should have 7 cases, got %d", len(cases))
	}
	expectedRuns, err := eval.ExpectedPilotRuns()
	if err != nil {
		t.Fatalf("ExpectedPilotRuns: %v", err)
	}
	if eval.CountRuns(cases) != expectedRuns {
		t.Fatalf("pilot runs: got %d want %d", eval.CountRuns(cases), expectedRuns)
	}
}

func TestCoreCasesHaveThreeRepeats(t *testing.T) {
	coreIDs := map[string]bool{
		"A01_healthy_cashflow":     true,
		"B01_minimum_below_safe": true,
		"C03_high_monthly_payment": true,
		"E01_partial_debt_data":    true,
	}
	for _, c := range eval.AllCases() {
		if coreIDs[c.ID] && c.Repeats != 3 {
			t.Fatalf("%s should have 3 repeats, got %d", c.ID, c.Repeats)
		}
		if !coreIDs[c.ID] && c.Repeats != 1 {
			t.Fatalf("%s should have 1 repeat, got %d", c.ID, c.Repeats)
		}
	}
	plans := eval.ExpandRuns(eval.AllCases())
	if eval.CountRuns(eval.AllCases()) != 37 {
		t.Fatalf("expected 37 total runs, got %d", len(plans))
	}
}

func TestFilterByCaseID(t *testing.T) {
	opts := eval.FilterOptions{CaseID: "A01_healthy_cashflow"}
	cases, err := eval.FilterCases(eval.AllCases(), opts)
	if err != nil {
		t.Fatalf("FilterCases: %v", err)
	}
	if len(cases) != 1 || cases[0].ID != "A01_healthy_cashflow" {
		t.Fatalf("unexpected filter result: %+v", cases)
	}
}

func TestFilterByCategory(t *testing.T) {
	opts := eval.FilterOptions{Category: eval.CategoryDebt}
	cases, err := eval.FilterCases(eval.AllCases(), opts)
	if err != nil {
		t.Fatalf("FilterCases: %v", err)
	}
	if len(cases) != 6 {
		t.Fatalf("expected 6 debt cases, got %d", len(cases))
	}
}

func TestFilterRepeatOverride(t *testing.T) {
	opts := eval.FilterOptions{CaseID: "A02_high_income_low_expense", RepeatOverride: 5}
	cases, err := eval.FilterCases(eval.AllCases(), opts)
	if err != nil {
		t.Fatalf("FilterCases: %v", err)
	}
	if cases[0].Repeats != 5 {
		t.Fatalf("repeat override not applied: %d", cases[0].Repeats)
	}
}

func TestFilterNoMatchFails(t *testing.T) {
	opts := eval.FilterOptions{CaseID: "nonexistent_case"}
	_, err := eval.FilterCases(eval.AllCases(), opts)
	if err == nil {
		t.Fatal("expected error for no matching cases")
	}
}

func TestPercentileCalculation(t *testing.T) {
	values := []int64{10, 20, 30, 40, 50, 60, 70, 80, 90, 100}
	p50 := eval.Percentile(values, 50)
	if p50 != 50 && p50 != 60 {
		t.Fatalf("P50 unexpected: %d", p50)
	}
	p95 := eval.Percentile(values, 95)
	if p95 != 100 {
		t.Fatalf("P95 unexpected: %d", p95)
	}
	if eval.Percentile(nil, 50) != 0 {
		t.Fatal("empty percentile should be 0")
	}
}

func TestComputeMetrics(t *testing.T) {
	results := []eval.RunResult{
		{EndToEndPass: true, LatencyMs: 100, PromptTokens: 1000, CompletionTokens: 500, TotalTokens: 1500, RiskMatch: true, UnknownBehaviorPass: true, ContractStages: eval.ContractStages{HTTPSuccess: true, ContentJSONValid: true, DraftDTODecode: "pass", GatewaySchemaValidation: "pass", FactValidation: "pass"}, ContractPass: true},
		{EndToEndPass: false, FailureClass: eval.FailureFact, LatencyMs: 200, ContractStages: eval.ContractStages{HTTPSuccess: true, FactValidation: "fail"}},
		{EndToEndPass: false, LatencyMs: 300, Timeout: true, ContractStages: eval.ContractStages{HTTPSuccess: false, TimeoutStage: "upstreamHTTP"}},
	}
	m := eval.ComputeMetrics(results, eval.EvaluationModeExplanationAlignmentV2)
	if m.TotalRuns != 3 {
		t.Fatalf("total runs: %d", m.TotalRuns)
	}
	if m.EndToEndSuccessCount != 1 {
		t.Fatalf("e2e success: %d", m.EndToEndSuccessCount)
	}
	if m.TimeoutCount != 1 {
		t.Fatalf("timeout count: %d", m.TimeoutCount)
	}
	if m.FailureBreakdown[eval.FailureFact] != 1 {
		t.Fatalf("failure breakdown: %v", m.FailureBreakdown)
	}
}

func TestCheckExpectationsRiskLevel(t *testing.T) {
	c := eval.EvaluationCase{ExpectedRiskLevel: eval.RiskLevelWarning}
	draft := contract.AssistantAnswerDraftDTO{
		Title: "t", Body: "b", Answer: "a",
		CitedFactKeys: []string{}, Unknowns: []string{},
		KeyFacts: []contract.KeyFact{}, Actions: []contract.Action{},
		References: []contract.Reference{},
		Warnings: []contract.Warning{{Title: "w", Message: "现金流压力", Severity: "warning", Source: "cashFlowRiskExplanation"}},
	}
	result := eval.CheckExpectations(c, draft)
	if !result.RiskMatch || !result.Passed {
		t.Fatalf("expected warning risk to pass: %+v", result)
	}
}

func TestCheckExpectationsForbiddenClaim(t *testing.T) {
	c := eval.EvaluationCase{
		ForbiddenClaims: []string{"一定会逾期"},
	}
	draft := contract.AssistantAnswerDraftDTO{
		Title: "t", Body: "你一定会逾期", Answer: "a",
		CitedFactKeys: []string{}, Unknowns: []string{},
		KeyFacts: []contract.KeyFact{}, Actions: []contract.Action{},
		References: []contract.Reference{}, Warnings: []contract.Warning{},
	}
	result := eval.CheckExpectations(c, draft)
	if result.Passed {
		t.Fatal("forbidden claim should fail")
	}
	if len(result.ForbiddenClaimHits) != 1 {
		t.Fatalf("expected 1 hit, got %v", result.ForbiddenClaimHits)
	}
	if result.FailureClasses[0] != eval.FailureSemanticForbidden {
		t.Fatalf("unexpected failure class: %v", result.FailureClasses)
	}
}

func TestCheckExpectationsRequiredUnknowns(t *testing.T) {
	c := eval.EvaluationCase{UnknownExpectation: eval.UnknownRequired}
	draft := contract.AssistantAnswerDraftDTO{
		Title: "t", Body: "b", Answer: "a",
		CitedFactKeys: []string{}, Unknowns: []string{},
		KeyFacts: []contract.KeyFact{}, Actions: []contract.Action{},
		References: []contract.Reference{}, Warnings: []contract.Warning{},
	}
	result := eval.CheckExpectations(c, draft)
	if result.UnknownBehaviorPass {
		t.Fatal("empty unknowns should fail when required")
	}
}

func TestCheckExpectationsAllowedActions(t *testing.T) {
	c := eval.EvaluationCase{AllowedActions: []string{"cashFlow", "debt"}}
	draft := contract.AssistantAnswerDraftDTO{
		Title: "t", Body: "b", Answer: "a",
		CitedFactKeys: []string{}, Unknowns: []string{},
		KeyFacts: []contract.KeyFact{},
		Actions:       []contract.Action{{Title: "查看", Destination: "transactions"}},
		References:    []contract.Reference{}, Warnings: []contract.Warning{},
	}
	result := eval.CheckExpectations(c, draft)
	if result.ActionCompliancePass {
		t.Fatal("transactions action should fail when not allowed")
	}
}

func TestDiagnosticKeywordsDoNotHardFail(t *testing.T) {
	c := eval.EvaluationCase{
		DiagnosticKeywords:   []string{"不可能出现的结论"},
		ManualReviewRequired: true,
	}
	draft := contract.AssistantAnswerDraftDTO{
		Title: "t", Body: "b", Answer: "a",
		CitedFactKeys: []string{}, Unknowns: []string{},
		KeyFacts: []contract.KeyFact{}, Actions: []contract.Action{},
		References: []contract.Reference{}, Warnings: []contract.Warning{},
	}
	result := eval.CheckExpectations(c, draft)
	if !result.Passed {
		t.Fatal("diagnostic keywords must not hard fail")
	}
	if len(result.DiagnosticKeywordMisses) != 1 {
		t.Fatalf("expected 1 diagnostic miss, got %v", result.DiagnosticKeywordMisses)
	}
}

func TestClassifyContractFailure(t *testing.T) {
	tests := []struct {
		name  string
		stage eval.ContractStages
		want  string
	}{
		{"timeout", eval.ContractStages{TimeoutStage: "upstreamHTTP"}, eval.FailureTimeout},
		{"network", eval.ContractStages{RequestAttempted: true, HTTPSuccess: false}, eval.FailureConnection},
		{"json", eval.ContractStages{HTTPSuccess: true, HTTP2xxSuccess: true, UpstreamHTTP: "pass", ContentJSONValid: false}, eval.FailureJSON},
		{"dto", eval.ContractStages{HTTPSuccess: true, HTTP2xxSuccess: true, UpstreamHTTP: "pass", ContentJSONValid: true, GenericJSONObjectDecode: "pass", DraftDTODecode: "fail"}, eval.FailureDTO},
		{"schema", eval.ContractStages{HTTPSuccess: true, HTTP2xxSuccess: true, UpstreamHTTP: "pass", ContentJSONValid: true, GenericJSONObjectDecode: "pass", DraftDTODecode: "pass", GatewaySchemaValidation: "fail"}, eval.FailureSchema},
		{"fact", eval.ContractStages{HTTPSuccess: true, HTTP2xxSuccess: true, UpstreamHTTP: "pass", ContentJSONValid: true, GenericJSONObjectDecode: "pass", DraftDTODecode: "pass", GatewaySchemaValidation: "pass", FactValidation: "fail"}, eval.FailureFact},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := eval.ClassifyContractFailure(tc.stage)
			if got != tc.want {
				t.Fatalf("got %q want %q", got, tc.want)
			}
		})
	}
}

func TestFormatSummaryContainsKeySections(t *testing.T) {
	meta := eval.RunMetadata{
		StartedAt: "2026-01-01T00:00:00Z", FinishedAt: "2026-01-01T00:01:00Z",
		ConfiguredModel: "qwen3.7-plus", StructuredOutputMode: "json_schema_strict",
		TotalCases: 29, TotalRuns: 37,
	}
	results := []eval.RunResult{
		{EndToEndPass: true, LatencyMs: 15000, ContractPass: true, RiskMatch: true, UnknownBehaviorPass: true,
			ContractStages: eval.ContractStages{HTTPSuccess: true, ContentJSONValid: true, DraftDTODecode: "pass", GatewaySchemaValidation: "pass", FactValidation: "pass"}},
	}
	m := eval.ComputeMetrics(results, eval.EvaluationModeExplanationAlignmentV2)
	analysis := eval.AnalyzeFullEvaluation(results, eval.AllCases(), m, eval.EvaluationModeExplanationAlignmentV2)
	summary := eval.FormatSummary(meta, m, analysis, eval.EvaluationVersionV2, eval.EvaluationModeExplanationAlignmentV2)
	for _, section := range []string{
		"Contract Metrics", "Fact Safety", "Legacy Semantic Metrics", "Latency / Tokens",
		"v2 Acceptance Thresholds", "Failure Breakdown", "Readiness Verdicts",
	} {
		if !strings.Contains(summary, section) {
			t.Fatalf("summary missing section %q", section)
		}
	}
}

func TestWriteReportExcludesSecrets(t *testing.T) {
	dir := t.TempDir()
	report := eval.BuildReport(
		eval.RunMetadata{ConfiguredModel: "test-model", TotalRuns: 1},
		[]eval.RunResult{{CaseID: "A01_healthy_cashflow", EndToEndPass: true}},
		eval.ComputeMetrics([]eval.RunResult{{EndToEndPass: true}}, eval.EvaluationModeExplanationAlignmentV2),
		eval.EvaluationModeExplanationAlignmentV2,
	)
	report.Summary = "Bearer sk-secret-key should be redacted"
	writeResult, err := eval.WriteReport(report, dir)
	if err != nil {
		t.Fatalf("WriteReport: %v", err)
	}
	data, err := os.ReadFile(writeResult.LatestPath)
	if err != nil {
		t.Fatalf("read report: %v", err)
	}
	content := string(data)
	if strings.Contains(content, "sk-secret-key") {
		t.Fatal("report should not contain secret key")
	}
	if !strings.Contains(content, "REDACTED") {
		t.Fatal("report should contain REDACTED marker")
	}
}

func TestAdjudicateFullEvaluationOffline(t *testing.T) {
	path := filepath.Join(eval.DefaultOutputDir, eval.LatestReportFile)
	if _, err := os.Stat(path); err != nil {
		t.Skip("Full eval report not found; run TestLiveEvaluation first")
	}
	adj, err := eval.LoadAndAdjudicateReport(path)
	if err != nil {
		t.Fatalf("LoadAndAdjudicateReport: %v", err)
	}
	if adj.AdjudicatedMetrics.EvaluatorFalsePositives != 0 {
		t.Fatalf("adjudicated evaluator false positives must be 0, got %d", adj.AdjudicatedMetrics.EvaluatorFalsePositives)
	}
	outPath, err := eval.WriteAdjudicationReport(adj, eval.DefaultOutputDir)
	if err != nil {
		t.Fatalf("WriteAdjudicationReport: %v", err)
	}
	t.Log(adj.SummaryText)
	t.Logf("adjudication written to %s", outPath)
}

func TestReportSerialization(t *testing.T) {
	report := eval.BuildReport(
		eval.RunMetadata{ConfiguredModel: "qwen3.7-plus", TotalRuns: 2},
		[]eval.RunResult{
			{CaseID: "A01_healthy_cashflow", Category: eval.CategoryHealthyFinance, EndToEndPass: true, LatencyMs: 15000},
			{CaseID: "B01_minimum_below_safe", Category: eval.CategoryCashFlowRisk, EndToEndPass: false, FailureClass: eval.FailureSemanticRisk},
		},
		eval.ComputeMetrics([]eval.RunResult{
			{EndToEndPass: true, LatencyMs: 15000, ContractPass: true, ContractStages: eval.ContractStages{HTTPSuccess: true, ContentJSONValid: true, DraftDTODecode: "pass", GatewaySchemaValidation: "pass", FactValidation: "pass"}},
			{EndToEndPass: false, FailureClass: eval.FailureSemanticRisk, LatencyMs: 16000},
		}, eval.EvaluationModeExplanationAlignmentV2),
		eval.EvaluationModeExplanationAlignmentV2,
	)
	dir := t.TempDir()
	writeResult, err := eval.WriteReport(report, dir)
	if err != nil {
		t.Fatalf("WriteReport: %v", err)
	}
	if !strings.HasSuffix(writeResult.LatestPath, "latest.json") {
		t.Fatalf("unexpected path: %s", writeResult.LatestPath)
	}
}
