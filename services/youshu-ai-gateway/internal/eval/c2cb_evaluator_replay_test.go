package eval

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/factpack"
	"github.com/youshu/youshu-ai-gateway/internal/smoke"
)

func TestC2CBC01CitationMonthlyDebtPaymentPass(t *testing.T) {
	if reg := evaluateC01CitationPairRegression(); !reg.Passed {
		t.Fatal(reg.Detail)
	}
}

func TestC2CBC01KeyFactMonthlyDebtPaymentFail(t *testing.T) {
	if reg := evaluateC01KeyFactPairRegression(); !reg.Passed {
		t.Fatal(reg.Detail)
	}
}

func TestC2CBLegacyForbiddenFactKeysCombinedSemantics(t *testing.T) {
	legacyCase := EvaluationCase{
		ID:                "legacy_probe",
		ForbiddenFactKeys: []string{"monthlyDebtPayment"},
	}
	scope := ResolveForbiddenScopes(legacyCase)
	if !scope.LegacyCombined {
		t.Fatal("legacy ForbiddenFactKeys must map to combined scopes")
	}
	if len(scope.KeyFactSources) != 1 || len(scope.CitationFactKeys) != 1 {
		t.Fatalf("legacy scope=%+v", scope)
	}
	draft := citationProbeDraft("monthlyDebtPayment")
	if checkForbiddenFactKeys(legacyCase.ForbiddenFactKeys, draft) {
		t.Fatal("legacy combined checker must fail citation")
	}
}

func TestC2CBExplicitScopePrecedenceOverLegacy(t *testing.T) {
	c, err := findCaseByID("C01_no_debt")
	if err != nil {
		t.Fatal(err)
	}
	scope := ResolveForbiddenScopes(c)
	if scope.LegacyCombined {
		t.Fatal("explicit migrated case must not use legacy combined mapping")
	}
	if len(scope.CitationFactKeys) != 0 {
		t.Fatalf("C01 citation scope must be empty, got %v", scope.CitationFactKeys)
	}
	if len(scope.KeyFactSources) != 1 || scope.KeyFactSources[0] != "monthlyDebtPayment" {
		t.Fatalf("C01 keyFact scope=%v", scope.KeyFactSources)
	}
}

func TestC2CBForbiddenScopeCaseMigrationAudit(t *testing.T) {
	expectations := map[string]struct {
		keyFacts  []string
		citations []string
	}{
		"C01_no_debt": {
			keyFacts:  []string{"monthlyDebtPayment"},
			citations: nil,
		},
		"E01_partial_debt_data": {
			keyFacts:  []string{"totalDebt", "estimatedDebtFreeDate"},
			citations: []string{"totalDebt", "estimatedDebtFreeDate"},
		},
		"E04_partial_facts_missing": {
			keyFacts:  []string{"safeBalance", "minimumBalance"},
			citations: []string{"safeBalance", "minimumBalance"},
		},
		"E05_missing_debt_data": {
			keyFacts:  []string{"debtPaymentToIncomePercent", "totalDebt", "estimatedDebtFreeDate", "monthlyDebtPayment"},
			citations: []string{"debtPaymentToIncomePercent", "totalDebt", "estimatedDebtFreeDate", "monthlyDebtPayment"},
		},
	}
	for id, want := range expectations {
		c, err := findCaseByID(id)
		if err != nil {
			t.Fatalf("%s: %v", id, err)
		}
		scope := ResolveForbiddenScopes(c)
		if !stringSlicesEqual(scope.KeyFactSources, want.keyFacts) {
			t.Fatalf("%s keyFacts=%v want %v", id, scope.KeyFactSources, want.keyFacts)
		}
		if !stringSlicesEqual(scope.CitationFactKeys, want.citations) {
			t.Fatalf("%s citations=%v want %v", id, scope.CitationFactKeys, want.citations)
		}
	}
	if err := ValidateForbiddenScopeSemantics(AllCases()); err != nil {
		t.Fatal(err)
	}
}

