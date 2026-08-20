package eval_test

import (
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/eval"
)

func contractPassRun(caseID, category string) eval.RunResult {
	return eval.RunResult{
		CaseID: caseID, Category: category,
		EndToEndPass: true, ContractPass: true, RiskMatch: true, UnknownBehaviorPass: true,
		ModelResponseAssessed: true,
		ContractStages: eval.ContractStages{
			HTTPSuccess: true, HTTP2xxSuccess: true, UpstreamHTTP: "pass",
			ContentJSONValid: true, DraftDTODecode: "pass",
			GatewaySchemaValidation: "pass", FactValidation: "pass",
			ModelResponseAssessed: true,
		},
	}
}

func TestAnalyzeFullEvaluationVerdictConditionallyReady(t *testing.T) {
	t.Setenv("YOUSHU_EVAL_MODE", eval.EvaluationModeLegacyRiskDecision)
	results := []eval.RunResult{
		{
			CaseID: "A01_healthy_cashflow", Category: eval.CategoryHealthyFinance,
			EndToEndPass: false, ContractPass: true, FailureClass: eval.FailureSemanticRisk,
			FailureSeverity: eval.SeverityMajor, RiskMatch: false,
			EvaluationVerdict: eval.EvaluationVerdictConfirmedModelFailure,
			AuditVerdict:      eval.SemanticAuditVerdict{Verdict: eval.VerdictModelError},
			Semantic:          eval.SemanticResult{RiskMismatchDirection: eval.RiskMismatchUnexpectedWarning},
			StructuredSnapshot: eval.StructuredSnapshot{ActualDerivedRisk: eval.RiskLevelWarning},
			ModelResponseAssessed: true,
			ContractStages: eval.ContractStages{
				HTTPSuccess: true, HTTP2xxSuccess: true, UpstreamHTTP: "pass",
				ContentJSONValid: true, DraftDTODecode: "pass",
				GatewaySchemaValidation: "pass", FactValidation: "pass",
				ModelResponseAssessed: true,
			},
		},
	}
	for _, id := range []string{"B01_minimum_below_safe", "C03_high_monthly_payment"} {
		results = append(results, contractPassRun(id, eval.CategoryCashFlowRisk))
	}
	metrics := eval.ComputeMetrics(results, eval.EvaluationModeLegacyRiskDecision)
	analysis := eval.AnalyzeFullEvaluation(results, eval.AllCases(), metrics, eval.EvaluationModeLegacyRiskDecision)
	if analysis.ModelVerdict != eval.VerdictConditionallyReady {
		t.Fatalf("expected Conditionally Ready, got %s", analysis.ModelVerdict)
	}
	if !analysis.PromptOptimizationNeeded {
		t.Fatal("prompt optimization should be needed")
	}
}

func TestAnalyzeFullEvaluationVerdictNotReadyOnInventedAmount(t *testing.T) {
	results := []eval.RunResult{
		{
			EndToEndPass: false, ContractPass: false, FailureClass: eval.FailureFact,
			FailureSeverity: eval.SeverityCritical, InventedFacts: 1,
			ContractStages: eval.ContractStages{HTTPSuccess: true, FactValidation: "fail"},
		},
	}
	metrics := eval.ComputeMetrics(results, eval.EvaluationModeLegacyRiskDecision)
	analysis := eval.AnalyzeFullEvaluation(results, eval.AllCases(), metrics, eval.EvaluationModeLegacyRiskDecision)
	if analysis.ModelVerdict != eval.VerdictNotReady {
		t.Fatalf("expected Not Ready, got %s", analysis.ModelVerdict)
	}
}

func TestFullDatasetSummaryInAnalysis(t *testing.T) {
	analysis := eval.AnalyzeFullEvaluation(nil, eval.AllCases(), eval.AggregateMetrics{}, eval.EvaluationModeExplanationAlignmentV2)
	if analysis.DatasetSummary.DatasetCases != 29 || analysis.DatasetSummary.FullRuns != 37 {
		t.Fatalf("unexpected dataset summary: %+v", analysis.DatasetSummary)
	}
}

