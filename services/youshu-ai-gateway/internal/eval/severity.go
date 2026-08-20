package eval

// Failure severity constants for audit reporting.
const (
	SeverityCritical   = "critical"
	SeverityMajor      = "major"
	SeverityMinor      = "minor"
	SeverityDiagnostic = "diagnostic"
)

// ClassifyFailureSeverity maps failure class and context to audit severity.
func ClassifyFailureSeverity(failureClass string, c EvaluationCase, snap StructuredSnapshot) string {
	switch failureClass {
	case FailureFact, FailureFactReference, FailureFactSourceCompliance, FailureForbiddenKeyFactSource:
		return SeverityCritical
	case FailureForbiddenCitationFact:
		return SeverityMajor
	case FailureSemanticForbidden:
		if snap.ForbiddenWouldBeCritical(c) {
			return SeverityCritical
		}
		return SeverityMajor
	case FailureExplanationRiskCoverage, FailureExplanationUnknownCoverage, FailureExplanationCitation,
		FailureExplanationUnsupportedRisk, FailureExplanationUnsupportedUnknown:
		return SeverityMajor
	case FailurePolicyProjection:
		return SeverityCritical
	case FailureFinalValidator:
		return SeverityMajor
	case FailureNarrativeKnownNoDebt, FailureNarrativeUnsupportedRisk:
		return SeverityCritical
	case FailureNarrativeMissingData, FailureNarrativeSafeMissing, FailureNarrativeSeverity:
		return SeverityMajor
	case FailureSemanticRisk:
		return classifyRiskFailureSeverity(c.ExpectedRiskLevel, snap)
	case FailureSemanticUnknown:
		return SeverityMajor
	case FailureSemanticConclusion:
		return SeverityDiagnostic
	case FailureSemanticAction:
		return SeverityMinor
	case FailureManualReview:
		return SeverityDiagnostic
	case FailureTimeout:
		return SeverityMajor
	default:
		return SeverityDiagnostic
	}
}

func classifyRiskFailureSeverity(expected RiskLevel, snap StructuredSnapshot) string {
	switch snap.RiskMismatchDirection {
	case RiskMismatchUnexpectedWarning, RiskMismatchOverclassified:
		if expected == RiskLevelNone {
			return SeverityMajor
		}
		return SeverityMinor
	case RiskMismatchMissingWarning, RiskMismatchUnderclassified:
		if expected == RiskLevelRisk {
			return SeverityMajor
		}
		return SeverityMajor
	default:
		return SeverityDiagnostic
	}
}

// AuditVerdict classifies a semantic failure as model error, evaluator issue, or ambiguous.
const (
	VerdictModelError           = "confirmedModelFailure"
	VerdictEvaluatorFalsePositive = "evaluatorFalsePositive"
	VerdictAmbiguous            = "ambiguousManualReview"
	VerdictNotApplicable        = "notApplicable"
)

// SemanticAuditVerdict holds audit classification for one run.
type SemanticAuditVerdict struct {
	CaseID    string `json:"caseId"`
	RunIndex  int    `json:"runIndex"`
	FailureClass string `json:"failureClass,omitempty"`
	Severity  string `json:"severity,omitempty"`
	Verdict   string `json:"verdict"`

	ModelOverWarningCandidate  bool `json:"modelOverWarningCandidate,omitempty"`
	ModelUnnecessaryWarning    bool `json:"modelUnnecessaryWarning,omitempty"`
	EvaluationRuleBug          bool `json:"evaluationRuleBug,omitempty"`
	SemanticCheckerFalseNegative bool `json:"semanticCheckerFalseNegative,omitempty"`
	DatasetExpectationBug      bool `json:"datasetExpectationBug,omitempty"`
	ModelUnknownFailureCandidate bool `json:"modelUnknownFailureCandidate,omitempty"`

	Notes []string `json:"notes,omitempty"`
}

// AuditSemanticFailure classifies a failed semantic check.
func AuditSemanticFailure(c EvaluationCase, r RunResult, snap StructuredSnapshot) SemanticAuditVerdict {
	v := SemanticAuditVerdict{
		CaseID:       r.CaseID,
		RunIndex:     r.RunIndex,
		FailureClass: r.FailureClass,
		Severity:     ClassifyFailureSeverity(r.FailureClass, c, snap),
	}

	if r.EndToEndPass {
		v.Verdict = VerdictNotApplicable
		return v
	}

	switch r.FailureClass {
	case FailureSemanticRisk:
		v = auditRiskFailure(c, snap, v)
	case FailureSemanticUnknown:
		v = auditUnknownFailure(c, v)
	case FailureSemanticConclusion:
		v = auditConclusionFailure(c, r, snap, v)
	case FailureTimeout:
		v.Verdict = VerdictAmbiguous
		v.Notes = append(v.Notes, "timeout prevents semantic audit")
	default:
		if r.ContractPass {
			v.Verdict = VerdictModelError
		} else {
			v.Verdict = VerdictAmbiguous
		}
	}
	return v
}