func TestC2CBC03KnownDebtControl(t *testing.T) {
	c, err := findCaseByID("C03_high_monthly_payment")
	if err != nil {
		t.Fatal(err)
	}
	scope := ResolveForbiddenScopes(c)
	if len(scope.KeyFactSources) > 0 || len(scope.CitationFactKeys) > 0 {
		t.Fatalf("C03 must not declare forbidden scopes: %+v", scope)
	}
	draft := contract.AssistantAnswerDraftDTO{
		Title: "t", Body: "b", Answer: "a",
		CitedFactKeys: []string{"monthlyDebtPayment", "monthlyIncome"},
		KeyFacts: []contract.KeyFact{
			{Source: "monthlyDebtPayment", Kind: "debt", Label: "debt", Value: contract.KeyFactValue{Type: "money"}},
		},
	}
	result := CheckExpectations(c, draft)
	if !result.KeyFactSelectionSemanticPass || !result.CitationSemanticPass {
		t.Fatalf("C03 control should pass forbidden scopes: %+v", result)
	}
}

func TestC2CBE01PartialRegression(t *testing.T) {
	c, err := findCaseByID("E01_partial_debt_data")
	if err != nil {
		t.Fatal(err)
	}
	facts := c.Envelope.MonthlySummaryFacts
	passDraft := c2aDraftE01PassPattern(facts)
	if res := CheckExpectations(c, passDraft); !res.Passed {
		t.Fatalf("E01 pass pattern should pass evaluator scopes: %+v", res)
	}
	failDraft := passDraft
	failDraft.CitedFactKeys = append(failDraft.CitedFactKeys, "totalDebt")
	if res := CheckExpectations(c, failDraft); res.Passed || res.CitationSemanticPass {
		t.Fatal("E01 must fail forbidden citation for totalDebt")
	}
}

func TestC2CBE05UnregisteredCitationStillBlockedByProduction(t *testing.T) {
	c, err := findCaseByID("E05_missing_debt_data")
	if err != nil {
		t.Fatal(err)
	}
	draft := contract.AssistantAnswerDraftDTO{
		Title: "t", Body: "b", Answer: "a",
		CitedFactKeys: []string{"totalDebt"},
	}
	diag := smoke.DiagnoseFactsWithKeySets(draft, c.Envelope.MonthlySummaryFacts, factpack.BuildKeySetsForRequest(c.Envelope.MonthlySummaryFacts, c.Envelope.FinancialRiskAssessment))
	if diag.Passed {
		t.Fatal("production must still block unregistered totalDebt citation for E05")
	}

	debtDraft := contract.AssistantAnswerDraftDTO{
		Title: "t", Body: "b", Answer: "a",
		CitedFactKeys: []string{"monthlyDebtPayment"},
	}
	res := CheckExpectations(c, debtDraft)
	if res.CitationSemanticPass {
		t.Fatal("evaluator citation scope must fail E05 monthlyDebtPayment citation")
	}
}

func TestC2CBRiskProvenanceUnaffected(t *testing.T) {
	c, err := findCaseByID("C01_no_debt")
	if err != nil {
		t.Fatal(err)
	}
	draft := contract.AssistantAnswerDraftDTO{
		Title: "t", Body: "b", Answer: "a",
		CitedFactKeys: []string{"monthlyIncome", "monthlyDebtPayment"},
	}
	res := CheckExpectations(c, draft)
	if !res.CitationSemanticPass || !res.Passed {
		t.Fatalf("top-level citation scope must pass registered known-zero monthlyDebtPayment: %+v", res)
	}
}

func TestC2CBReferencesUnaffected(t *testing.T) {
	c := EvaluationCase{
		ID:                  "ref_probe",
		ForbiddenReferences: []string{"debtDetail"},
	}
	draft := contract.AssistantAnswerDraftDTO{
		Title: "t", Body: "b", Answer: "a",
		References: []contract.Reference{{Key: "debtDetail"}},
	}
	res := CheckExpectations(c, draft)
	if res.ReferenceCompliancePass {
		t.Fatal("reference restriction must remain independent from citation scope")
	}
}

func TestC2CBEvaluatorVersionIdentity(t *testing.T) {
	id := CurrentEvaluatorIdentity()
	if id.EvaluatorVersion != EvaluatorVersionPostC2CB {
		t.Fatalf("version=%s", id.EvaluatorVersion)
	}
	if id.EvaluatorFingerprint != EvaluatorFingerprintPostC2CB {
		t.Fatalf("fingerprint=%s", id.EvaluatorFingerprint)
	}
}

func TestC2CBFactSourceComplianceClassification(t *testing.T) {
	got := ClassifyFactValidationFailure(1, 0)
	if got != FailureFactSourceCompliance {
		t.Fatalf("got=%s want %s", got, FailureFactSourceCompliance)
	}
	got = ClassifyFactValidationFailure(0, 1)
	if got != FailureFact {
		t.Fatalf("got=%s want %s", got, FailureFact)
	}
}

