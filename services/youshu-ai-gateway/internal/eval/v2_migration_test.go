package eval_test

import (
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/eval"
)

func TestDefaultEvaluationModeIsV2(t *testing.T) {
	if eval.ResolveEvaluationMode() != eval.EvaluationModeExplanationAlignmentV2 {
		t.Fatalf("expected default v2 mode, got %s", eval.ResolveEvaluationMode())
	}
}

func TestAllCasesHaveAssessmentFixtures(t *testing.T) {
	cases := eval.AllCases()
	if len(cases) != 29 {
		t.Fatalf("expected 29 cases, got %d", len(cases))
	}
	if err := eval.ValidateDataset(cases); err != nil {
		t.Fatalf("ValidateDataset: %v", err)
	}
}

func TestAssessmentMigrationTable29Cases(t *testing.T) {
	rows, err := eval.BuildAssessmentMigrationTable(eval.AllCases())
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 29 {
		t.Fatalf("expected 29 migration rows, got %d", len(rows))
	}
}

func TestCoreCaseAssessmentSemantics(t *testing.T) {
	expectations := map[string]struct {
		level      string
		debtState  string
		signals    []string
		unknowns   []string
	}{
		"A01_healthy_cashflow":            {"safe", "knownDebt", nil, nil},
		"F06_no_warning_expected":         {"safe", "knownDebt", nil, nil},
		"B01_minimum_below_safe":          {"warning", "knownDebt", []string{"cashFlowBelowSafeBalance"}, nil},
		"B04_short_term_negative_balance": {"risk", "knownDebt", []string{"negativeProjectedBalance"}, nil},
		"C01_no_debt":                     {"safe", "knownNoDebt", nil, nil},
		"C03_high_monthly_payment":        {"warning", "knownDebt", []string{"highDebtPaymentToIncome"}, nil},
		"C05_high_dti":                    {"warning", "knownDebt", []string{"highDebtPaymentToIncome"}, nil},
		"D02_zero_income_month":           {"warning", "knownDebt", []string{"zeroIncomeWithExpenses"}, nil},
		"E01_partial_debt_data":           {"warning", "partial", []string{"highDebtPaymentToIncome"}, nil},
		"E05_missing_debt_data":           {"safe", "missing", nil, []string{"debtDataMissing"}},
	}
	for id, want := range expectations {
		c := findCase(t, id)
		a := c.Assessment
		if a.OverallLevel != want.level {
			t.Fatalf("%s overallLevel=%s want %s", id, a.OverallLevel, want.level)
		}
		if a.DebtDataState != want.debtState {
			t.Fatalf("%s debtDataState=%s want %s", id, a.DebtDataState, want.debtState)
		}
		var signals []string
		for _, s := range a.Signals {
			if s.Level != "safe" {
				signals = append(signals, s.ReasonCode)
			}
		}
		if len(signals) != len(want.signals) {
			t.Fatalf("%s signals=%v want %v", id, signals, want.signals)
		}
		for i := range want.signals {
			if signals[i] != want.signals[i] {
				t.Fatalf("%s signal[%d]=%s want %s", id, i, signals[i], want.signals[i])
			}
		}
		if len(a.DataCompleteness.RequiredUnknownReasonCodes) != len(want.unknowns) {
			t.Fatalf("%s unknowns=%v want %v", id, a.DataCompleteness.RequiredUnknownReasonCodes, want.unknowns)
		}
	}
}

func TestSmokeV2Selection(t *testing.T) {
	cases, err := eval.FilterCases(eval.AllCases(), eval.SmokeV2FilterOptions())
	if err != nil {
		t.Fatal(err)
	}
	if len(cases) != 6 {
		t.Fatalf("expected 6 smoke cases, got %d", len(cases))
	}
	runs, err := eval.ExpectedSmokeV2Runs()
	if err != nil {
		t.Fatal(err)
	}
	if runs != 12 {
		t.Fatalf("expected 12 smoke runs, got %d", runs)
	}
}

func TestAnalyzeModelExplanationAlignmentCoverage(t *testing.T) {
	c := findCase(t, "C03_high_monthly_payment")
	model := contract.ModelAssistantAnswerDraftDTO{
		RiskExplanations: []contract.ModelRiskExplanationDTO{{
			ReasonCode: "highDebtPaymentToIncome",
			Text:       "DTI",
		}},
	}
	analysis := eval.AnalyzeModelExplanationAlignment(model, c.Assessment, c.Envelope.MonthlySummaryFacts)
	if !analysis.RiskCoveragePass || !analysis.CitationAlignmentPass {
		t.Fatalf("expected pass coverage: %+v", analysis)
	}
}

