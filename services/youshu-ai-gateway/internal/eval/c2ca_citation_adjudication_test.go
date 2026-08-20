package eval

import (
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/factpack"
	"github.com/youshu/youshu-ai-gateway/internal/prompt"
	"github.com/youshu/youshu-ai-gateway/internal/smoke"
)

func TestC2CAProductionAllowsMonthlyDebtPaymentCitationForC01(t *testing.T) {
	c, err := findCaseByID(C2CCaseC01)
	if err != nil {
		t.Fatal(err)
	}
	facts := c.Envelope.MonthlySummaryFacts
	assessment := c.Envelope.FinancialRiskAssessment
	keySets := factpack.BuildKeySetsForRequest(facts, assessment)

	if !containsEvalKey(keySets.AllowedFactKeys, "monthlyDebtPayment") {
		t.Fatal("monthlyDebtPayment must remain registered in AllowedFactKeys")
	}
	if containsEvalKey(keySets.AllowedKeyFactKeys, "monthlyDebtPayment") {
		t.Fatal("monthlyDebtPayment must be excluded from AllowedKeyFactKeys for knownNoDebt")
	}

	draft := contract.AssistantAnswerDraftDTO{
		Title:         "t",
		Body:          "b",
		Answer:        "a",
		CitedFactKeys: []string{"monthlyDebtPayment", "monthlyIncome"},
		KeyFacts:      []contract.KeyFact{},
	}
	diag := smoke.DiagnoseFactsWithKeySets(draft, facts, keySets)
	if !diag.Passed || !diag.CitedFactKeysValid {
		t.Fatalf("production fact validation must allow citedFactKeys monthlyDebtPayment: %+v", diag)
	}

	schema, err := prompt.BuildAssistantAnswerSchema(mustModelSchema(t), keySets, prompt.BuildExplanationSchemaKeys(assessment))
	if err != nil {
		t.Fatal(err)
	}
	raw := []byte(`{"title":"t","body":"b","answer":"a","citedFactKeys":["monthlyDebtPayment"],"confidence":0.9,"keyFacts":[],"references":[],"riskExplanations":[],"unknownExplanations":[]}`)
	if err := prompt.ValidateDraftJSONWithSchema(raw, schema); err != nil {
		t.Fatal("dynamic schema must allow citedFactKeys monthlyDebtPayment for C01")
	}
}

func TestC2CAEvaluatorCitationAndKeyFactScopesSplit(t *testing.T) {
	c, err := findCaseByID(C2CCaseC01)
	if err != nil {
		t.Fatal(err)
	}
	citationDraft := contract.AssistantAnswerDraftDTO{
		Title: "t", Body: "b", Answer: "a",
		CitedFactKeys: []string{"monthlyIncome", "monthlyDebtPayment"},
		KeyFacts: []contract.KeyFact{
			{Source: "monthlyIncome", Kind: "income", Label: "income", Value: contract.KeyFactValue{Type: "money"}},
		},
	}
	citationResult := CheckExpectations(c, citationDraft)
	if !citationResult.CitationSemanticPass || !citationResult.Passed {
		t.Fatalf("post-C2CB C01 citation must PASS: %+v", citationResult)
	}

	keyFactOnlyDraft := contract.AssistantAnswerDraftDTO{
		Title: "t", Body: "b", Answer: "a",
		CitedFactKeys: []string{"monthlyIncome"},
		KeyFacts: []contract.KeyFact{
			{Source: "monthlyDebtPayment", Kind: "debt", Label: "debt", Value: contract.KeyFactValue{Type: "money"}},
		},
	}
	keyFactResult := CheckExpectations(c, keyFactOnlyDraft)
	if keyFactResult.KeyFactSelectionSemanticPass || keyFactResult.Passed {
		t.Fatalf("post-C2CB C01 keyFact must FAIL: %+v", keyFactResult)
	}
}

func TestC2CAFrozenC01RunDiffOnlyMonthlyDebtPaymentCitation(t *testing.T) {
	report := loadC2CAFrozenReport(t)
	run1, ok := findC2CAFrozenRun(report, C2CCaseC01, 1)
	if !ok {
		t.Fatal("missing C01 run=1")
	}
	run2, ok := findC2CAFrozenRun(report, C2CCaseC01, 2)
	if !ok {
		t.Fatal("missing C01 run=2")
	}

	run1Keys := citationSortedCopy(run1.StructuredSnapshot.CitedFactKeys)
	run2Keys := citationSortedCopy(run2.StructuredSnapshot.CitedFactKeys)
	added, removed := citationSetDiff(run1Keys, run2Keys)
	if len(removed) != 0 {
		t.Fatalf("unexpected removed citations: %v", removed)
	}
	if len(added) != 1 || added[0] != "monthlyDebtPayment" {
		t.Fatalf("expected only monthlyDebtPayment added, got added=%v run1=%v run2=%v", added, run1Keys, run2Keys)
	}

	if run1.EndToEndPass != true || run2.EndToEndPass != false {
		t.Fatalf("run1 e2e=%t run2 e2e=%t", run1.EndToEndPass, run2.EndToEndPass)
	}
	if run2.FailureClass != FailureFactReference {
		t.Fatalf("run2 failureClass=%s", run2.FailureClass)
	}
	if run2.Semantic.FactKeyCompliancePass {
		t.Fatal("run2 must fail FactKeyCompliance via ForbiddenFactKeys")
	}
	if run2.ContractStages.FactValidation != "pass" {
		t.Fatalf("run2 production FactValidation=%s", run2.ContractStages.FactValidation)
	}

	for _, key := range []string{"primaryPressure", "monthlyIncome", "monthlyExpense", "availableCash", "estimatedMonthEndBalance"} {
		if !citationContains(run1Keys, key) && !citationContains(run2Keys, key) {
			continue
		}
		c, err := findCaseByID(C2CCaseC01)
		if err != nil {
			t.Fatal(err)
		}
		if citationContains(c.ForbiddenFactKeys, key) {
			t.Fatalf("%s is forbidden but present in both runs", key)
		}
	}
}

