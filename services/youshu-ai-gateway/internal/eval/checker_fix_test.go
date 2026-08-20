package eval_test

import (
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/eval"
)

func TestDatasetHas29Cases(t *testing.T) {
	cases := eval.AllCases()
	if len(cases) != 29 {
		t.Fatalf("expected 29 cases, got %d", len(cases))
	}
	if err := eval.ValidateDataset(cases); err != nil {
		t.Fatalf("ValidateDataset: %v", err)
	}
	counts := eval.CategoryCounts(cases)
	if counts[eval.CategoryInsufficientData] != 5 {
		t.Fatalf("insufficient_data should have 5 cases, got %d", counts[eval.CategoryInsufficientData])
	}
}

func TestPartialDebtUnknownNotRequired(t *testing.T) {
	c := findCase(t, "E01_partial_debt_data")
	if eval.ResolveUnknownExpectation(c) != eval.UnknownNotRequired {
		t.Fatalf("partial debt must not require unknowns")
	}
	debt := eval.AnalyzeDebtFacts(c)
	if !debt.DebtFactsPartial {
		t.Fatal("E01 should be partial debt")
	}
	draft := contract.AssistantAnswerDraftDTO{
		Title: "t", Body: "b", Answer: "a",
		CitedFactKeys: []string{"monthlyDebtPayment"},
		KeyFacts: []contract.KeyFact{{
			Source: "monthlyDebtPayment", Kind: "debt", Label: "还款",
			Value: contract.KeyFactValue{Type: "money", Amount: floatPtr(800), CurrencyCode: strPtr("CNY")},
		}},
		Unknowns: []string{}, Warnings: []contract.Warning{},
		Actions: []contract.Action{}, References: []contract.Reference{},
	}
	result := eval.CheckExpectations(c, draft)
	if !result.UnknownBehaviorPass || !result.Passed {
		t.Fatalf("partial debt with empty unknowns should pass: %+v", result)
	}
}

func TestE03BudgetNotApplicableUnknownNotRequired(t *testing.T) {
	c := findCase(t, "E03_no_budget")
	if eval.ResolveUnknownExpectation(c) != eval.UnknownNotRequired {
		t.Fatal("E03 must not require unknowns")
	}
	data := eval.AnalyzeInsufficientDataCase(c)
	if data.Classification != eval.DataNotApplicable {
		t.Fatalf("expected notApplicable, got %s", data.Classification)
	}
}

func TestE04OptionalAbsentUnknownNotRequired(t *testing.T) {
	c := findCase(t, "E04_partial_facts_missing")
	if eval.ResolveUnknownExpectation(c) != eval.UnknownNotRequired {
		t.Fatal("E04 must not require unknowns")
	}
	data := eval.AnalyzeInsufficientDataCase(c)
	if data.Classification != eval.DataOptionalAbsent {
		t.Fatalf("expected optionalAbsent, got %s", data.Classification)
	}
}

func TestMissingDebtUnknownRequired(t *testing.T) {
	c := findCase(t, "E05_missing_debt_data")
	debt := eval.AnalyzeDebtFacts(c)
	if !debt.DebtFactsMissing {
		t.Fatal("E05 should be genuinely missing debt")
	}
	draft := contract.AssistantAnswerDraftDTO{
		Title: "t", Body: "b", Answer: "a",
		CitedFactKeys: []string{}, Unknowns: []string{},
		Warnings: []contract.Warning{}, Actions: []contract.Action{}, References: []contract.Reference{},
	}
	result := eval.CheckExpectations(c, draft)
	if result.UnknownBehaviorPass {
		t.Fatal("missing debt with empty unknowns must fail")
	}
}

func TestKnownZeroDebtIsNotMissing(t *testing.T) {
	c := findCase(t, "C01_no_debt")
	debt := eval.AnalyzeDebtFacts(c)
	if !debt.DebtFactsKnownZero || debt.DebtFactsMissing {
		t.Fatal("C01 known zero must not be missing")
	}
}

func TestMissingDebtUsesOverlayNotEmptyString(t *testing.T) {
	c := findCase(t, "E05_missing_debt_data")
	if eval.ResolveDebtPaymentAvailability(c) != eval.MoneyMissing {
		t.Fatal("missing debt must use MoneyMissing overlay")
	}
	if c.Envelope.MonthlySummaryFacts.MonthlyDebtPayment.Amount != "" {
		t.Fatal("missing debt fixture must leave production DTO amount unset")
	}
}

func TestB01StructuredConclusionPass(t *testing.T) {
	c := findCase(t, "B01_minimum_below_safe")
	draft := b01StructuredDraft()
	result := eval.CheckExpectations(c, draft)
	if !result.StructuredConclusionPass || !result.Passed {
		t.Fatalf("B01 structured conclusion should pass: %+v", result)
	}
}

func TestB01SynonymNarrativeDoesNotFail(t *testing.T) {
	c := findCase(t, "B01_minimum_below_safe")
	draft := b01StructuredDraft()
	draft.Body = "最低余额低于安全余额"
	result := eval.CheckExpectations(c, draft)
	if !result.Passed {
		t.Fatalf("B01 must not fail without 现金流 keyword: %+v", result)
	}
}

func TestNarrativeKeywordNotHardFail(t *testing.T) {
	c := findCase(t, "C03_high_monthly_payment")
	draft := contract.AssistantAnswerDraftDTO{
		Title: "t", Body: "还款压力较高", Answer: "a",
		Warnings:  []contract.Warning{{Severity: "warning", Title: "w", Message: "m", Source: "monthlyDebtPayment"}},
		CitedFactKeys: []string{"monthlyDebtPayment"}, Unknowns: []string{},
		KeyFacts: []contract.KeyFact{}, Actions: []contract.Action{}, References: []contract.Reference{},
	}
	result := eval.CheckExpectations(c, draft)
	if !result.RiskMatch {
		t.Fatal("C03 should pass risk with warning present")
	}
	if len(result.DiagnosticKeywordMisses) > 0 && !result.Passed {
		t.Fatal("diagnostic keyword miss must not cause hard fail")
	}
}