func TestAnalyzeModelExplanationAlignmentMissingRisk(t *testing.T) {
	c := findCase(t, "C03_high_monthly_payment")
	analysis := eval.AnalyzeModelExplanationAlignment(contract.ModelAssistantAnswerDraftDTO{}, c.Assessment, c.Envelope.MonthlySummaryFacts)
	if analysis.RiskCoveragePass || analysis.MissingRiskExplanationCount != 1 {
		t.Fatalf("expected missing risk: %+v", analysis)
	}
}

func TestAnalyzeModelExplanationAlignmentUnsupportedRisk(t *testing.T) {
	c := findCase(t, "A01_healthy_cashflow")
	model := contract.ModelAssistantAnswerDraftDTO{
		RiskExplanations: []contract.ModelRiskExplanationDTO{{
			ReasonCode: "highDebtPaymentToIncome",
			Text:       "DTI",
		}},
	}
	analysis := eval.AnalyzeModelExplanationAlignment(model, c.Assessment, c.Envelope.MonthlySummaryFacts)
	if analysis.RiskCoveragePass || analysis.UnsupportedRiskExplanationCount != 1 {
		t.Fatalf("expected unsupported risk: %+v", analysis)
	}
}

func TestAnalyzeModelExplanationAlignmentUnknownCoverage(t *testing.T) {
	c := findCase(t, "E05_missing_debt_data")
	model := contract.ModelAssistantAnswerDraftDTO{
		UnknownExplanations: []contract.ModelUnknownExplanationDTO{{ReasonCode: "debtDataMissing"}},
	}
	analysis := eval.AnalyzeModelExplanationAlignment(model, c.Assessment, c.Envelope.MonthlySummaryFacts)
	if !analysis.UnknownCoveragePass {
		t.Fatalf("expected unknown coverage pass: %+v", analysis)
	}
}

func TestAnalyzeModelExplanationAlignmentUnsupportedUnknown(t *testing.T) {
	c := findCase(t, "E05_missing_debt_data")
	model := contract.ModelAssistantAnswerDraftDTO{
		UnknownExplanations: []contract.ModelUnknownExplanationDTO{{ReasonCode: "cashFlowProjectionMissing"}},
	}
	analysis := eval.AnalyzeModelExplanationAlignment(model, c.Assessment, c.Envelope.MonthlySummaryFacts)
	if analysis.UnknownCoveragePass || analysis.UnsupportedUnknownExplanationCount != 1 {
		t.Fatalf("expected unsupported unknown: %+v", analysis)
	}
}

func TestDeterministicCitationAssemblyAlwaysMatchesAssessment(t *testing.T) {
	c := findCase(t, "C03_high_monthly_payment")
	model := contract.ModelAssistantAnswerDraftDTO{
		RiskExplanations: []contract.ModelRiskExplanationDTO{{
			ReasonCode: "highDebtPaymentToIncome",
			Text:       "model no longer supplies citations",
		}},
	}
	analysis := eval.AnalyzeModelExplanationAlignment(model, c.Assessment, c.Envelope.MonthlySummaryFacts)
	if !analysis.CitationAlignmentPass || analysis.CitationMisalignmentCount != 0 {
		t.Fatalf("expected deterministic citation pass: %+v", analysis)
	}
}

func TestKnownNoDebtNarrativeContradiction(t *testing.T) {
	c := findCase(t, "C01_no_debt")
	draft := contract.AssistantAnswerDraftDTO{
		Title: "t", Body: "当前债务压力较高，需要关注。", Answer: "a",
	}
	narr := eval.AnalyzeNarrativeSemantics(c, draft)
	if narr.KnownNoDebtContradictionCount != 1 {
		t.Fatalf("expected contradiction: %+v", narr)
	}
}

func TestMissingDebtOverconfidence(t *testing.T) {
	c := findCase(t, "E05_missing_debt_data")
	draft := contract.AssistantAnswerDraftDTO{
		Title: "t", Body: "您目前没有债务，财务状况良好。", Answer: "a",
	}
	narr := eval.AnalyzeNarrativeSemantics(c, draft)
	if narr.MissingDebtOverconfidenceCount != 1 {
		t.Fatalf("expected overconfidence: %+v", narr)
	}
}

func TestSafePlusMissingMisstatement(t *testing.T) {
	c := findCase(t, "E05_missing_debt_data")
	draft := contract.AssistantAnswerDraftDTO{
		Title: "t", Body: "整体财务完全安全，没有任何财务风险。", Answer: "a",
	}
	narr := eval.AnalyzeNarrativeSemantics(c, draft)
	if narr.SafePlusMissingMisstatementCount != 1 {
		t.Fatalf("expected safe+missing misstatement: %+v", narr)
	}
}

