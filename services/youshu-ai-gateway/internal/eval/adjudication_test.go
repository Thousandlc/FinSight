package eval_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/eval"
)

func TestE03CorrectedExpectationNotApplicable(t *testing.T) {
	c := findCase(t, "E03_no_budget")
	data := eval.AnalyzeInsufficientDataCase(c)
	if data.Classification != eval.DataNotApplicable {
		t.Fatalf("E03 should be not applicable, got %s", data.Classification)
	}
	if eval.ResolveUnknownExpectation(c) != eval.UnknownNotRequired {
		t.Fatal("E03 must use unknownNotRequired")
	}
}

func TestE04CorrectedExpectationOptionalAbsent(t *testing.T) {
	c := findCase(t, "E04_partial_facts_missing")
	data := eval.AnalyzeInsufficientDataCase(c)
	if data.Classification != eval.DataOptionalAbsent {
		t.Fatalf("E04 should be optionalAbsent, got %s", data.Classification)
	}
	if eval.ResolveUnknownExpectation(c) != eval.UnknownNotRequired {
		t.Fatal("E04 must use unknownNotRequired")
	}
}

func TestOfflineRescoreE03E04Pass(t *testing.T) {
	report := buildFullEvalFixtureReport()
	adj := eval.AdjudicateFullEvaluation(report, eval.AllCases())

	if !adj.E03Audit.OfflineRescorePassed {
		t.Fatalf("E03 offline rescore should pass: %s", adj.E03Audit.OfflineRescoreDetail)
	}
	if !adj.E04Audit.OfflineRescorePassed {
		t.Fatalf("E04 offline rescore should pass: %s", adj.E04Audit.OfflineRescoreDetail)
	}
	if adj.AdjudicatedMetrics.EvaluatorFalsePositives != 0 {
		t.Fatalf("adjudicated FP should be 0, got %d", adj.AdjudicatedMetrics.EvaluatorFalsePositives)
	}
}

func TestRawMetricsPreserved(t *testing.T) {
	report := buildFullEvalFixtureReport()
	adj := eval.AdjudicateFullEvaluation(report, eval.AllCases())
	if adj.RawMetrics.EvaluatorFalsePositives != 2 {
		t.Fatalf("raw FP should remain 2, got %d", adj.RawMetrics.EvaluatorFalsePositives)
	}
	if adj.RawMetrics.ExpectedRiskMatchRate <= 0 {
		t.Fatal("raw risk metrics should be preserved")
	}
}

func TestC01KnownZeroForbiddenFactKey(t *testing.T) {
	c := findCase(t, "C01_no_debt")
	r := eval.RunResult{
		CaseID: "C01_no_debt", RunIndex: 1,
		ContractPass: true, EndToEndPass: false,
		FailureClass: eval.FailureSemanticForbidden,
		FailureSeverity: eval.SeverityCritical,
		StructuredSnapshot: eval.StructuredSnapshot{
			CitedFactKeys:  []string{"monthlyDebtPayment", "availableCash"},
			KeyFactSources: []string{"monthlyDebtPayment"},
		},
	}
	audit := eval.AuditC01ForbiddenClaim(c, r)
	if !audit.DebtKnownZero {
		t.Fatal("C01 must be known zero debt")
	}
	if len(audit.ViolatedForbiddenFactKeys) == 0 {
		t.Fatal("expected violated forbidden fact key")
	}
	if !audit.ConfirmedSemanticHallucination {
		t.Fatal("C01 forbidden fact key on known-zero must be confirmed hallucination")
	}
	if audit.Severity != eval.SeverityCritical {
		t.Fatalf("expected critical severity, got %s", audit.Severity)
	}
	if !strings.Contains(strings.Join(audit.ReferencePaths, ","), "keyFacts.source:monthlyDebtPayment") {
		t.Fatalf("expected keyFacts source path, got %v", audit.ReferencePaths)
	}
}

func TestContractVsScenarioSemanticSafety(t *testing.T) {
	report := buildFullEvalFixtureReport()
	adj := eval.AdjudicateFullEvaluation(report, eval.AllCases())
	if !adj.ContractFactSafety.ContractFactSafetyPass {
		t.Fatal("contract fact safety should pass")
	}
	if adj.ScenarioSemanticSafety.ScenarioSemanticSafetyPass {
		t.Fatal("scenario semantic safety should fail due to C01 critical")
	}
	if adj.ScenarioSemanticSafety.MissingDataOverconfidenceCount == 0 {
		t.Fatal("missing data overconfidence should be counted separately from fabrication")
	}
}