func TestC2CAC01MonthlyDebtPaymentIsKnownZero(t *testing.T) {
	c, err := findCaseByID(C2CCaseC01)
	if err != nil {
		t.Fatal(err)
	}
	if ResolveDebtPaymentAvailability(c) != MoneyKnownZero {
		t.Fatalf("availability=%s want knownZero", ResolveDebtPaymentAvailability(c))
	}
	amount := c.Envelope.MonthlySummaryFacts.MonthlyDebtPayment.Amount
	if !isKnownZeroAmount(amount) {
		t.Fatalf("amount=%q want known zero", amount)
	}
	debt := AnalyzeDebtFacts(c)
	if !debt.DebtFactsKnownZero {
		t.Fatal("C01 debt facts must be known zero")
	}
}

func TestC2CAAdjudicateC01Run2AsHistoricalEvaluatorFalsePositive(t *testing.T) {
	report := loadC2CAFrozenReport(t)
	run2, ok := findC2CAFrozenRun(report, C2CCaseC01, 2)
	if !ok {
		t.Fatal("missing C01 run=2")
	}
	c, err := findCaseByID(C2CCaseC01)
	if err != nil {
		t.Fatal(err)
	}

	verdict := AdjudicateC01CitationRun(run2, c)
	if verdict.Owner != CitationAdjudicationEvaluatorFalsePositive {
		t.Fatalf("historical owner=%s want evaluatorFalsePositive", verdict.Owner)
	}
	if !verdict.ProductionCitationAllowed {
		t.Fatal("production citation contract allows monthlyDebtPayment for C01")
	}
	if verdict.KeyFactSelectionPass != true {
		t.Fatal("run2 keyFact selection must pass")
	}
	if EvaluatorForbiddenFactKeysScopeCreep(c) {
		t.Fatal("post-C2CB evaluator must no longer exhibit citation scope creep")
	}
}

func TestC2CACorrectedC2CCounts(t *testing.T) {
	report := loadC2CAFrozenReport(t)
	corrected := CorrectC2CCitationAdjudication(report)
	if corrected.KeyFactArchitectureReadiness != ReadinessPass {
		t.Fatalf("keyFact readiness=%s", corrected.KeyFactArchitectureReadiness)
	}
	if corrected.CorrectedE2EReadiness != ReadinessPass {
		t.Fatalf("corrected e2e=%s", corrected.CorrectedE2EReadiness)
	}
	if corrected.EvaluatorFalsePositives != 1 {
		t.Fatalf("evaluatorFP=%d want 1", corrected.EvaluatorFalsePositives)
	}
	if corrected.ConfirmedModelFailures != 0 {
		t.Fatalf("confirmedModelFailures=%d want 0", corrected.ConfirmedModelFailures)
	}
	if corrected.EvaluationContractGaps != 0 {
		t.Fatalf("contractGaps=%d want 0 post-C2CB", corrected.EvaluationContractGaps)
	}
}

func loadC2CAFrozenReport(t *testing.T) EvaluationReport {
	t.Helper()
	path := DefaultOutputDir + "/c2c-keyfact-targeted-20260817-074139.json"
	report, err := LoadReport(path)
	if err != nil {
		t.Skipf("frozen C2C artifact unavailable: %v", err)
	}
	return report
}

func findC2CAFrozenRun(report EvaluationReport, caseID string, runIndex int) (RunResult, bool) {
	for _, r := range report.Results {
		if r.CaseID == caseID && r.RunIndex == runIndex {
			return r, true
		}
	}
	return RunResult{}, false
}

func mustModelSchema(t *testing.T) []byte {
	t.Helper()
	raw, err := prompt.LoadAssistantAnswerModelDraftSchema()
	if err != nil {
		t.Fatal(err)
	}
	return raw
}

func citationSortedCopy(items []string) []string {
	out := append([]string(nil), items...)
	for i := 0; i < len(out); i++ {
		for j := i + 1; j < len(out); j++ {
			if out[j] < out[i] {
				out[i], out[j] = out[j], out[i]
			}
		}
	}
	return out
}

func citationSetDiff(before, after []string) (added, removed []string) {
	b := map[string]struct{}{}
	a := map[string]struct{}{}
	for _, k := range before {
		b[k] = struct{}{}
	}
	for _, k := range after {
		a[k] = struct{}{}
	}
	for k := range a {
		if _, ok := b[k]; !ok {
			added = append(added, k)
		}
	}
	for k := range b {
		if _, ok := a[k]; !ok {
			removed = append(removed, k)
		}
	}
	added = citationSortedCopy(added)
	removed = citationSortedCopy(removed)
	return added, removed
}

func citationContains(items []string, target string) bool {
	for _, item := range items {
		if item == target {
			return true
		}
	}
	return false
}
