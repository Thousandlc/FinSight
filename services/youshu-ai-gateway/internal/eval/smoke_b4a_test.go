package eval

import (
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/provider"
)

func TestExplanationReadinessFailsOnTenOfTwelveAlignment(t *testing.T) {
	results := make([]RunResult, 0, 12)
	for i := 0; i < 10; i++ {
		results = append(results, passingSmokeRun("A01_healthy_cashflow", i+1))
	}
	for run := 1; run <= 2; run++ {
		results = append(results, RunResult{
			CaseID:   "E01_partial_debt_data",
			RunIndex: run,
			ContractStages: ContractStages{
				HTTPSuccess:             true,
				HTTP2xxSuccess:          true,
				ContentJSONValid:        true,
				GenericJSONObjectDecode: "pass",
				DraftDTODecode:          "fail",
				DTODecodeErrorKind:      "explanationAlignment",
				ExplanationAlignment:    "fail",
			},
		})
	}
	metrics := ComputeMetrics(results, EvaluationModeExplanationAlignmentV2)
	analysis := AnalyzeFullEvaluation(results, AllCases(), metrics, EvaluationModeExplanationAlignmentV2)
	srv := DeriveSmokeReadinessVerdicts(metrics, analysis)
	if srv.SmokeExplanationContractReadiness != ReadinessFail {
		t.Fatalf("expected explanation readiness FAIL, got %s (pass=%d http2xx=%d)",
			srv.SmokeExplanationContractReadiness, metrics.ExplanationAlignmentPassCount, metrics.HTTP2xxSuccessCount)
	}
}

func TestSurvivingTenOfTenMustNotProduceExplanationPassWhenTwoFailed(t *testing.T) {
	results := make([]RunResult, 0, 12)
	for i := 0; i < 10; i++ {
		r := passingSmokeRun("C03_high_monthly_payment", i+1)
		results = append(results, r)
	}
	for run := 1; run <= 2; run++ {
		results = append(results, RunResult{
			CaseID: "E01_partial_debt_data", RunIndex: run,
			ContractStages: ContractStages{
				HTTPSuccess: true, HTTP2xxSuccess: true, ContentJSONValid: true,
				GenericJSONObjectDecode: "pass", DraftDTODecode: "fail",
				DTODecodeErrorKind: "explanationAlignment", ExplanationAlignment: "fail",
			},
		})
	}
	metrics := ComputeMetrics(results, EvaluationModeExplanationAlignmentV2)
	if metrics.ExplanationAlignmentPassCount != 10 {
		t.Fatalf("alignment pass=%d want 10", metrics.ExplanationAlignmentPassCount)
	}
	if rate(metrics.ExplanationAlignmentPassCount, metrics.HTTP2xxSuccessCount) >= 0.99 {
		t.Fatal("10/12 must not meet 99% threshold")
	}
}

func TestKnownNoDebtForbiddenDebtPressureCountsContradiction(t *testing.T) {
	c, err := findCaseByID("C01_no_debt")
	if err != nil {
		t.Fatal(err)
	}
	draft := contract.AssistantAnswerDraftDTO{
		Title: "t", Body: "当前债务压力需要关注", Answer: "a",
		CitedFactKeys: []string{}, Unknowns: []string{},
		KeyFacts: []contract.KeyFact{}, Actions: []contract.Action{},
		References: []contract.Reference{}, Warnings: []contract.Warning{},
	}
	v2 := CheckExplanationExpectationsV2(c, draft, true, true)
	if v2.Narrative.KnownNoDebtContradictionCount != 1 {
		t.Fatalf("expected knownNoDebt contradiction=1, got %d", v2.Narrative.KnownNoDebtContradictionCount)
	}
	if !containsString(v2.FailureClasses, FailureNarrativeKnownNoDebt) {
		t.Fatalf("expected primary %s, got %v", FailureNarrativeKnownNoDebt, v2.FailureClasses)
	}
	if containsString(v2.FailureClasses, FailureSemanticForbidden) {
		t.Fatalf("must not double-count forbidden claim: %v", v2.FailureClasses)
	}
}