func TestMissingOverconfidenceNotFabrication(t *testing.T) {
	report := buildFullEvalFixtureReport()
	adj := eval.AdjudicateFullEvaluation(report, eval.AllCases())
	if adj.ScenarioSemanticSafety.DataInsufficientFabricationCount != 0 {
		t.Fatalf("fabrication count should stay 0 when only unknowns empty, got %d",
			adj.ScenarioSemanticSafety.DataInsufficientFabricationCount)
	}
	if adj.ScenarioSemanticSafety.MissingDataOverconfidenceCount < 1 {
		t.Fatal("missing overconfidence should be >= 1")
	}
}

func TestIntegrationAndProductionReadiness(t *testing.T) {
	report := buildFullEvalFixtureReport()
	adj := eval.AdjudicateFullEvaluation(report, eval.AllCases())
	if adj.IntegrationReadiness != eval.ReadinessPass {
		t.Fatalf("integration readiness expected PASS, got %s", adj.IntegrationReadiness)
	}
	if adj.ProductionSemanticReadiness != eval.ReadinessFail {
		t.Fatalf("production semantic readiness expected FAIL, got %s", adj.ProductionSemanticReadiness)
	}
	if !adj.DeterministicRiskPolicyRecommended {
		t.Fatal("should recommend deterministic risk policy when semantic fails")
	}
}

func TestAdjudicateSummarySections(t *testing.T) {
	report := buildFullEvalFixtureReport()
	adj := eval.AdjudicateFullEvaluation(report, eval.AllCases())
	for _, section := range []string{
		"E03 no_budget", "E04 partial_facts_missing", "C01 no_debt",
		"Contract Fact Safety", "Scenario Semantic Safety",
		"Raw vs Adjudicated", "IntegrationReadiness",
	} {
		if !strings.Contains(adj.SummaryText, section) {
			t.Fatalf("missing section %q in summary", section)
		}
	}
}

func TestAdjudicateFullEval(t *testing.T) {
	report := buildFullEvalFixtureReport()
	adj := eval.AdjudicateFullEvaluation(report, eval.AllCases())
	t.Log(adj.SummaryText)
}

func TestAdjudicateFromLatestJSONIfPresent(t *testing.T) {
	path := filepath.Join("..", "..", ".eval-output", "latest.json")
	if _, err := os.Stat(path); err != nil {
		t.Skip("latest.json not present; skipping live report adjudication")
	}
	adj, err := eval.LoadAndAdjudicateReport(path)
	if err != nil {
		t.Fatalf("LoadAndAdjudicateReport: %v", err)
	}
	if adj.AdjudicatedMetrics.EvaluatorFalsePositives != 0 {
		t.Fatalf("adjudicated FP must be 0 after E03/E04 fix, got %d", adj.AdjudicatedMetrics.EvaluatorFalsePositives)
	}
	t.Log(adj.SummaryText)
}

