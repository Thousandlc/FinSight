package eval

import (
	"reflect"
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/factpack"
	"github.com/youshu/youshu-ai-gateway/internal/smoke"
)

func TestC2AFrozenArtifactThreeFailures(t *testing.T) {
	report := loadC2AFrozenReport(t)
	if report.Metadata.TotalRuns != 37 {
		t.Fatalf("totalRuns=%d want 37", report.Metadata.TotalRuns)
	}

	c01, ok := findC2AFrozenRun(report, "C01_no_debt", 1)
	if !ok {
		t.Fatal("missing C01 run=1")
	}
	if c01.ContractStages.FactValidation != "pass" {
		t.Fatalf("C01 FactValidation=%s want pass", c01.ContractStages.FactValidation)
	}
	if c01.Semantic.FactKeyCompliancePass {
		t.Fatal("C01 expected FactKeyCompliance fail")
	}

	c04, ok := findC2AFrozenRun(report, "C04_multiple_debts", 1)
	if !ok {
		t.Fatal("missing C04 run=1")
	}
	if c04.ContractStages.FactValidation != "fail" || c04.InvalidKeyFactSource != 1 {
		t.Fatalf("C04 FactValidation=%s invalidKeyFactSource=%d", c04.ContractStages.FactValidation, c04.InvalidKeyFactSource)
	}

	e01, ok := findC2AFrozenRun(report, "E01_partial_debt_data", 1)
	if !ok {
		t.Fatal("missing E01 run=1")
	}
	if e01.ContractStages.FactValidation != "fail" || e01.InvalidKeyFactSource != 1 {
		t.Fatalf("E01 run1 FactValidation=%s invalidKeyFactSource=%d", e01.ContractStages.FactValidation, e01.InvalidKeyFactSource)
	}
}

func TestC2AC01MonthlyDebtPaymentRegisteredButForbiddenAsKeyFact(t *testing.T) {
	c, err := findCaseByID("C01_no_debt")
	if err != nil {
		t.Fatal(err)
	}
	facts := c.Envelope.MonthlySummaryFacts
	amountKeys, factKeys, _ := smoke.AllowedKeys(facts)
	if _, ok := amountKeys["monthlyDebtPayment"]; !ok {
		t.Fatal("monthlyDebtPayment must be registered in FactPack amountKeys")
	}
	if facts.MonthlyDebtPayment.Amount != "0" {
		t.Fatalf("monthlyDebtPayment amount=%s want 0", facts.MonthlyDebtPayment.Amount)
	}
	if len(factKeys) == 0 && len(amountKeys) == 0 {
		t.Fatal("unexpected empty allowed keys")
	}

	draft := c2aDraftFromFrozenC01()
	keySets := factpack.BuildKeySetsForRequest(facts, c.Envelope.FinancialRiskAssessment)
	diag := smoke.DiagnoseFactsWithKeySets(draft, facts, keySets)
	if diag.Passed {
		t.Fatal("production FactValidation must fail for forbidden C01 keyFact after C2B")
	}
	if !c2aContainsString(diag.FailureRules, smoke.FactRuleKeyFactSourceNotAllowed) {
		t.Fatalf("expected keyFactSourceNotAllowed, rules=%s", diag.FailureRulesSummary())
	}
	semantic := CheckExpectations(c, draft)
	if semantic.KeyFactSelectionSemanticPass {
		t.Fatal("evaluation ForbiddenKeyFactSources should fail for salient monthlyDebtPayment")
	}
	if !semantic.CitationSemanticPass {
		t.Fatal("citation scope should allow registered known-zero monthlyDebtPayment")
	}
	v2 := CheckExplanationExpectationsV2(c, draft, true, true)
	if !v2.FinalValidatorPass {
		t.Fatal("FinalValidatorPass should be true when explanation/provenance/policy pass (FactKeyCompliance is separate)")
	}
	if v2.Passed {
		t.Fatal("v2 semantic should fail on forbidden-keyfact-source")
	}
}

func TestC2AC04ExactSourceSetDiff(t *testing.T) {
	c04, ok := findC2AFrozenRun(loadC2AFrozenReport(t), "C04_multiple_debts", 1)
	if !ok {
		t.Fatal("missing C04")
	}
	cited := map[string]struct{}{}
	for _, k := range c04.StructuredSnapshot.CitedFactKeys {
		cited[k] = struct{}{}
	}
	sources := map[string]struct{}{}
	for _, k := range c04.StructuredSnapshot.KeyFactSources {
		sources[k] = struct{}{}
	}
	var onlyCited []string
	for k := range cited {
		if _, ok := sources[k]; !ok {
			onlyCited = append(onlyCited, k)
		}
	}
	if len(onlyCited) != 1 || onlyCited[0] != "debtPressureLevel" {
		t.Fatalf("cited-only keys=%v want [debtPressureLevel]", onlyCited)
	}
}

func TestC2AC04InvalidKeyFactMoneySourceOnDTI(t *testing.T) {
	facts := c2aCaseFacts("C04_multiple_debts")
	if facts.DebtPressureLevel == nil || *facts.DebtPressureLevel != "high" {
		t.Fatalf("debtPressureLevel=%v want high", facts.DebtPressureLevel)
	}
	passDraft := c2aDraftC04PassPattern(facts)
	if diag := smoke.DiagnoseFacts(passDraft, facts); !diag.Passed {
		t.Fatalf("control pass draft failed: %s", diag.FailureRulesSummary())
	}
	failDraft := c2aDraftC04FailPattern(facts)
	diag := smoke.DiagnoseFacts(failDraft, facts)
	if diag.Passed || diag.InvalidKeyFactCount != 1 {
		t.Fatalf("expected single invalid keyFact, diag=%+v", diag)
	}
	if diag.InvalidFactRule != smoke.FactRuleInvalidKeyFactMoneySource {
		t.Fatalf("invalid rule=%s want %s", diag.InvalidFactRule, smoke.FactRuleInvalidKeyFactMoneySource)
	}
	if diag.InvalidFactKey != "debtPaymentToIncomePercent" {
		t.Fatalf("invalid key=%s want debtPaymentToIncomePercent", diag.InvalidFactKey)
	}
}