func TestConfirmedC01ContradictionFailsNarrativeReadiness(t *testing.T) {
	c, err := findCaseByID("C01_no_debt")
	if err != nil {
		t.Fatal(err)
	}
	var results []RunResult
	for run := 1; run <= 2; run++ {
		draft := contract.AssistantAnswerDraftDTO{
			Title: "t", Body: "债务压力", Answer: "a",
			CitedFactKeys: []string{}, Unknowns: []string{},
			KeyFacts: []contract.KeyFact{}, Actions: []contract.Action{},
			References: []contract.Reference{}, Warnings: []contract.Warning{},
		}
		v2 := CheckExplanationExpectationsV2(c, draft, true, true)
		results = append(results, RunResult{
			CaseID: "C01_no_debt", RunIndex: run, EndToEndPass: false, ContractPass: true,
			ExplanationAlignmentPass: true, V2Semantic: v2, Semantic: SemanticResult{ForbiddenClaimHits: []string{"债务压力"}},
			ContractStages: ContractStages{HTTPSuccess: true, HTTP2xxSuccess: true, DraftDTODecode: "pass", ExplanationAlignment: "pass", GatewaySchemaValidation: "pass", FactValidation: "pass"},
			ModelResponseAssessed: true,
		})
	}
	metrics := ComputeMetrics(results, EvaluationModeExplanationAlignmentV2)
	analysis := AnalyzeFullEvaluation(results, AllCases(), metrics, EvaluationModeExplanationAlignmentV2)
	srv := DeriveSmokeReadinessVerdicts(metrics, analysis)
	if srv.SmokeNarrativeReadiness != ReadinessFail {
		t.Fatalf("expected narrative FAIL, got %s", srv.SmokeNarrativeReadiness)
	}
}

func TestDTODecodePassAlignmentFailStageAttribution(t *testing.T) {
	content := `{
		"title":"t","body":"b","answer":"a","citedFactKeys":[],"confidence":0.8,
		"keyFacts":[],"references":[],
		"riskExplanations":[],"unknownExplanations":[]
	}`
	c, err := findCaseByID("E01_partial_debt_data")
	if err != nil {
		t.Fatal(err)
	}
	_, diag := provider.AnalyzeContent(content, &c.Assessment, c.Envelope.MonthlySummaryFacts)
	if diag.DraftDTODecode != provider.StagePass {
		t.Fatalf("dto=%s kind=%s", diag.DraftDTODecode, diag.DTODecodeErrorKind)
	}
	if diag.ExplanationAlignment != provider.StageFail {
		t.Fatalf("alignment stage=%s code=%s", diag.ExplanationAlignment, diag.AlignmentFailureCode)
	}
	if diag.AlignmentFailureCode != "riskExplanationCoverageMismatch" {
		t.Fatalf("code=%s", diag.AlignmentFailureCode)
	}
}

func TestNormalizeLegacyRunStages(t *testing.T) {
	r := RunResult{
		CaseID: "E01_partial_debt_data", RunIndex: 1,
		ContractStages: ContractStages{
			HTTPSuccess: true, HTTP2xxSuccess: true, ContentJSONValid: true,
			GenericJSONObjectDecode: "pass", DraftDTODecode: "fail",
			DTODecodeErrorKind: "explanationAlignment", ExplanationAlignment: "fail",
		},
		Transport: TransportFailureDetail{FailureStage: "modelDecode"},
	}
	NormalizeLegacyRunStages(&r)
	if r.ContractStages.DraftDTODecode != "pass" {
		t.Fatalf("dto=%s", r.ContractStages.DraftDTODecode)
	}
	if r.ContractStages.ExplanationAlignment != "fail" {
		t.Fatal("expected alignment fail")
	}
	if r.Transport.FailureStage != "explanationAlignment" {
		t.Fatalf("stage=%s", r.Transport.FailureStage)
	}
}

func TestRescoreFrozenSmokeArtifactOffline(t *testing.T) {
	path := ".eval-output/smoke-v2-20260817-013536.json"
	rescore, err := LoadAndRescoreSmokeArtifact(path)
	if err != nil {
		t.Skipf("frozen artifact unavailable: %v", err)
	}
	if rescore.CorrectedReadiness.SmokeExplanationContractReadiness != ReadinessFail {
		t.Fatalf("corrected explanation readiness=%s", rescore.CorrectedReadiness.SmokeExplanationContractReadiness)
	}
	if rescore.CorrectedReadiness.SmokeNarrativeReadiness != ReadinessFail {
		t.Fatalf("corrected narrative readiness=%s", rescore.CorrectedReadiness.SmokeNarrativeReadiness)
	}
	if rescore.CorrectedReadiness.SmokeFullEvalReadiness != ReadinessFail {
		t.Fatalf("corrected full eval readiness=%s", rescore.CorrectedReadiness.SmokeFullEvalReadiness)
	}
	if len(rescore.E01Audits) != 2 {
		t.Fatalf("expected 2 E01 audits, got %d", len(rescore.E01Audits))
	}
	for _, audit := range rescore.E01Audits {
		if audit.AlignmentFailureCode != "riskExplanationCoverageMismatch" {
			t.Fatalf("run=%d code=%s", audit.RunIndex, audit.AlignmentFailureCode)
		}
		if audit.Adjudication != VerdictModelError {
			t.Fatalf("run=%d adjudication=%s want %s", audit.RunIndex, audit.Adjudication, VerdictModelError)
		}
	}
	if rescore.CorrectedReport.Metrics.ModelDTODecodeCount != 12 {
		t.Fatalf("model dto decode=%d want 12", rescore.CorrectedReport.Metrics.ModelDTODecodeCount)
	}
	if rescore.CorrectedReport.Metrics.ExplanationAlignmentPassCount != 10 {
		t.Fatalf("explanation alignment=%d want 10", rescore.CorrectedReport.Metrics.ExplanationAlignmentPassCount)
	}
	if rescore.CorrectedReport.Metrics.KnownNoDebtContradictionCount != 2 {
		t.Fatalf("knownNoDebt contradictions=%d want 2", rescore.CorrectedReport.Metrics.KnownNoDebtContradictionCount)
	}
}