func auditRiskFailure(c EvaluationCase, snap StructuredSnapshot, v SemanticAuditVerdict) SemanticAuditVerdict {
	switch c.ID {
	case "A01_healthy_cashflow", "F06_no_warning_expected":
		if snap.WarningCount > 0 && (snap.ActualDerivedRisk == RiskLevelWarning || snap.ActualDerivedRisk == RiskLevelRisk) {
			v.Verdict = VerdictModelError
			v.ModelOverWarningCandidate = true
			if c.ID == "F06_no_warning_expected" {
				v.ModelUnnecessaryWarning = true
			}
			v.Notes = append(v.Notes, "healthy scenario produced warning/risk severity")
		} else if snap.WarningCount > 0 && snap.ActualDerivedRisk == RiskLevelSafe {
			v.Verdict = VerdictAmbiguous
			v.Notes = append(v.Notes, "only safe-severity warnings present; may be acceptable")
		} else {
			v.Verdict = VerdictAmbiguous
		}
	case "C03_high_monthly_payment", "D02_zero_income_month":
		if snap.RiskMismatchDirection == RiskMismatchMissingWarning || snap.RiskMismatchDirection == RiskMismatchUnderclassified {
			v.Verdict = VerdictModelError
			v.Notes = append(v.Notes, "expected warning/risk but model under-classified")
		} else {
			v.Verdict = VerdictAmbiguous
		}
	default:
		if snap.RiskMismatchDirection == RiskMismatchOverclassified || snap.RiskMismatchDirection == RiskMismatchUnexpectedWarning {
			v.Verdict = VerdictModelError
		} else if snap.RiskMismatchDirection == RiskMismatchMissingWarning {
			v.Verdict = VerdictModelError
		} else {
			v.Verdict = VerdictAmbiguous
		}
	}
	return v
}

func auditUnknownFailure(c EvaluationCase, v SemanticAuditVerdict) SemanticAuditVerdict {
	debt := AnalyzeDebtFacts(c)
	exp := ResolveUnknownExpectation(c)
	data := AnalyzeInsufficientDataCase(c)

	if exp == UnknownNotRequired && (data.Classification == DataNotApplicable || data.Classification == DataOptionalAbsent) {
		v.Verdict = VerdictNotApplicable
		v.Notes = append(v.Notes, data.Summary)
		return v
	}
	if exp == UnknownRequired && debt.DebtFactsPartial {
		v.Verdict = VerdictEvaluatorFalsePositive
		v.DatasetExpectationBug = true
		v.EvaluationRuleBug = true
		v.Notes = append(v.Notes, "partial debt data should not require unknowns")
		return v
	}
	if exp == UnknownRequired && debt.DebtFactsMissing {
		v.Verdict = VerdictModelError
		v.ModelUnknownFailureCandidate = true
		v.Notes = append(v.Notes, "genuinely missing debt; model should populate unknowns")
		return v
	}
	if exp == UnknownNotRequired && !debt.DebtFactsMissing {
		v.Verdict = VerdictNotApplicable
		return v
	}
	if exp == UnknownRequired {
		v.Verdict = VerdictModelError
		v.ModelUnknownFailureCandidate = true
	}
	return v
}

func auditConclusionFailure(c EvaluationCase, r RunResult, snap StructuredSnapshot, v SemanticAuditVerdict) SemanticAuditVerdict {
	if !c.StructuredConclusion.IsZero() {
		if r.Semantic.StructuredConclusionPass {
			v.Verdict = VerdictNotApplicable
			return v
		}
		v.Verdict = VerdictModelError
		v.Notes = append(v.Notes, "structured conclusion requirements not met")
		return v
	}
	if len(c.RequiredFactKeys) > 0 && !r.Semantic.FactKeyCompliancePass {
		v.Verdict = VerdictModelError
		v.Notes = append(v.Notes, "required fact keys missing from structured output")
		return v
	}
	v.Verdict = VerdictAmbiguous
	return v
}

// ForbiddenWouldBeCritical is a stub for severity helper on snapshot.
func (s StructuredSnapshot) ForbiddenWouldBeCritical(c EvaluationCase) bool {
	return len(c.ForbiddenClaims) > 0
}
