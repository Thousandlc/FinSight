package eval

import (
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/provider"
)

func TestDeriveE01TargetedDiagnosticReadinessStableOmission(t *testing.T) {
	results := []RunResult{
		{
			CaseID: E01DiagnosticCaseID, RunIndex: 1,
			Transport: TransportFailureDetail{HTTP2xxSuccess: true},
			ContractStages: ContractStages{HTTP2xxSuccess: true, ExplanationAlignment: provider.StageFail},
			DiagnosticSnapshot: EvaluationDiagnosticSnapshot{
				AlignmentFailureCode: "riskExplanationCoverageMismatch",
				ExpectedRiskReasons:  []string{"highDebtPaymentToIncome"},
			},
		},
		{
			CaseID: E01DiagnosticCaseID, RunIndex: 2,
			Transport: TransportFailureDetail{HTTP2xxSuccess: true},
			ContractStages: ContractStages{HTTP2xxSuccess: true, ExplanationAlignment: provider.StageFail},
			DiagnosticSnapshot: EvaluationDiagnosticSnapshot{
				AlignmentFailureCode: "riskExplanationCoverageMismatch",
				ExpectedRiskReasons:  []string{"highDebtPaymentToIncome"},
			},
		},
	}
	readiness := DeriveE01TargetedDiagnosticReadiness(results)
	if readiness.Verdict != ReadinessFail {
		t.Fatalf("verdict=%s", readiness.Verdict)
	}
	if !readiness.StableFailurePattern {
		t.Fatal("expected stable failure pattern")
	}
	if readiness.SignalOmissionCount != 2 {
		t.Fatalf("omission=%d", readiness.SignalOmissionCount)
	}
	if readiness.RecommendedPromptTarget != "coverage" {
		t.Fatalf("target=%s", readiness.RecommendedPromptTarget)
	}
}

func TestDeriveE01TargetedDiagnosticReadinessTwoPass(t *testing.T) {
	results := []RunResult{
		{CaseID: E01DiagnosticCaseID, RunIndex: 1, ExplanationAlignmentPass: true, ContractStages: ContractStages{HTTP2xxSuccess: true, ExplanationAlignment: provider.StagePass}, Transport: TransportFailureDetail{HTTP2xxSuccess: true}},
		{CaseID: E01DiagnosticCaseID, RunIndex: 2, ExplanationAlignmentPass: true, ContractStages: ContractStages{HTTP2xxSuccess: true, ExplanationAlignment: provider.StagePass}, Transport: TransportFailureDetail{HTTP2xxSuccess: true}},
	}
	readiness := DeriveE01TargetedDiagnosticReadiness(results)
	if readiness.Verdict != ReadinessPass {
		t.Fatalf("verdict=%s", readiness.Verdict)
	}
	if readiness.ExplanationPassCount != 2 {
		t.Fatalf("pass=%d", readiness.ExplanationPassCount)
	}
}