func TestRepeatStabilityFromSyntheticRuns(t *testing.T) {
	results := []eval.RunResult{
		{CaseID: "A01_healthy_cashflow", RunIndex: 1, ContractPass: true, UnknownBehaviorPass: true, ModelResponseAssessed: true,
			StructuredSnapshot: eval.StructuredSnapshot{ActualDerivedRisk: eval.RiskLevelWarning}},
		{CaseID: "A01_healthy_cashflow", RunIndex: 2, ContractPass: true, UnknownBehaviorPass: true, ModelResponseAssessed: true,
			StructuredSnapshot: eval.StructuredSnapshot{ActualDerivedRisk: eval.RiskLevelWarning}},
		{CaseID: "A01_healthy_cashflow", RunIndex: 3, ContractPass: true, UnknownBehaviorPass: true, ModelResponseAssessed: true,
			StructuredSnapshot: eval.StructuredSnapshot{ActualDerivedRisk: eval.RiskLevelWarning}},
	}
	analysis := eval.AnalyzeFullEvaluation(results, eval.AllCases(), eval.ComputeMetrics(results, eval.EvaluationModeExplanationAlignmentV2), eval.EvaluationModeExplanationAlignmentV2)
	if len(analysis.RepeatStability) != 1 {
		t.Fatalf("expected 1 stability report, got %d", len(analysis.RepeatStability))
	}
	if !analysis.RepeatStability[0].RiskStable {
		t.Fatal("risk outcomes should be stable")
	}
}

func TestWorstCasesLimitTen(t *testing.T) {
	var results []eval.RunResult
	for i := 0; i < 12; i++ {
		id := eval.AllCases()[i].ID
		results = append(results, eval.RunResult{
			CaseID: id, Category: eval.AllCases()[i].Category,
			EndToEndPass: false, FailureClass: eval.FailureSemanticRisk,
			FailureSeverity: eval.SeverityMajor,
		})
	}
	analysis := eval.AnalyzeFullEvaluation(results, eval.AllCases(), eval.ComputeMetrics(results, eval.EvaluationModeExplanationAlignmentV2), eval.EvaluationModeExplanationAlignmentV2)
	if len(analysis.WorstCases) > 10 {
		t.Fatalf("worst cases should be capped at 10, got %d", len(analysis.WorstCases))
	}
}

func TestRiskMismatchDirectionCounts(t *testing.T) {
	results := []eval.RunResult{
		{
			CaseID: "A01_healthy_cashflow", Category: eval.CategoryHealthyFinance,
			ContractPass: true, RiskMatch: false, ModelResponseAssessed: true,
			Semantic: eval.SemanticResult{RiskMismatchDirection: eval.RiskMismatchUnexpectedWarning},
		},
		{
			CaseID: "C03_high_monthly_payment", Category: eval.CategoryDebt,
			ContractPass: true, RiskMatch: false, ModelResponseAssessed: true,
			Semantic: eval.SemanticResult{RiskMismatchDirection: eval.RiskMismatchMissingWarning},
		},
	}
	analysis := eval.AnalyzeFullEvaluation(results, eval.AllCases(), eval.ComputeMetrics(results, eval.EvaluationModeExplanationAlignmentV2), eval.EvaluationModeExplanationAlignmentV2)
	if analysis.RiskMismatchDirections[eval.RiskMismatchUnexpectedWarning] != 1 {
		t.Fatalf("unexpected direction counts: %+v", analysis.RiskMismatchDirections)
	}
	if analysis.RiskMismatchDirections[eval.RiskMismatchMissingWarning] != 1 {
		t.Fatalf("unexpected direction counts: %+v", analysis.RiskMismatchDirections)
	}
}
