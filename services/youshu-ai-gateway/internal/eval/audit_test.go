package eval_test

import (
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/eval"
)

func TestDeriveActualRiskNoWarnings(t *testing.T) {
	got := eval.DeriveActualRisk(nil)
	if got != eval.RiskLevelNone {
		t.Fatalf("got %q want none", got)
	}
}

func TestDeriveActualRiskMaxAggregation(t *testing.T) {
	warnings := []contract.Warning{
		{Severity: "safe", Title: "a", Message: "a", Source: "a"},
		{Severity: "warning", Title: "b", Message: "b", Source: "b"},
	}
	got := eval.DeriveActualRisk(warnings)
	if got != eval.RiskLevelWarning {
		t.Fatalf("max aggregation got %q want warning", got)
	}
}

func TestCheckRiskLevelNoneAllowsSafe(t *testing.T) {
	warnings := []contract.Warning{{Severity: "safe", Title: "t", Message: "m", Source: "s"}}
	if !eval.CheckRiskLevelMatch(eval.RiskLevelNone, warnings) {
		t.Fatal("none should allow safe-severity warnings")
	}
}

func TestCheckRiskLevelNoneRejectsWarning(t *testing.T) {
	warnings := []contract.Warning{{Severity: "warning", Title: "t", Message: "m", Source: "s"}}
	if eval.CheckRiskLevelMatch(eval.RiskLevelNone, warnings) {
		t.Fatal("none should reject warning severity")
	}
}

func TestCheckRiskLevelWarningAcceptsRisk(t *testing.T) {
	warnings := []contract.Warning{{Severity: "risk", Title: "t", Message: "m", Source: "s"}}
	if !eval.CheckRiskLevelMatch(eval.RiskLevelWarning, warnings) {
		t.Fatal("expected warning should accept risk severity")
	}
}

func TestRiskMismatchDirectionUnexpectedWarning(t *testing.T) {
	warnings := []contract.Warning{{Severity: "warning", Title: "t", Message: "m", Source: "s"}}
	_, dir := eval.DiagnoseRiskMismatch(eval.RiskLevelNone, warnings)
	if dir != eval.RiskMismatchUnexpectedWarning {
		t.Fatalf("got %q want unexpectedWarning", dir)
	}
}

func TestRiskMismatchDirectionMissingWarning(t *testing.T) {
	_, dir := eval.DiagnoseRiskMismatch(eval.RiskLevelWarning, nil)
	if dir != eval.RiskMismatchMissingWarning {
		t.Fatalf("got %q want missingWarning", dir)
	}
}

func TestAnalyzeDebtFactsE01PartialData(t *testing.T) {
	c := findCase(t, "E01_partial_debt_data")
	analysis := eval.AnalyzeDebtFacts(c)
	if !analysis.DebtFactsPartial {
		t.Fatal("E01 should be partial debt")
	}
}

func TestAnalyzeDebtFactsC01KnownZero(t *testing.T) {
	c := findCase(t, "C01_no_debt")
	analysis := eval.AnalyzeDebtFacts(c)
	if !analysis.DebtFactsKnownZero {
		t.Fatal("C01 should be known zero debt")
	}
}

func TestUnknownCheckerRule(t *testing.T) {
	c := findCase(t, "E01_partial_debt_data")
	rule := eval.UnknownCheckerRule(c)
	if rule == "" {
		t.Fatal("expected rule description")
	}
	fp, fn := eval.UnknownCheckerRisk(c)
	if fp == "" {
		t.Fatal("expected false positive risk note")
	}
	_ = fn
}

func TestStructuredConclusionB01WithKeyFacts(t *testing.T) {
	c := findCase(t, "B01_minimum_below_safe")
	snap := eval.StructuredSnapshot{
		CitedFactKeys:    []string{"minimumBalance", "safeBalance"},
		KeyFactSources:   []string{"minimumBalance", "safeBalance"},
		WarningSources:   []string{"minimumBalance"},
		WarningCount:     1,
	}
	audit := eval.AuditStructuredConclusion(c, snap)
	if !audit.StructuredConclusionPresent {
		t.Fatal("B01 should pass structured conclusion when key facts present")
	}
}

