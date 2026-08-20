package eval

import (
	"strings"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
)

// StructuredConclusionAudit checks whether required conclusions are expressed via structured fields.
type StructuredConclusionAudit struct {
	RequiredFactKeysPresent     bool     `json:"requiredFactKeysPresent"`
	RequiredFactKeysMissing     []string `json:"requiredFactKeysMissing,omitempty"`
	CashFlowWarningPresent      bool     `json:"cashFlowWarningPresent"`
	MinimumSafeKeyFactsPresent  bool     `json:"minimumSafeKeyFactsPresent"`
	DebtWarningPresent          bool     `json:"debtWarningPresent"`
	StructuredConclusionPresent bool     `json:"structuredConclusionPresent"`
	NarrativeKeywordRequired    []string `json:"narrativeKeywordRequired,omitempty"`
	NarrativeKeywordRule        string   `json:"narrativeKeywordRule"`
}
func AuditStructuredConclusion(c EvaluationCase, snap StructuredSnapshot) StructuredConclusionAudit {
	audit := StructuredConclusionAudit{
		NarrativeKeywordRequired: c.DiagnosticKeywords,
		NarrativeKeywordRule:     "diagnostic only; not a hard fail condition",
	}

	exp := c.StructuredConclusion
	if exp.IsZero() {
		exp = StructuredConclusionExpectation{RequiredFactKeys: c.RequiredFactKeys}
	}

	requiredKeys := map[string]bool{}
	for _, key := range exp.RequiredFactKeys {
		requiredKeys[key] = false
	}
	allKeys := append(append([]string{}, snap.CitedFactKeys...), snap.KeyFactSources...)
	for _, key := range allKeys {
		if _, ok := requiredKeys[key]; ok {
			requiredKeys[key] = true
		}
	}
	for key, found := range requiredKeys {
		if !found {
			audit.RequiredFactKeysMissing = append(audit.RequiredFactKeysMissing, key)
		}
	}
	audit.RequiredFactKeysPresent = len(audit.RequiredFactKeysMissing) == 0

	for _, src := range snap.WarningSources {
		if src == "cashFlowRiskExplanation" || src == "minimumBalance" || src == "safeBalance" {
			audit.CashFlowWarningPresent = true
		}
		if src == "minimumBalance" || src == "safeBalance" {
			audit.MinimumSafeKeyFactsPresent = true
		}
		if src == "monthlyDebtPayment" || src == "debtPaymentToIncomePercent" || src == "primaryPressure" {
			audit.DebtWarningPresent = true
		}
	}
	for _, src := range snap.KeyFactSources {
		if src == "minimumBalance" || src == "safeBalance" {
			audit.MinimumSafeKeyFactsPresent = true
		}
		if src == "monthlyDebtPayment" || src == "debtPaymentToIncomePercent" {
			audit.DebtWarningPresent = true
		}
	}

	switch {
	case c.ID == "B01_minimum_below_safe":
		audit.StructuredConclusionPresent = audit.RequiredFactKeysPresent &&
			(audit.CashFlowWarningPresent || audit.MinimumSafeKeyFactsPresent) &&
			snap.WarningCount > 0
	case !exp.IsZero():
		passed, _ := CheckStructuredConclusion(exp, draftFromSnapshot(snap))
		audit.StructuredConclusionPresent = passed
	default:
		audit.StructuredConclusionPresent = audit.RequiredFactKeysPresent
	}

	return audit
}

// ConclusionCheckerDescription documents how conclusion is evaluated.
func ConclusionCheckerDescription(c EvaluationCase) string {
	if !c.StructuredConclusion.IsZero() {
		return "structured conclusion: " + describeStructuredConclusion(c.StructuredConclusion)
	}
	if len(c.RequiredFactKeys) > 0 {
		return "required fact keys: " + joinStrings(c.RequiredFactKeys)
	}
	if len(c.DiagnosticKeywords) > 0 {
		return "diagnostic keywords only: " + joinStrings(c.DiagnosticKeywords)
	}
	return "no conclusion requirements"
}

func describeStructuredConclusion(exp StructuredConclusionExpectation) string {
	parts := []string{}
	if len(exp.RequiredFactKeys) > 0 {
		parts = append(parts, "factKeys="+joinStrings(exp.RequiredFactKeys))
	}
	if len(exp.RequiredAnyWarningSources) > 0 {
		parts = append(parts, "warningSources="+joinStrings(exp.RequiredAnyWarningSources))
	}
	if exp.RequireWarning {
		parts = append(parts, "requireWarning=true")
	}
	return joinStrings(parts)
}

func draftFromSnapshot(snap StructuredSnapshot) contract.AssistantAnswerDraftDTO {
	warnings := make([]contract.Warning, 0, len(snap.WarningSources))
	for i, src := range snap.WarningSources {
		sev := "warning"
		if i < len(snap.WarningSeverities) {
			sev = snap.WarningSeverities[i]
		}
		warnings = append(warnings, contract.Warning{Source: src, Severity: sev, Title: "audit", Message: "audit"})
	}
	keyFacts := make([]contract.KeyFact, 0, len(snap.KeyFactSources))
	for i, src := range snap.KeyFactSources {
		kind := "other"
		if i < len(snap.KeyFactKinds) {
			kind = snap.KeyFactKinds[i]
		}
		keyFacts = append(keyFacts, contract.KeyFact{Source: src, Kind: kind, Label: "audit", Value: contract.KeyFactValue{Type: "text", TextValue: strPtr("audit")}})
	}
	refs := make([]contract.Reference, 0, len(snap.CitedFactKeys))
	for _, key := range snap.CitedFactKeys {
		refs = append(refs, contract.Reference{Key: key})
	}
	return contract.AssistantAnswerDraftDTO{
		CitedFactKeys: snap.CitedFactKeys,
		KeyFacts:      keyFacts,
		Warnings:      warnings,
		References:    refs,
		Unknowns:      snap.Unknowns,
	}
}

func strPtr(s string) *string { return &s }

func joinStrings(items []string) string {
	if len(items) == 0 {
		return ""
	}
	return strings.Join(items, ", ")
}