func TestC2CBContractStageAuditNoteFactValidation(t *testing.T) {
	note := contractStageAuditNote(ContractStages{FactValidation: "fail"})
	if note == "" || note == "transport/provider failure; semantic stages not assessed" {
		t.Fatalf("note=%q", note)
	}
}

func TestC2CBFrozenC01RunsReplayWhenArtifactAvailable(t *testing.T) {
	path := filepath.Join(DefaultOutputDir, c2cbFrozenC2CArtifactName)
	if _, err := os.Stat(path); err != nil {
		t.Skipf("frozen C2C artifact unavailable: %v", err)
	}
	raw, replayed, err := ReplayFrozenC2CReport(DefaultOutputDir)
	if err != nil {
		t.Fatal(err)
	}
	if replayed.EvaluatorVersion != EvaluatorVersionPostC2CB {
		t.Fatalf("evaluatorVersion=%s", replayed.EvaluatorVersion)
	}
	pass := 0
	for _, r := range replayed.Results {
		if r.EndToEndPass {
			pass++
		}
	}
	if pass != len(replayed.Results) {
		t.Fatalf("C2C replay=%d/%d", pass, len(replayed.Results))
	}
	for _, runIndex := range []int{1, 2} {
		_, ok := findC2CAFrozenRunFromReport(raw, C2CCaseC01, runIndex)
		if !ok {
			t.Fatalf("missing C01 run=%d", runIndex)
		}
		replayRun, ok := findC2CAFrozenRunFromReport(replayed, C2CCaseC01, runIndex)
		if !ok {
			t.Fatalf("missing replay C01 run=%d", runIndex)
		}
		if !replayRun.EndToEndPass {
			t.Fatalf("C01 run=%d replay e2e=false class=%s", runIndex, replayRun.FailureClass)
		}
	}
}

func TestC2CBFrozenC2ReplayWhenArtifactAvailable(t *testing.T) {
	path := filepath.Join(DefaultOutputDir, c2cbFrozenC2ArtifactName)
	if _, err := os.Stat(path); err != nil {
		t.Skipf("frozen C2 artifact unavailable: %v", err)
	}
	raw, replayed, err := ReplayFrozenC2Report(DefaultOutputDir)
	if err != nil {
		t.Fatal(err)
	}
	c01Raw, _ := findC2CAFrozenRunFromReport(raw, "C01_no_debt", 1)
	c01Replay, _ := findC2CAFrozenRunFromReport(replayed, "C01_no_debt", 1)
	t.Logf("C01 run1 raw e2e=%t replay e2e=%t rawClass=%s replayClass=%s",
		c01Raw.EndToEndPass, c01Replay.EndToEndPass, c01Raw.FailureClass, c01Replay.FailureClass)
	if replayed.EvaluatorVersion != EvaluatorVersionPostC2CB {
		t.Fatalf("evaluatorVersion=%s", replayed.EvaluatorVersion)
	}
}

func TestC2CBEvaluatorScopeCreepClosed(t *testing.T) {
	c, err := findCaseByID("C01_no_debt")
	if err != nil {
		t.Fatal(err)
	}
	if EvaluatorForbiddenFactKeysScopeCreep(c) {
		t.Fatal("post-C2CB must not report citation scope creep for C01")
	}
}

func TestC2CB29CaseExpectationsLoad(t *testing.T) {
	if err := ValidateDataset(AllCases()); err != nil {
		t.Fatal(err)
	}
}

func TestC2CBWriteReplayArtifactOutput(t *testing.T) {
	result, err := BuildC2CBReplayResult(DefaultOutputDir)
	if err != nil {
		t.Fatal(err)
	}
	if !result.C01CitationRegression.Passed || !result.C01KeyFactRegression.Passed {
		t.Fatalf("pair regressions citation=%+v keyFact=%+v", result.C01CitationRegression, result.C01KeyFactRegression)
	}
	path, err := WriteC2CBReplayArtifact(result, DefaultOutputDir)
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("replay artifact: %s", path)
}

func findC2CAFrozenRunFromReport(report EvaluationReport, caseID string, runIndex int) (RunResult, bool) {
	for _, r := range report.Results {
		if r.CaseID == caseID && r.RunIndex == runIndex {
			return r, true
		}
	}
	return RunResult{}, false
}

func stringSlicesEqual(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	am := map[string]struct{}{}
	for _, v := range a {
		am[v] = struct{}{}
	}
	for _, v := range b {
		if _, ok := am[v]; !ok {
			return false
		}
	}
	return true
}
