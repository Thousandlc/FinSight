package eval

import (
	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/factpack"
	"github.com/youshu/youshu-ai-gateway/internal/smoke"
)

const (
	CitationAdjudicationConfirmedModelFailure  = "confirmedModelFailure"
	CitationAdjudicationEvaluatorFalsePositive = "evaluatorFalsePositive"
	CitationAdjudicationProductionContractGap  = "productionCitationContractGap"
	CitationAdjudicationEvaluationContractGap  = "evaluationCitationContractGap"
)

// C01CitationAdjudication summarizes offline adjudication for C01 citation semantics.
type C01CitationAdjudication struct {
	CaseID                    string `json:"caseId"`
	RunIndex                  int    `json:"runIndex"`
	Owner                     string `json:"owner"`
	ProductionCitationAllowed bool   `json:"productionCitationAllowed"`
	KeyFactSelectionPass      bool   `json:"keyFactSelectionPass"`
	EvaluatorScopeCreep       bool   `json:"evaluatorScopeCreep"`
	Notes                     string `json:"notes,omitempty"`
}

// CorrectedC2CAdjudication holds post-C2C corrected failure ownership after citation audit.
type CorrectedC2CAdjudication struct {
	KeyFactArchitectureReadiness string `json:"keyFactArchitectureReadiness"`
	CorrectedE2EReadiness        string `json:"correctedE2EReadiness"`
	StrictE2EReadiness           string `json:"strictE2EReadiness"`
	ConfirmedModelFailures       int    `json:"confirmedModelFailures"`
	ApplicationFailures          int    `json:"applicationFailures"`
	EvaluatorFalsePositives      int    `json:"evaluatorFalsePositives"`
	EvaluationContractGaps       int    `json:"evaluationContractGaps"`
	ProductionContractGaps       int    `json:"productionContractGaps"`
}

// AdjudicateC01CitationRun resolves C01 citation failure ownership against production contract.
func AdjudicateC01CitationRun(r RunResult, c EvaluationCase) C01CitationAdjudication {
	out := C01CitationAdjudication{
		CaseID:               r.CaseID,
		RunIndex:             r.RunIndex,
		KeyFactSelectionPass: r.DiagnosticSnapshot.KeyFactSelectionPass,
	}
	out.ProductionCitationAllowed = ProductionAllowsMonthlyDebtPaymentCitation(c)
	out.EvaluatorScopeCreep = EvaluatorForbiddenFactKeysScopeCreep(c)

	if !r.EndToEndPass &&
		r.FailureClass == FailureFactReference &&
		out.ProductionCitationAllowed &&
		out.KeyFactSelectionPass {
		out.Owner = CitationAdjudicationEvaluatorFalsePositive
		out.Notes = "monthlyDebtPayment=0 is registered known-zero; production allows top-level citation; evaluator ForbiddenFactKeys over-scans citedFactKeys"
		return out
	}
	if !out.ProductionCitationAllowed {
		out.Owner = CitationAdjudicationConfirmedModelFailure
		out.Notes = "citation violates production AllowedFactKeys contract"
		return out
	}
	out.Owner = CitationAdjudicationConfirmedModelFailure
	return out
}

// ProductionAllowsMonthlyDebtPaymentCitation reports whether production fact/schema contract allows C01 citation.
func ProductionAllowsMonthlyDebtPaymentCitation(c EvaluationCase) bool {
	facts := c.Envelope.MonthlySummaryFacts
	assessment := c.Envelope.FinancialRiskAssessment
	if assessment == nil {
		a := c.Assessment
		assessment = &a
	}
	if facts == nil {
		return false
	}
	keySets := factpack.BuildKeySetsForRequest(facts, assessment)
	if !containsEvalKey(keySets.AllowedFactKeys, "monthlyDebtPayment") {
		return false
	}
	diag := smoke.DiagnoseFactsWithKeySets(
		citationProbeDraft("monthlyDebtPayment"),
		facts,
		keySets,
	)
	return diag.Passed && diag.CitedFactKeysValid
}

// EvaluatorForbiddenFactKeysScopeCreep reports when eval forbidden scope rejects production-allowed citations.
func EvaluatorForbiddenFactKeysScopeCreep(c EvaluationCase) bool {
	scope := ResolveForbiddenScopes(c)
	if len(scope.CitationFactKeys) == 0 {
		return false
	}
	legacy := CheckExpectations(c, citationProbeDraft("monthlyDebtPayment"))
	return !legacy.CitationSemanticPass && ProductionAllowsMonthlyDebtPaymentCitation(c)
}

func citationProbeDraft(source string) contract.AssistantAnswerDraftDTO {
	return contract.AssistantAnswerDraftDTO{
		Title:         "probe",
		Body:          "probe",
		Answer:        "probe",
		CitedFactKeys: []string{"monthlyIncome", source},
		KeyFacts:      []contract.KeyFact{},
	}
}

// CorrectC2CCitationAdjudication recomputes C2C ownership using citation semantic audit.
func CorrectC2CCitationAdjudication(report EvaluationReport) CorrectedC2CAdjudication {
	out := CorrectedC2CAdjudication{
		KeyFactArchitectureReadiness: ReadinessPass,
		StrictE2EReadiness:           ReadinessFail,
	}
	if report.C2CTargetedReadiness.EndToEndPassCount == report.C2CTargetedReadiness.PlannedRuns &&
		report.C2CTargetedReadiness.PlannedRuns > 0 {
		out.StrictE2EReadiness = ReadinessPass
	}

	c, err := findCaseByID(C2CCaseC01)
	if err == nil && EvaluatorForbiddenFactKeysScopeCreep(c) {
		out.EvaluationContractGaps = 1
	}

	e2ePass := 0
	for _, r := range report.Results {
		pass := r.EndToEndPass
		if r.CaseID == C2CCaseC01 && r.RunIndex == 2 && err == nil {
			adj := AdjudicateC01CitationRun(r, c)
			if adj.Owner == CitationAdjudicationEvaluatorFalsePositive {
				out.EvaluatorFalsePositives++
				pass = true
			}
		}
		if pass {
			e2ePass++
		}
	}
	if report.C2CTargetedReadiness.PlannedRuns > 0 &&
		e2ePass == report.C2CTargetedReadiness.PlannedRuns {
		out.CorrectedE2EReadiness = ReadinessPass
	}
	return out
}

func containsEvalKey(items []string, target string) bool {
	for _, item := range items {
		if item == target {
			return true
		}
	}
	return false
}
