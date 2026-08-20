package eval

import (
	"sort"
	"strings"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/factpack"
	"github.com/youshu/youshu-ai-gateway/internal/provider"
)

// EvaluationDiagnosticSnapshot holds safe synthetic-eval diagnostics for offline adjudication.
type EvaluationDiagnosticSnapshot struct {
	FailureStage                   string   `json:"failureStage,omitempty"`
	AlignmentFailureCode           string   `json:"alignmentFailureCode,omitempty"`
	ExpectedRiskReasons            []string `json:"expectedRiskReasons,omitempty"`
	ActualRiskExplanationReasons   []string `json:"actualRiskExplanationReasons,omitempty"`
	ExpectedUnknownReasons         []string `json:"expectedUnknownReasons,omitempty"`
	ActualUnknownExplanationReasons []string `json:"actualUnknownExplanationReasons,omitempty"`
	ExpectedSignalSourceFactKeys   []string `json:"expectedSignalSourceFactKeys,omitempty"`
	AssembledCitedFactKeys         []string `json:"assembledCitedFactKeys,omitempty"`
	TopLevelCitedFactKeys          []string `json:"topLevelCitedFactKeys,omitempty"`
	ActualCitedFactKeys            []string `json:"actualCitedFactKeys,omitempty"` // legacy alias; prefer assembledCitedFactKeys post-B5E
	ExpectedPrimarySource          string   `json:"expectedPrimarySource,omitempty"`
	PrimarySourcePresent           bool     `json:"primarySourcePresent"`
	ProvenanceAssemblyPass         bool     `json:"provenanceAssemblyPass,omitempty"`
	ProvenanceAssemblyFailureCode  string   `json:"provenanceAssemblyFailureCode,omitempty"`
	RiskSourceFactAvailabilityFailureCode string `json:"riskSourceFactAvailabilityFailureCode,omitempty"`
	RiskExplanations               []EvalRiskExplanationSnapshot    `json:"riskExplanations,omitempty"`
	UnknownExplanations            []EvalUnknownExplanationSnapshot `json:"unknownExplanations,omitempty"`
	Title                          string   `json:"title,omitempty"`
	Body                           string   `json:"body,omitempty"`
	Answer                         string   `json:"answer,omitempty"`

	AllowedFactKeys             []string                      `json:"allowedFactKeys,omitempty"`
	AllowedKeyFactKeys          []string                      `json:"allowedKeyFactKeys,omitempty"`
	ForbiddenKeyFactKeys        []string                      `json:"forbiddenKeyFactKeys,omitempty"`
	ModelSelectedKeyFactSources []string                      `json:"modelSelectedKeyFactSources,omitempty"`
	MaterializedKeyFacts        []MaterializedKeyFactSnapshot `json:"materializedKeyFacts,omitempty"`
	KeyFactSelectionPass        bool                          `json:"keyFactSelectionPass"`
	KeyFactMaterializationPass  bool                          `json:"keyFactMaterializationPass"`
	KeyFactCanonicalParityPass  bool                          `json:"keyFactCanonicalParityPass"`
	ModelSchemaContractMarker   string                        `json:"modelSchemaContractMarker,omitempty"`
	ModelSchemaFingerprint      string                        `json:"modelSchemaFingerprint,omitempty"`
}

// EvalRiskExplanationSnapshot is synthetic-eval-only structured risk explanation detail.
type EvalRiskExplanationSnapshot struct {
	ReasonCode    string   `json:"reasonCode"`
	CitedFactKeys []string `json:"citedFactKeys,omitempty"`
	Text          string   `json:"text,omitempty"`
}

// EvalUnknownExplanationSnapshot is synthetic-eval-only structured unknown explanation detail.
type EvalUnknownExplanationSnapshot struct {
	ReasonCode string `json:"reasonCode"`
	Text       string `json:"text,omitempty"`
}

var manualReviewSmokeCaseIDs = map[string]struct{}{
	"C01_no_debt":                     {},
	"E01_partial_debt_data":           {},
	"E05_missing_debt_data":           {},
	"B04_short_term_negative_balance": {},
}