func TestC2AE01Run1VsPassControlDiff(t *testing.T) {
	report := loadC2AFrozenReport(t)
	run1, _ := findC2AFrozenRun(report, "E01_partial_debt_data", 1)
	run3, _ := findC2AFrozenRun(report, "E01_partial_debt_data", 3)

	if !reflect.DeepEqual(run1.StructuredSnapshot.KeyFactSources, []string{
		"availableCash", "estimatedMonthEndBalance", "monthlyIncome",
		"monthlyExpense", "monthlyDebtPayment", "debtPaymentToIncomePercent",
	}) {
		t.Fatalf("E01 run1 keyFactSources=%v", run1.StructuredSnapshot.KeyFactSources)
	}
	if reflect.DeepEqual(run1.StructuredSnapshot.KeyFactSources, run3.StructuredSnapshot.KeyFactSources) {
		t.Fatal("run1 and run3 should differ on keyFactSources")
	}
	if c2aContainsString(run3.StructuredSnapshot.KeyFactSources, "debtPaymentToIncomePercent") {
		t.Fatal("E01 run3 pass control omits DTI keyFact row")
	}

	facts := c2aCaseFacts("E01_partial_debt_data")
	failDiag := smoke.DiagnoseFacts(c2aDraftE01FailPattern(facts), facts)
	if failDiag.Passed {
		t.Fatal("E01 fail pattern should not pass FactValidation")
	}
	if failDiag.InvalidFactKey != "debtPaymentToIncomePercent" {
		t.Fatalf("missing source key=%s want debtPaymentToIncomePercent", failDiag.InvalidFactKey)
	}
	passDiag := smoke.DiagnoseFacts(c2aDraftE01PassPattern(facts), facts)
	if !passDiag.Passed {
		t.Fatalf("E01 pass control should pass FactValidation rules=%s", passDiag.FailureRulesSummary())
	}
}

func TestC2AAdjudicationVerdicts(t *testing.T) {
	report := loadC2AFrozenReport(t)
	corrected := map[string]string{
		"C01_no_debt:1":              "confirmedModelFailure",
		"C04_multiple_debts:1":       "confirmedModelFailure",
		"E01_partial_debt_data:1":    "confirmedModelFailure",
	}
	for key, want := range corrected {
		var caseID string
		var runIndex int
		switch key {
		case "C01_no_debt:1":
			caseID, runIndex = "C01_no_debt", 1
		case "C04_multiple_debts:1":
			caseID, runIndex = "C04_multiple_debts", 1
		case "E01_partial_debt_data:1":
			caseID, runIndex = "E01_partial_debt_data", 1
		}
		r, ok := findC2AFrozenRun(report, caseID, runIndex)
		if !ok {
			t.Fatalf("missing %s", key)
		}
		got := c2aCorrectedAdjudication(r)
		if got != want {
			t.Fatalf("%s corrected=%s want %s (frozen audit=%s evaluation=%s)", key, got, want, r.AuditVerdict.Verdict, r.EvaluationVerdict)
		}
	}
}

func TestC2AFactInventedClassificationMismatch(t *testing.T) {
	report := loadC2AFrozenReport(t)
	for _, id := range []string{"C04_multiple_debts", "E01_partial_debt_data"} {
		r, ok := findC2AFrozenRun(report, id, 1)
		if !ok {
			t.Fatalf("missing %s", id)
		}
		if r.FailureClass != FailureFact {
			t.Fatalf("%s failureClass=%s", id, r.FailureClass)
		}
		if r.InventedFacts != 0 || r.InvalidKeyFactSource != 1 {
			t.Fatalf("%s invented=%d invalidKeyFactSource=%d", id, r.InventedFacts, r.InvalidKeyFactSource)
		}
		if ClassifyContractFailureWithFactContext(r.ContractStages, r.InvalidKeyFactSource, r.InventedFacts) != FailureFactSourceCompliance {
			t.Fatal("contract classifier maps invalidKeyFactSource-only FactValidation fail to fact-source-compliance")
		}
	}
}

func TestC2AContractAssessedCount(t *testing.T) {
	report := loadC2AFrozenReport(t)
	assessed := 0
	for _, r := range report.Results {
		if r.ModelResponseAssessed {
			assessed++
		}
	}
	if assessed != 35 {
		t.Fatalf("modelResponseAssessed=%d want 35", assessed)
	}
}

func c2aCorrectedAdjudication(r RunResult) string {
	if r.EndToEndPass {
		return EvaluationVerdictPass
	}
	switch r.FailureClass {
	case FailureFactReference:
		return EvaluationVerdictConfirmedModelFailure
	case FailureFact:
		if r.InvalidKeyFactSource > 0 && r.InventedFacts == 0 {
			return EvaluationVerdictConfirmedModelFailure
		}
	}
	if r.ContractPass && !r.SemanticPass {
		return EvaluationVerdictConfirmedModelFailure
	}
	return EvaluationVerdictAmbiguous
}

func c2aContainsString(items []string, target string) bool {
	for _, item := range items {
		if item == target {
			return true
		}
	}
	return false
}