func TestStructuredConclusionB01NarrativeFalseNegative(t *testing.T) {
	c := findCase(t, "B01_minimum_below_safe")
	draft := b01StructuredDraft()
	draft.Body = "最低余额低于安全余额"
	result := eval.CheckExpectations(c, draft)
	if !result.Passed {
		t.Fatal("B01 structured pass should not fail on narrative wording")
	}
}

func TestAuditA01ModelOverWarning(t *testing.T) {
	c := findCase(t, "A01_healthy_cashflow")
	snap := eval.StructuredSnapshot{
		ExpectedRiskLevel:     eval.RiskLevelNone,
		WarningCount:          1,
		WarningSeverities:     []string{"warning"},
		ActualDerivedRisk:     eval.RiskLevelWarning,
		RiskMismatchDirection: eval.RiskMismatchUnexpectedWarning,
	}
	r := eval.RunResult{
		CaseID: "A01_healthy_cashflow", RunIndex: 1,
		ContractPass: true, EndToEndPass: false,
		FailureClass: eval.FailureSemanticRisk,
	}
	v := eval.AuditSemanticFailure(c, r, snap)
	if !v.ModelOverWarningCandidate {
		t.Fatal("A01 with warning severity should flag modelOverWarning")
	}
	if v.Verdict != eval.VerdictModelError {
		t.Fatalf("expected model error, got %s", v.Verdict)
	}
}

func TestAuditE01PartialNotFalsePositive(t *testing.T) {
	c := findCase(t, "E01_partial_debt_data")
	r := eval.RunResult{
		CaseID: "E01_partial_debt_data", RunIndex: 1,
		ContractPass: true, EndToEndPass: true,
	}
	snap := eval.StructuredSnapshot{UnknownCount: 0}
	v := eval.AuditSemanticFailure(c, r, snap)
	if v.Verdict == eval.VerdictEvaluatorFalsePositive {
		t.Fatal("partial debt should not be false positive when passing")
	}
}

func TestFailureSeverityHealthyToRisk(t *testing.T) {
	c := findCase(t, "A01_healthy_cashflow")
	snap := eval.StructuredSnapshot{RiskMismatchDirection: eval.RiskMismatchUnexpectedWarning}
	sev := eval.ClassifyFailureSeverity(eval.FailureSemanticRisk, c, snap)
	if sev != eval.SeverityMajor {
		t.Fatalf("healthy→risk should be major, got %s", sev)
	}
}

func TestFailureSeverityConclusionDiagnostic(t *testing.T) {
	c := findCase(t, "B01_minimum_below_safe")
	snap := eval.StructuredSnapshot{}
	sev := eval.ClassifyFailureSeverity(eval.FailureSemanticConclusion, c, snap)
	if sev != eval.SeverityDiagnostic {
		t.Fatalf("wording mismatch should be diagnostic, got %s", sev)
	}
}

func TestAuditPilotReportSynthetic(t *testing.T) {
	report := buildSyntheticPilotReport()
	audit := eval.AuditPilotReport(report, eval.AllCases())

	if audit.RawSemanticFailures != 9 {
		t.Fatalf("expected 9 semantic failures in fixed synthetic replay, got %d", audit.RawSemanticFailures)
	}
	if audit.ConfirmedModelFailures < 5 {
		t.Fatalf("expected several confirmed model failures, got %d", audit.ConfirmedModelFailures)
	}
	if audit.EvaluatorFalsePositives < 0 {
		t.Fatalf("expected no evaluator false positives in fixed synthetic replay")
	}
	if audit.SummaryText == "" {
		t.Fatal("expected summary text")
	}
}

func TestFormatPilotAuditSummarySections(t *testing.T) {
	audit := eval.AuditPilotReport(buildSyntheticPilotReport(), eval.AllCases())
	for _, section := range []string{"Risk Checker Algorithm", "Reclassified Failures", "Case Audits"} {
		if !contains(audit.SummaryText, section) {
			t.Fatalf("missing section %q", section)
		}
	}
}

func findCase(t *testing.T, id string) eval.EvaluationCase {
	t.Helper()
	for _, c := range eval.AllCases() {
		if c.ID == id {
			return c
		}
	}
	t.Fatalf("case %s not found", id)
	return eval.EvaluationCase{}
}

func contains(s, sub string) bool {
	return len(s) >= len(sub) && (s == sub || len(sub) == 0 || indexOf(s, sub) >= 0)
}