// BuildEvaluationDiagnosticSnapshot captures contract-debug fields without secrets.
func BuildEvaluationDiagnosticSnapshot(
	c EvaluationCase,
	env contract.RequestEnvelope,
	diag provider.DecodeDiagnostics,
	draft contract.AssistantAnswerDraftDTO,
	explanationStage string,
) EvaluationDiagnosticSnapshot {
	snap := EvaluationDiagnosticSnapshot{
		FailureStage:         transportFailureStageForSnapshot(diag, explanationStage),
		AlignmentFailureCode: diag.AlignmentFailureCode,
		ExpectedRiskReasons:  expectedSignalReasonCodes(&c.Assessment),
		ExpectedUnknownReasons: append([]string(nil), c.Assessment.DataCompleteness.RequiredUnknownReasonCodes...),
	}
	sort.Strings(snap.ExpectedUnknownReasons)

	if len(c.Assessment.Signals) > 0 {
		signal := nonSafeSignals(c.Assessment)[0]
		snap.ExpectedSignalSourceFactKeys = append([]string(nil), signal.SourceFactKeys...)
		snap.ExpectedPrimarySource = primarySourceFactKey(signal)
	}

	if shouldCaptureEvalDiagnosticSnapshot(c.ID) {
		snap.Title = draft.Title
		snap.Body = draft.Body
		snap.Answer = draft.Answer
	}

	if len(diag.RiskExplanationDiagnostics) > 0 {
		for _, item := range diag.RiskExplanationDiagnostics {
			snap.RiskExplanations = append(snap.RiskExplanations, EvalRiskExplanationSnapshot{
				ReasonCode:    item.ReasonCode,
				CitedFactKeys: cloneStringSlice(item.CitedFactKeys),
				Text:          item.Text,
			})
			if snap.ExpectedPrimarySource != "" {
				for _, key := range item.CitedFactKeys {
					if key == snap.ExpectedPrimarySource {
						snap.PrimarySourcePresent = true
						break
					}
				}
			}
		}
	}
	if len(diag.UnknownExplanationDiagnostics) > 0 {
		for _, item := range diag.UnknownExplanationDiagnostics {
			snap.UnknownExplanations = append(snap.UnknownExplanations, EvalUnknownExplanationSnapshot{
				ReasonCode: item.ReasonCode,
				Text:       item.Text,
			})
		}
	}

	if len(diag.ActualRiskExplanationReasons) > 0 {
		snap.ActualRiskExplanationReasons = cloneStringSlice(diag.ActualRiskExplanationReasons)
	}
	if len(diag.ActualUnknownExplanationReasons) > 0 {
		snap.ActualUnknownExplanationReasons = cloneStringSlice(diag.ActualUnknownExplanationReasons)
	}
	if len(diag.AssembledCitedFactKeys) > 0 {
		snap.AssembledCitedFactKeys = cloneStringSlicePreserveOrder(diag.AssembledCitedFactKeys)
		snap.ProvenanceAssemblyPass = diag.ProvenanceAssembly == provider.StagePass
	}
	if len(draft.CitedFactKeys) > 0 {
		snap.TopLevelCitedFactKeys = cloneStringSlice(draft.CitedFactKeys)
	}
	if snap.ProvenanceAssemblyPass {
		snap.ActualCitedFactKeys = cloneStringSlicePreserveOrder(snap.AssembledCitedFactKeys)
	} else if len(diag.AssembledCitedFactKeys) > 0 {
		snap.ActualCitedFactKeys = cloneStringSlicePreserveOrder(diag.AssembledCitedFactKeys)
	} else if len(diag.ActualModelCitedFactKeys) > 0 {
		snap.ActualCitedFactKeys = cloneStringSlice(diag.ActualModelCitedFactKeys) // legacy pre-B5E model citation
	} else if len(snap.TopLevelCitedFactKeys) > 0 {
		snap.ActualCitedFactKeys = cloneStringSlice(snap.TopLevelCitedFactKeys)
	}
	if diag.ProvenanceAssemblyFailureCode != "" {
		snap.ProvenanceAssemblyFailureCode = diag.ProvenanceAssemblyFailureCode
	} else if diag.ProvenanceAssembly == provider.StageFail && diag.DTODecodeErrorKind == "provenanceAssembly" {
		snap.ProvenanceAssemblyFailureCode = diag.ProvenanceAssemblyFailureCode
	}
	for _, exp := range draft.RiskExplanations {
		if snap.ExpectedPrimarySource != "" {
			for _, key := range exp.CitedFactKeys {
				if key == snap.ExpectedPrimarySource {
					snap.PrimarySourcePresent = true
					break
				}
			}
		}
	}
	if snap.ExpectedPrimarySource != "" && len(snap.AssembledCitedFactKeys) > 0 && !snap.PrimarySourcePresent {
		for _, key := range snap.AssembledCitedFactKeys {
			if key == snap.ExpectedPrimarySource {
				snap.PrimarySourcePresent = true
				break
			}
		}
	}
	if snap.ExpectedPrimarySource != "" && len(snap.ActualCitedFactKeys) > 0 && !snap.PrimarySourcePresent {
		for _, key := range snap.ActualCitedFactKeys {
			if key == snap.ExpectedPrimarySource {
				snap.PrimarySourcePresent = true
				break
			}
		}
	}

	return snap
}

func shouldCaptureEvalDiagnosticSnapshot(caseID string) bool {
	if includeNarrativeEnabled() {
		return true
	}
	_, ok := manualReviewSmokeCaseIDs[caseID]
	return ok
}

func transportFailureStageForSnapshot(diag provider.DecodeDiagnostics, explanationStage string) string {
	if explanationStage == provider.StageFail {
		return "explanationAlignment"
	}
	return transportFailureStage(diag)
}

// InferAlignmentFailureCodeFromCase provides a conservative default when artifact lacks provider code.
func InferAlignmentFailureCodeFromCase(caseID string) string {
	switch caseID {
	case "E01_partial_debt_data":
		return "riskExplanationCoverageMismatch"
	default:
		return "unknown"
	}
}

// BuildDiagnosticSnapshotFromAssessment reconstructs expected sets for offline artifact audit.
func BuildDiagnosticSnapshotFromAssessment(c EvaluationCase, facts *contract.MonthlySummaryFactsDTO) EvaluationDiagnosticSnapshot {
	_ = factpack.BuildKeySets(facts)
	snap := EvaluationDiagnosticSnapshot{
		ExpectedRiskReasons:    expectedSignalReasonCodes(&c.Assessment),
		ExpectedUnknownReasons: append([]string(nil), c.Assessment.DataCompleteness.RequiredUnknownReasonCodes...),
	}
	sort.Strings(snap.ExpectedUnknownReasons)
	signals := nonSafeSignals(c.Assessment)
	if len(signals) > 0 {
		snap.ExpectedSignalSourceFactKeys = append([]string(nil), signals[0].SourceFactKeys...)
		snap.ExpectedPrimarySource = primarySourceFactKey(signals[0])
	}
	return snap
}

func containsSecretDiagnostic(text string) bool {
	lower := strings.ToLower(text)
	return strings.Contains(lower, "sk-") || strings.Contains(lower, "bearer ")
}
