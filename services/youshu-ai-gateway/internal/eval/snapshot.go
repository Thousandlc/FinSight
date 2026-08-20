package eval

import (
	"os"
	"strings"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
)

// StructuredSnapshot holds safe structured fields for semantic audit.
// Never includes amounts, body, answer, prompt, context, or API keys.
type StructuredSnapshot struct {
	ExpectedRiskLevel RiskLevel `json:"expectedRiskLevel"`

	WarningCount       int      `json:"warningCount"`
	WarningSeverities  []string `json:"warningSeverities"`
	WarningSources     []string `json:"warningSources"`
	ActionDestinations []string `json:"actionDestinations"`
	UnknownCount       int      `json:"unknownCount"`
	Unknowns           []string `json:"unknowns,omitempty"`
	CitedFactKeys      []string `json:"citedFactKeys"`
	KeyFactKinds       []string `json:"keyFactKinds"`
	KeyFactSources     []string `json:"keyFactSources"`

	ActualDerivedRisk     RiskLevel `json:"actualDerivedRisk"`
	RiskMismatchDirection string    `json:"riskMismatchDirection,omitempty"`
	UnknownExpectation    string    `json:"unknownExpectation,omitempty"`
	StructuredConclusionPass bool   `json:"structuredConclusionPass,omitempty"`

	// Optional narrative for synthetic eval audit only (YOUSHU_EVAL_INCLUDE_NARRATIVE=1).
	Body   string `json:"body,omitempty"`
	Answer string `json:"answer,omitempty"`
}

// BuildStructuredSnapshot extracts audit-safe structured fields from a draft.
func BuildStructuredSnapshot(c EvaluationCase, draft contract.AssistantAnswerDraftDTO) StructuredSnapshot {
	warningSeverities := make([]string, 0, len(draft.Warnings))
	warningSources := make([]string, 0, len(draft.Warnings))
	for _, w := range draft.Warnings {
		warningSeverities = append(warningSeverities, w.Severity)
		warningSources = append(warningSources, w.Source)
	}

	actionDestinations := make([]string, 0, len(draft.Actions))
	for _, a := range draft.Actions {
		actionDestinations = append(actionDestinations, a.Destination)
	}

	keyFactKinds := make([]string, 0, len(draft.KeyFacts))
	keyFactSources := make([]string, 0, len(draft.KeyFacts))
	for _, f := range draft.KeyFacts {
		keyFactKinds = append(keyFactKinds, f.Kind)
		keyFactSources = append(keyFactSources, f.Source)
	}

	riskAudit := BuildRiskAudit(c.ExpectedRiskLevel, draft.Warnings)

	snap := StructuredSnapshot{
		ExpectedRiskLevel:     c.ExpectedRiskLevel,
		UnknownExpectation:    string(ResolveUnknownExpectation(c)),
		WarningCount:          len(draft.Warnings),
		WarningSeverities:     warningSeverities,
		WarningSources:        warningSources,
		ActionDestinations:    actionDestinations,
		UnknownCount:          len(draft.Unknowns),
		CitedFactKeys:         cloneStringSlice(draft.CitedFactKeys),
		KeyFactKinds:          keyFactKinds,
		KeyFactSources:        keyFactSources,
		ActualDerivedRisk:     riskAudit.ActualDerivedRisk,
		RiskMismatchDirection: riskAudit.MismatchDirection,
	}

	if ResolveUnknownExpectation(c) == UnknownRequired && len(draft.Unknowns) > 0 {
		snap.Unknowns = cloneStringSlice(draft.Unknowns)
	} else if includeNarrativeEnabled() {
		snap.Unknowns = cloneStringSlice(draft.Unknowns)
	}

	if includeNarrativeEnabled() {
		snap.Body = draft.Body
		snap.Answer = draft.Answer
	}

	return snap
}

func includeNarrativeEnabled() bool {
	v := strings.TrimSpace(os.Getenv("YOUSHU_EVAL_INCLUDE_NARRATIVE"))
	return v == "1" || strings.EqualFold(v, "true")
}

func cloneStringSlice(items []string) []string {
	if items == nil {
		return []string{}
	}
	out := make([]string, len(items))
	copy(out, items)
	return out
}

func cloneStringSlicePreserveOrder(items []string) []string {
	if items == nil {
		return []string{}
	}
	out := make([]string, len(items))
	copy(out, items)
	return out
}
