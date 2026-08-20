package eval

// EvaluationVerdict constants for replay pilot audit.
const (
	EvaluationVerdictConfirmedModelFailure = "confirmedModelFailure"
	EvaluationVerdictEvaluatorFalsePositive = "evaluatorFalsePositive"
	EvaluationVerdictAmbiguous             = "ambiguous"
	EvaluationVerdictManualReview          = "manualReview"
	EvaluationVerdictPass                  = "pass"
)

// EvaluationReadinessResult reports whether the framework is ready for full eval.
type EvaluationReadinessResult struct {
	Ready    bool     `json:"ready"`
	Blockers []string `json:"blockers,omitempty"`
}

// AssessEvaluationReadiness checks post-replay pilot readiness criteria.
func AssessEvaluationReadiness(audit PilotAuditReport) EvaluationReadinessResult {
	var blockers []string

	if audit.EvaluatorFalsePositives > 0 {
		blockers = append(blockers, "evaluator false positives must be 0")
	}
	if err := ValidateDataset(AllCases()); err != nil {
		blockers = append(blockers, "dataset validation: "+err.Error())
	}
	if err := ValidateDebtDataSemantics(AllCases()); err != nil {
		blockers = append(blockers, "debt semantics: "+err.Error())
	}

	return EvaluationReadinessResult{
		Ready:    len(blockers) == 0,
		Blockers: blockers,
	}
}

// ResolveEvaluationVerdict maps audit verdict to evaluationVerdict label.
func ResolveEvaluationVerdict(r RunResult) string {
	if r.EndToEndPass {
		return EvaluationVerdictPass
	}
	switch r.AuditVerdict.Verdict {
	case VerdictModelError:
		return EvaluationVerdictConfirmedModelFailure
	case VerdictEvaluatorFalsePositive:
		return EvaluationVerdictEvaluatorFalsePositive
	case VerdictAmbiguous:
		if r.Semantic.ManualReviewRequired {
			return EvaluationVerdictManualReview
		}
		return EvaluationVerdictAmbiguous
	case VerdictNotApplicable:
		if r.Timeout {
			return EvaluationVerdictAmbiguous
		}
		return EvaluationVerdictPass
	default:
		if r.FailureClass == FailureTimeout {
			return EvaluationVerdictAmbiguous
		}
		if r.ContractPass && !r.SemanticPass {
			return EvaluationVerdictConfirmedModelFailure
		}
		return EvaluationVerdictAmbiguous
	}
}