func TestDiagnosticSnapshotOmitsSecrets(t *testing.T) {
	c, err := findCaseByID("A01_healthy_cashflow")
	if err != nil {
		t.Fatal(err)
	}
	snap := BuildEvaluationDiagnosticSnapshot(c, c.Envelope, provider.DecodeDiagnostics{}, contract.AssistantAnswerDraftDTO{
		Title: "t", Body: "sk-secret-token", Answer: "a",
	}, provider.StagePass)
	if containsSecretDiagnostic(snap.Body) {
		t.Fatal("should not store raw secret patterns in diagnostic helper test")
	}
	_ = snap
}

func passingSmokeRun(caseID string, run int) RunResult {
	return RunResult{
		CaseID: caseID, RunIndex: run, EndToEndPass: true, ContractPass: true,
		ExplanationAlignmentPass: true, PolicyStructuralPass: true, FinalValidatorPass: true,
		V2Semantic: V2SemanticResult{
			Passed: true,
			Explanation: ExplanationAlignmentAnalysis{RiskCoveragePass: true, UnknownCoveragePass: true, CitationAlignmentPass: true},
			PolicyStructuralPass: true, FinalValidatorPass: true,
		},
		ContractStages: ContractStages{
			HTTPSuccess: true, HTTP2xxSuccess: true, ContentJSONValid: true,
			GenericJSONObjectDecode: "pass", DraftDTODecode: "pass", ExplanationAlignment: "pass",
			GatewaySchemaValidation: "pass", FactValidation: "pass",
		},
		ModelResponseAssessed: true,
	}
}

func containsString(items []string, want string) bool {
	for _, item := range items {
		if item == want {
			return true
		}
	}
	return false
}

func TestClassifyAlignmentFailureCodes(t *testing.T) {
	if ClassifyAlignmentFailure("riskExplanationCoverageMismatch") != FailureExplanationRiskCoverage {
		t.Fatal("coverage mismatch mapping")
	}
	if ClassifyAlignmentFailure("riskExplanation missingPrimarySource") != FailureExplanationCitation {
		t.Fatal("citation mapping")
	}
}

func TestLegacyMissingWarningRemainsNonGating(t *testing.T) {
	results := []RunResult{{
		CaseID: "C03_high_monthly_payment", RunIndex: 1, EndToEndPass: true, ContractPass: true,
		RiskMatch: false, ExplanationAlignmentPass: true, PolicyStructuralPass: true, FinalValidatorPass: true,
		V2Semantic: V2SemanticResult{Passed: true, Explanation: ExplanationAlignmentAnalysis{RiskCoveragePass: true, UnknownCoveragePass: true, CitationAlignmentPass: true}, PolicyStructuralPass: true, FinalValidatorPass: true},
		ContractStages: ContractStages{HTTPSuccess: true, HTTP2xxSuccess: true, DraftDTODecode: "pass", ExplanationAlignment: "pass", GatewaySchemaValidation: "pass", FactValidation: "pass"},
		ModelResponseAssessed: true,
	}}
	metrics := ComputeMetrics(results, EvaluationModeExplanationAlignmentV2)
	analysis := AnalyzeFullEvaluation(results, AllCases(), metrics, EvaluationModeExplanationAlignmentV2)
	if !analysis.V2Acceptance.LegacyRiskMatchNonGating {
		t.Fatal("legacy must remain non-gating")
	}
	srv := DeriveSmokeReadinessVerdicts(metrics, analysis)
	if srv.SmokeFullEvalReadiness == ReadinessFail && results[0].RiskMatch {
		t.Fatal("legacy riskMatch alone must not fail full eval when all v2 gates pass")
	}
}