func buildFullEvalFixtureReport() eval.EvaluationReport {
	makeRiskFail := func(caseID, category string, run int, expected eval.RiskLevel, direction string, actual eval.RiskLevel) eval.RunResult {
		snap := eval.StructuredSnapshot{
			ExpectedRiskLevel:     expected,
			ActualDerivedRisk:     actual,
			RiskMismatchDirection: direction,
		}
		if actual != eval.RiskLevelNone {
			snap.WarningCount = 1
			snap.WarningSeverities = []string{"warning"}
		}
		return eval.RunResult{
			CaseID: caseID, Category: category, RunIndex: run,
			ContractPass: true, SemanticPass: false, EndToEndPass: false,
			FailureClass: eval.FailureSemanticRisk, FailureSeverity: eval.SeverityMajor,
			RiskMatch: false,
			Semantic: eval.SemanticResult{RiskMismatchDirection: direction, RiskMatch: false},
			EvaluationVerdict: eval.EvaluationVerdictConfirmedModelFailure,
			AuditVerdict: eval.SemanticAuditVerdict{Verdict: eval.VerdictModelError},
			StructuredSnapshot: snap,
			ContractStages: eval.ContractStages{
				HTTPSuccess: true, ContentJSONValid: true, DraftDTODecode: "pass",
				GatewaySchemaValidation: "pass", FactValidation: "pass",
			},
		}
	}

	var results []eval.RunResult
	addPass := func(caseID, category string, run int) {
		results = append(results, eval.RunResult{
			CaseID: caseID, Category: category, RunIndex: run,
			ContractPass: true, SemanticPass: true, EndToEndPass: true,
			RiskMatch: true, UnknownBehaviorPass: true,
			EvaluationVerdict: eval.EvaluationVerdictPass,
			ContractStages: eval.ContractStages{
				HTTPSuccess: true, ContentJSONValid: true, DraftDTODecode: "pass",
				GatewaySchemaValidation: "pass", FactValidation: "pass",
			},
		})
	}

	// Core repeat failures from full eval
	for run := 1; run <= 3; run++ {
		results = append(results, makeRiskFail("A01_healthy_cashflow", eval.CategoryHealthyFinance, run,
			eval.RiskLevelNone, eval.RiskMismatchUnexpectedWarning, eval.RiskLevelWarning))
	}
	for run := 1; run <= 3; run++ {
		results = append(results, makeRiskFail("C03_high_monthly_payment", eval.CategoryDebt, run,
			eval.RiskLevelWarning, eval.RiskMismatchMissingWarning, eval.RiskLevelNone))
	}
	addPass("B01_minimum_below_safe", eval.CategoryCashFlowRisk, 1)
	addPass("B01_minimum_below_safe", eval.CategoryCashFlowRisk, 2)
	addPass("B01_minimum_below_safe", eval.CategoryCashFlowRisk, 3)

	// Evaluator false positives (raw)
	results = append(results, eval.RunResult{
		CaseID: "E03_no_budget", Category: eval.CategoryInsufficientData, RunIndex: 1,
		ContractPass: true, SemanticPass: false, EndToEndPass: false,
		FailureClass: eval.FailureSemanticUnknown, UnknownBehaviorPass: false,
		EvaluationVerdict: eval.EvaluationVerdictEvaluatorFalsePositive,
		AuditVerdict: eval.SemanticAuditVerdict{Verdict: eval.VerdictEvaluatorFalsePositive, DatasetExpectationBug: true},
		StructuredSnapshot: eval.StructuredSnapshot{UnknownCount: 0, UnknownExpectation: string(eval.UnknownRequired)},
		ContractStages: eval.ContractStages{HTTPSuccess: true, ContentJSONValid: true, DraftDTODecode: "pass", GatewaySchemaValidation: "pass", FactValidation: "pass"},
	})
	results = append(results, eval.RunResult{
		CaseID: "E04_partial_facts_missing", Category: eval.CategoryInsufficientData, RunIndex: 1,
		ContractPass: true, SemanticPass: false, EndToEndPass: false,
		FailureClass: eval.FailureSemanticUnknown, UnknownBehaviorPass: false,
		EvaluationVerdict: eval.EvaluationVerdictEvaluatorFalsePositive,
		AuditVerdict: eval.SemanticAuditVerdict{Verdict: eval.VerdictEvaluatorFalsePositive, DatasetExpectationBug: true},
		StructuredSnapshot: eval.StructuredSnapshot{UnknownCount: 0, UnknownExpectation: string(eval.UnknownRequired)},
		ContractStages: eval.ContractStages{HTTPSuccess: true, ContentJSONValid: true, DraftDTODecode: "pass", GatewaySchemaValidation: "pass", FactValidation: "pass"},
	})

	// C01 critical
	results = append(results, eval.RunResult{
		CaseID: "C01_no_debt", Category: eval.CategoryDebt, RunIndex: 1,
		ContractPass: true, SemanticPass: false, EndToEndPass: false,
		FailureClass: eval.FailureSemanticForbidden, FailureSeverity: eval.SeverityCritical,
		ForbiddenClaimCount: 1,
		EvaluationVerdict: eval.EvaluationVerdictConfirmedModelFailure,
		StructuredSnapshot: eval.StructuredSnapshot{
			CitedFactKeys:  []string{"monthlyDebtPayment", "availableCash"},
			KeyFactSources: []string{"monthlyDebtPayment", "availableCash"},
		},
		Semantic: eval.SemanticResult{FactKeyCompliancePass: false},
		ContractStages: eval.ContractStages{HTTPSuccess: true, ContentJSONValid: true, DraftDTODecode: "pass", GatewaySchemaValidation: "pass", FactValidation: "pass"},
	})

	// E05 missing debt unknown fail
	results = append(results, eval.RunResult{
		CaseID: "E05_missing_debt_data", Category: eval.CategoryInsufficientData, RunIndex: 1,
		ContractPass: true, SemanticPass: false, EndToEndPass: false,
		FailureClass: eval.FailureSemanticUnknown, UnknownBehaviorPass: false,
		EvaluationVerdict: eval.EvaluationVerdictConfirmedModelFailure,
		StructuredSnapshot: eval.StructuredSnapshot{UnknownCount: 0},
		ContractStages: eval.ContractStages{HTTPSuccess: true, ContentJSONValid: true, DraftDTODecode: "pass", GatewaySchemaValidation: "pass", FactValidation: "pass"},
	})

	results = append(results, makeRiskFail("D02_zero_income_month", eval.CategoryIncomeExpense, 1,
		eval.RiskLevelWarning, eval.RiskMismatchMissingWarning, eval.RiskLevelNone))
	results = append(results, makeRiskFail("F06_no_warning_expected", eval.CategoryEdgeCase, 1,
		eval.RiskLevelNone, eval.RiskMismatchUnexpectedWarning, eval.RiskLevelWarning))

	// Fill remaining cases as passes to reach 37 runs
	for _, c := range eval.AllCases() {
		for run := 1; run <= c.Repeats; run++ {
			found := false
			for _, r := range results {
				if r.CaseID == c.ID && r.RunIndex == run {
					found = true
					break
				}
			}
			if !found {
				addPass(c.ID, c.Category, run)
			}
		}
	}

	// One timeout
	for i := range results {
		if results[i].CaseID == "A02_high_income_low_expense" && results[i].RunIndex == 1 {
			results[i] = eval.RunResult{
				CaseID: results[i].CaseID, Category: results[i].Category, RunIndex: 1,
				Timeout: true, FailureClass: eval.FailureTimeout, FailureSeverity: eval.SeverityMajor,
				EvaluationVerdict: eval.EvaluationVerdictAmbiguous,
				ContractStages: eval.ContractStages{TimeoutStage: "upstreamHTTP"},
			}
		}
	}

	metrics := eval.ComputeMetrics(results, eval.EvaluationModeExplanationAlignmentV2)
	metrics.ExpectedRiskMatchCount = 20
	metrics.UnknownBehaviorPassCount = 32
	metrics.ForbiddenClaimCount = 1
	metrics.HTTPSuccessCount = 36
	metrics.ContractAmongHTTPSuccesses = 36
	metrics.JSONValidCount = 36
	metrics.ModelDTODecodeCount = 36
	metrics.SchemaSuccessCount = 36
	metrics.FactValidationCount = 36

	analysis := eval.AnalyzeFullEvaluation(results, eval.AllCases(), metrics, eval.EvaluationModeExplanationAlignmentV2)
	analysis.RiskMismatchDirections = map[string]int{
		eval.RiskMismatchMissingWarning:    10,
		eval.RiskMismatchOverclassified:    3,
		eval.RiskMismatchUnexpectedWarning: 3,
	}
	analysis.ConfirmedModelFailures = 19
	analysis.EvaluatorFalsePositives = 2

	return eval.EvaluationReport{
		Metadata: eval.RunMetadata{
			TotalCases: 29, TotalRuns: 37,
			ConfiguredModel: "qwen3.7-plus", StructuredOutputMode: "json_schema_strict",
		},
		Results:  results,
		Metrics:  metrics,
		Analysis: analysis,
	}
}