func indexOf(s, sub string) int {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return i
		}
	}
	return -1
}

// buildSyntheticPilotReport reconstructs pilot failures from reported metrics.
func buildSyntheticPilotReport() eval.EvaluationReport {
	makeRiskFail := func(caseID, category string, run int, sev string) eval.RunResult {
		snap := eval.StructuredSnapshot{
			WarningCount:      1,
			WarningSeverities: []string{sev},
			ActualDerivedRisk: eval.RiskLevelWarning,
		}
		if sev == "risk" {
			snap.ActualDerivedRisk = eval.RiskLevelRisk
		}
		if caseID == "A01_healthy_cashflow" || caseID == "F06_no_warning_expected" {
			snap.ExpectedRiskLevel = eval.RiskLevelNone
			snap.RiskMismatchDirection = eval.RiskMismatchUnexpectedWarning
		}
		if caseID == "C03_high_monthly_payment" || caseID == "D02_zero_income_month" {
			snap.ExpectedRiskLevel = eval.RiskLevelWarning
			snap.ActualDerivedRisk = eval.RiskLevelNone
			snap.WarningCount = 0
			snap.WarningSeverities = nil
			snap.RiskMismatchDirection = eval.RiskMismatchMissingWarning
		}
		return eval.RunResult{
			CaseID: caseID, Category: category, RunIndex: run,
			ContractPass: true, SemanticPass: false, EndToEndPass: false,
			FailureClass: eval.FailureSemanticRisk,
			StructuredSnapshot: snap,
		}
	}

	results := []eval.RunResult{
		makeRiskFail("A01_healthy_cashflow", eval.CategoryHealthyFinance, 1, "warning"),
		makeRiskFail("A01_healthy_cashflow", eval.CategoryHealthyFinance, 2, "warning"),
		{CaseID: "A01_healthy_cashflow", Category: eval.CategoryHealthyFinance, RunIndex: 3, Timeout: true, FailureClass: eval.FailureTimeout, ContractStages: eval.ContractStages{TimeoutStage: "upstreamHTTP"}},
		makeRiskFail("C03_high_monthly_payment", eval.CategoryDebt, 1, ""),
		makeRiskFail("C03_high_monthly_payment", eval.CategoryDebt, 2, ""),
		makeRiskFail("C03_high_monthly_payment", eval.CategoryDebt, 3, ""),
		{CaseID: "E01_partial_debt_data", Category: eval.CategoryInsufficientData, RunIndex: 1, ContractPass: true, SemanticPass: true, EndToEndPass: true},
		{CaseID: "E05_missing_debt_data", Category: eval.CategoryInsufficientData, RunIndex: 1, ContractPass: true, SemanticPass: false, EndToEndPass: false, FailureClass: eval.FailureSemanticUnknown, StructuredSnapshot: eval.StructuredSnapshot{UnknownCount: 0}},
		makeRiskFail("F06_no_warning_expected", eval.CategoryEdgeCase, 1, "warning"),
		makeRiskFail("D02_zero_income_month", eval.CategoryIncomeExpense, 1, ""),
		{CaseID: "B01_minimum_below_safe", Category: eval.CategoryCashFlowRisk, RunIndex: 1, ContractPass: true, SemanticPass: false, EndToEndPass: false, FailureClass: eval.FailureSemanticConclusion, StructuredSnapshot: eval.StructuredSnapshot{CitedFactKeys: []string{"minimumBalance", "safeBalance"}, KeyFactSources: []string{"minimumBalance", "safeBalance"}, WarningSources: []string{"minimumBalance"}}},
		{CaseID: "F01_all_amounts_zero", Category: eval.CategoryEdgeCase, RunIndex: 1, ContractPass: true, SemanticPass: true, EndToEndPass: true},
		{CaseID: "F03_large_amounts", Category: eval.CategoryEdgeCase, RunIndex: 1, ContractPass: true, SemanticPass: true, EndToEndPass: true},
	}

	return eval.EvaluationReport{
		Metadata: eval.RunMetadata{TotalRuns: 16, PilotMode: true},
		Results:  results,
		Metrics:  eval.ComputeMetrics(results, eval.EvaluationModeExplanationAlignmentV2),
	}
}