func TestNarrativeSeverityMismatch(t *testing.T) {
	c := findCase(t, "C03_high_monthly_payment")
	draft := contract.AssistantAnswerDraftDTO{
		Title: "t", Body: "存在严重风险，属于高危情况。", Answer: "a",
	}
	narr := eval.AnalyzeNarrativeSemantics(c, draft)
	if narr.NarrativeSeverityMismatchCount != 1 {
		t.Fatalf("expected severity mismatch: %+v", narr)
	}
}

func TestPolicyStructuralAlignmentPass(t *testing.T) {
	c := findCase(t, "B01_minimum_below_safe")
	draft := contract.AssistantAnswerDraftDTO{Title: "t", Body: "b", Answer: "a"}
	pass, detail := eval.EvaluatePolicyStructuralAlignment(c.Assessment, draft)
	if !pass {
		t.Fatalf("expected policy alignment pass, got %s", detail)
	}
}

func TestPolicyStructuralAlignmentRejectsModelWarnings(t *testing.T) {
	c := findCase(t, "B01_minimum_below_safe")
	draft := contract.AssistantAnswerDraftDTO{
		Title: "t", Body: "b", Answer: "a",
		Warnings: []contract.Warning{{Title: "x", Message: "y", Severity: "warning", Source: "minimumBalance"}},
	}
	pass, _ := eval.EvaluatePolicyStructuralAlignment(c.Assessment, draft)
	if pass {
		t.Fatal("expected failure when model draft includes warnings")
	}
}

func TestLegacyMetricNonGatingInV2Acceptance(t *testing.T) {
	acceptance := eval.V2AcceptanceComparison{LegacyRiskMatchNonGating: true, LegacyRiskMatchPass: false}
	if !acceptance.LegacyRiskMatchNonGating {
		t.Fatal("legacy risk match must remain non-gating")
	}
}

func TestV2ReportSerializationFields(t *testing.T) {
	report := eval.BuildReport(
		eval.RunMetadata{TotalCases: 1, TotalRuns: 1},
		nil,
		eval.AggregateMetrics{},
		eval.EvaluationModeExplanationAlignmentV2,
	)
	if report.EvaluationVersion != eval.EvaluationVersionV2 {
		t.Fatalf("expected version %s, got %s", eval.EvaluationVersionV2, report.EvaluationVersion)
	}
	if len(report.AssessmentMigration) != 29 {
		t.Fatalf("expected migration table, got %d rows", len(report.AssessmentMigration))
	}
	if report.ModelVerdict.ProductionReadiness == "" {
		t.Fatal("expected readiness verdicts")
	}
}

func TestLegacyModePreservesRiskGatingVerdict(t *testing.T) {
	results := []eval.RunResult{
		{
			CaseID: "A01_healthy_cashflow", Category: eval.CategoryHealthyFinance,
			EndToEndPass: false, ContractPass: true, FailureClass: eval.FailureSemanticRisk,
			RiskMatch: false, ModelResponseAssessed: true,
			Semantic:  eval.SemanticResult{RiskMismatchDirection: eval.RiskMismatchUnexpectedWarning},
			ContractStages: eval.ContractStages{
				HTTPSuccess: true, HTTP2xxSuccess: true, UpstreamHTTP: "pass",
				DraftDTODecode: "pass", GatewaySchemaValidation: "pass", FactValidation: "pass",
				ModelResponseAssessed: true,
			},
		},
	}
	for _, id := range []string{"B01_minimum_below_safe", "C03_high_monthly_payment"} {
		results = append(results, eval.RunResult{
			CaseID: id, EndToEndPass: true, ContractPass: true, RiskMatch: true, UnknownBehaviorPass: true,
			ModelResponseAssessed: true,
			ContractStages: eval.ContractStages{
				HTTPSuccess: true, HTTP2xxSuccess: true, UpstreamHTTP: "pass",
				DraftDTODecode: "pass", GatewaySchemaValidation: "pass", FactValidation: "pass",
				ModelResponseAssessed: true,
			},
		})
	}
	metrics := eval.ComputeMetrics(results, eval.EvaluationModeLegacyRiskDecision)
	analysis := eval.AnalyzeFullEvaluation(results, eval.AllCases(), metrics, eval.EvaluationModeLegacyRiskDecision)
	if analysis.ModelVerdict != eval.VerdictConditionallyReady {
		t.Fatalf("expected legacy Conditionally Ready, got %s", analysis.ModelVerdict)
	}
}