func TestDraftFromSnapshotRescore(t *testing.T) {
	c := findCase(t, "E03_no_budget")
	snap := eval.StructuredSnapshot{UnknownCount: 0}
	result := eval.RescoreRunOffline(c, snap)
	if !result.UnknownBehaviorPass || !result.Passed {
		t.Fatalf("E03 with corrected expectation should pass rescore: %+v", result)
	}
}

func TestValidateInsufficientDataSemantics(t *testing.T) {
	if err := eval.ValidateInsufficientDataSemantics(eval.AllCases()); err != nil {
		t.Fatalf("ValidateInsufficientDataSemantics: %v", err)
	}
}

func TestC01ForbiddenClaimDoesNotUseNarrative(t *testing.T) {
	c := findCase(t, "C01_no_debt")
	draft := contract.AssistantAnswerDraftDTO{
		Title: "t", Body: "b", Answer: "a",
		CitedFactKeys: []string{"monthlyDebtPayment"},
		KeyFacts: []contract.KeyFact{{
			Source: "monthlyDebtPayment", Kind: "debt", Label: "debt",
			Value: contract.KeyFactValue{Type: "money"},
		}},
		Unknowns: []string{}, Warnings: []contract.Warning{},
		Actions: []contract.Action{}, References: []contract.Reference{},
	}
	result := eval.CheckExpectations(c, draft)
	if result.Passed {
		t.Fatal("C01 must fail when forbidden fact key cited")
	}
}