func TestA01UnexpectedWarningStillFails(t *testing.T) {
	c := findCase(t, "A01_healthy_cashflow")
	draft := contract.AssistantAnswerDraftDTO{
		Title: "t", Body: "b", Answer: "a",
		Warnings:      []contract.Warning{{Severity: "warning", Title: "w", Message: "m", Source: "availableCash"}},
		CitedFactKeys: []string{}, Unknowns: []string{},
		KeyFacts: []contract.KeyFact{}, Actions: []contract.Action{}, References: []contract.Reference{},
	}
	result := eval.CheckExpectations(c, draft)
	if result.RiskMatch || result.Passed {
		t.Fatal("A01 must fail on unexpected warning")
	}
}

func TestC03MissingWarningStillFails(t *testing.T) {
	c := findCase(t, "C03_high_monthly_payment")
	draft := contract.AssistantAnswerDraftDTO{
		Title: "t", Body: "b", Answer: "a",
		Warnings: []contract.Warning{}, CitedFactKeys: []string{}, Unknowns: []string{},
		KeyFacts: []contract.KeyFact{}, Actions: []contract.Action{}, References: []contract.Reference{},
	}
	result := eval.CheckExpectations(c, draft)
	if result.RiskMatch {
		t.Fatal("C03 must fail when warning missing")
	}
}

func TestF06WarningStillFails(t *testing.T) {
	c := findCase(t, "F06_no_warning_expected")
	draft := contract.AssistantAnswerDraftDTO{
		Title: "t", Body: "b", Answer: "a",
		Warnings:      []contract.Warning{{Severity: "warning", Title: "w", Message: "m", Source: "availableCash"}},
		CitedFactKeys: []string{}, Unknowns: []string{},
		KeyFacts: []contract.KeyFact{}, Actions: []contract.Action{}, References: []contract.Reference{},
	}
	result := eval.CheckExpectations(c, draft)
	if result.Passed {
		t.Fatal("F06 must fail on unnecessary warning")
	}
}

func TestEvaluationVerdictClassification(t *testing.T) {
	r := eval.RunResult{
		EndToEndPass: false, ContractPass: true,
		FailureClass: eval.FailureSemanticRisk,
		AuditVerdict: eval.SemanticAuditVerdict{Verdict: eval.VerdictModelError},
	}
	if eval.ResolveEvaluationVerdict(r) != eval.EvaluationVerdictConfirmedModelFailure {
		t.Fatal("expected confirmed model failure")
	}
}

func TestReadinessFalsePositiveZero(t *testing.T) {
	audit := eval.PilotAuditReport{EvaluatorFalsePositives: 0}
	if !eval.AssessEvaluationReadiness(audit).Ready {
		t.Fatal("should be ready when FP=0")
	}
}

func TestPilotHasSevenCases(t *testing.T) {
	opts := eval.PilotFilterOptions()
	cases, err := eval.FilterCases(eval.AllCases(), opts)
	if err != nil || len(cases) != 7 {
		t.Fatalf("pilot cases: %d err=%v", len(cases), err)
	}
}

func TestPilotTotalRunsMatchesExpansion(t *testing.T) {
	opts := eval.PilotFilterOptions()
	cases, err := eval.FilterCases(eval.AllCases(), opts)
	if err != nil {
		t.Fatalf("FilterCases: %v", err)
	}
	expanded := eval.CountRuns(cases)
	expected, err := eval.ExpectedPilotRuns()
	if err != nil {
		t.Fatalf("ExpectedPilotRuns: %v", err)
	}
	if expanded != expected {
		t.Fatalf("pilot run expansion mismatch: got %d expected %d", expanded, expected)
	}
}

func TestDatasetSummaryCounts(t *testing.T) {
	summary, err := eval.BuildDatasetSummary()
	if err != nil {
		t.Fatalf("BuildDatasetSummary: %v", err)
	}
	if summary.DatasetCases != 29 || summary.PilotCases != 7 || summary.FullRuns != 37 || summary.PilotRuns != 15 {
		t.Fatalf("unexpected dataset summary: %+v", summary)
	}
}

func TestFullDatasetTotalRuns37(t *testing.T) {
	if eval.CountRuns(eval.AllCases()) != 37 {
		t.Fatal("expected 37 total runs for full dataset")
	}
}

func b01StructuredDraft() contract.AssistantAnswerDraftDTO {
	return contract.AssistantAnswerDraftDTO{
		Title: "t", Body: "b", Answer: "a",
		CitedFactKeys: []string{"minimumBalance", "safeBalance"},
		KeyFacts: []contract.KeyFact{
			{Label: "最低", Source: "minimumBalance", Kind: "balance", Value: contract.KeyFactValue{Type: "money", Amount: floatPtr(800), CurrencyCode: strPtr("CNY")}},
			{Label: "安全", Source: "safeBalance", Kind: "balance", Value: contract.KeyFactValue{Type: "money", Amount: floatPtr(2000), CurrencyCode: strPtr("CNY")}},
		},
		Warnings:   []contract.Warning{{Severity: "warning", Title: "w", Message: "m", Source: "minimumBalance"}},
		Unknowns:   []string{},
		Actions:    []contract.Action{},
		References: []contract.Reference{},
	}
}

func floatPtr(v float64) *float64 { return &v }

func strPtr(s string) *string { return &s }
