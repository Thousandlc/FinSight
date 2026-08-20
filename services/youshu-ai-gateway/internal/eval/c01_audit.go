package eval

import (
	"fmt"
	"strings"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
)

// ForbiddenClaimAudit captures structured forbidden-claim analysis for a run.
type ForbiddenClaimAudit struct {
	CaseID                        string   `json:"caseId"`
	RunIndex                      int      `json:"runIndex"`
	DebtKnownZero                 bool     `json:"debtKnownZero"`
	DebtMissing                   bool     `json:"debtMissing"`
	ForbiddenClaimType            string   `json:"forbiddenClaimType,omitempty"`
	ForbiddenFactKeys             []string `json:"forbiddenFactKeys,omitempty"`
	ViolatedForbiddenFactKeys     []string `json:"violatedForbiddenFactKeys,omitempty"`
	ReferencePaths                []string `json:"referencePaths,omitempty"`
	ConfirmedSemanticHallucination bool    `json:"confirmedSemanticHallucination"`
	Severity                      string   `json:"severity"`
	EvaluatorFalsePositive        bool     `json:"evaluatorFalsePositive"`
	Notes                         []string `json:"notes,omitempty"`
}

// ForbiddenScopeAudit captures split forbidden-scope violations for one run.
type ForbiddenScopeAudit struct {
	ForbiddenKeyFactSources         []string `json:"forbiddenKeyFactSources,omitempty"`
	ForbiddenCitationFactKeys       []string `json:"forbiddenCitationFactKeys,omitempty"`
	ViolatedForbiddenKeyFactSources []string `json:"violatedForbiddenKeyFactSources,omitempty"`
	ViolatedForbiddenCitationFactKeys []string `json:"violatedForbiddenCitationFactKeys,omitempty"`
	LegacyForbiddenFactKeys         []string `json:"legacyForbiddenFactKeys,omitempty"`
	ViolatedForbiddenFactKeys       []string `json:"violatedForbiddenFactKeys,omitempty"`
	ReferencePaths                  []string `json:"referencePaths,omitempty"`
}

// AuditC01ForbiddenClaim inspects C01_no_debt forbidden fact/claim violations.
func AuditC01ForbiddenClaim(c EvaluationCase, r RunResult) ForbiddenClaimAudit {
	audit := ForbiddenClaimAudit{
		CaseID:    r.CaseID,
		RunIndex:  r.RunIndex,
		Severity:  r.FailureSeverity,
	}

	debt := AnalyzeDebtFacts(c)
	audit.DebtKnownZero = debt.DebtFactsKnownZero
	audit.DebtMissing = debt.DebtFactsMissing

	if r.FailureClass == FailureSemanticForbidden ||
		r.FailureClass == FailureForbiddenKeyFactSource ||
		r.FailureClass == FailureForbiddenCitationFact ||
		r.FailureClass == FailureFactReference {
		audit.ForbiddenClaimType = "forbiddenFactKeyOrClaim"
	} else if len(r.Semantic.ForbiddenClaimHits) > 0 {
		audit.ForbiddenClaimType = "forbiddenClaim"
	}

	scope := ResolveForbiddenScopes(c)
	audit.ForbiddenFactKeys = append([]string(nil), scope.LegacyForbiddenKeys...)
	scopeAudit := auditForbiddenScopeViolations(scope, r.StructuredSnapshot)
	audit.ViolatedForbiddenFactKeys = appendUniqueStrings(scopeAudit.ViolatedForbiddenKeyFactSources, scopeAudit.ViolatedForbiddenCitationFactKeys...)
	audit.ReferencePaths = scopeAudit.ReferencePaths

	if audit.DebtKnownZero && len(scopeAudit.ViolatedForbiddenKeyFactSources) > 0 {
		audit.ConfirmedSemanticHallucination = true
		audit.Severity = SeverityCritical
		audit.Notes = append(audit.Notes, "known-zero no-debt case used forbidden salient keyFact source")
	} else if audit.DebtKnownZero && len(scopeAudit.ViolatedForbiddenCitationFactKeys) > 0 {
		audit.Notes = append(audit.Notes, "known-zero citation present; post-C2CB citation scope allows registered known-zero facts")
	} else if len(r.Semantic.ForbiddenClaimHits) > 0 {
		audit.ConfirmedSemanticHallucination = true
		if audit.Severity == "" {
			audit.Severity = SeverityMajor
		}
		audit.Notes = append(audit.Notes, "forbidden narrative claim detected")
	}

	if !audit.ConfirmedSemanticHallucination && r.EvaluationVerdict == EvaluationVerdictEvaluatorFalsePositive {
		audit.EvaluatorFalsePositive = true
	}

	return audit
}

func auditForbiddenScopeViolations(scope ForbiddenScopeResolution, snap StructuredSnapshot) ForbiddenScopeAudit {
	out := ForbiddenScopeAudit{
		ForbiddenKeyFactSources:   cloneStringSlice(scope.KeyFactSources),
		ForbiddenCitationFactKeys: cloneStringSlice(scope.CitationFactKeys),
		LegacyForbiddenFactKeys:   cloneStringSlice(scope.LegacyForbiddenKeys),
	}
	keyViolated, keyPaths := findForbiddenKeyFactSourceViolations(scope.KeyFactSources, snap)
	citeViolated, citePaths := findForbiddenCitationFactKeyViolations(scope.CitationFactKeys, snap)
	out.ViolatedForbiddenKeyFactSources = keyViolated
	out.ViolatedForbiddenCitationFactKeys = citeViolated
	out.ReferencePaths = append(keyPaths, citePaths...)
	return out
}

func findForbiddenKeyFactSourceViolations(forbidden []string, snap StructuredSnapshot) (violated []string, paths []string) {
	if len(forbidden) == 0 {
		return nil, nil
	}
	forbiddenSet := stringSet(forbidden)
	for _, src := range snap.KeyFactSources {
		if _, ok := forbiddenSet[src]; ok {
			violated = appendUniqueString(violated, src)
			paths = appendUniqueString(paths, fmt.Sprintf("keyFacts.source:%s", src))
		}
	}
	for _, src := range snap.WarningSources {
		if _, ok := forbiddenSet[src]; ok {
			violated = appendUniqueString(violated, src)
			paths = appendUniqueString(paths, fmt.Sprintf("warnings.source:%s", src))
		}
	}
	return violated, paths
}

func findForbiddenCitationFactKeyViolations(forbidden []string, snap StructuredSnapshot) (violated []string, paths []string) {
	if len(forbidden) == 0 {
		return nil, nil
	}
	forbiddenSet := stringSet(forbidden)
	for _, key := range snap.CitedFactKeys {
		if _, ok := forbiddenSet[key]; ok {
			violated = appendUniqueString(violated, key)
			paths = appendUniqueString(paths, fmt.Sprintf("citedFactKeys:%s", key))
		}
	}
	return violated, paths
}

func findForbiddenFactKeyViolations(forbidden []string, snap StructuredSnapshot) (violated []string, paths []string) {
	keyViolated, keyPaths := findForbiddenKeyFactSourceViolations(forbidden, snap)
	citeViolated, citePaths := findForbiddenCitationFactKeyViolations(forbidden, snap)
	violated = appendUniqueStrings(keyViolated, citeViolated...)
	paths = append(keyPaths, citePaths...)
	return violated, paths
}

func appendUniqueStrings(items []string, extra ...string) []string {
	out := append([]string(nil), items...)
	for _, item := range extra {
		out = appendUniqueString(out, item)
	}
	return out
}

func appendUniqueString(items []string, item string) []string {
	for _, existing := range items {
		if existing == item {
			return items
		}
	}
	return append(items, item)
}

// DraftFromSnapshot reconstructs a minimal draft for offline semantic rescoring.
func DraftFromSnapshot(snap StructuredSnapshot) contract.AssistantAnswerDraftDTO {
	draft := contract.AssistantAnswerDraftDTO{
		Title:         "eval-rescore",
		Body:          snap.Body,
		Answer:        snap.Answer,
		CitedFactKeys: cloneStringSlice(snap.CitedFactKeys),
		Unknowns:      cloneStringSlice(snap.Unknowns),
	}
	for _, src := range snap.KeyFactSources {
		kind := "balance"
		if len(snap.KeyFactKinds) > 0 {
			kind = snap.KeyFactKinds[0]
		}
		draft.KeyFacts = append(draft.KeyFacts, contract.KeyFact{
			Source: src,
			Kind:   kind,
			Label:  src,
			Value:  contract.KeyFactValue{Type: "money"},
		})
	}
	for i, sev := range snap.WarningSeverities {
		src := ""
		if i < len(snap.WarningSources) {
			src = snap.WarningSources[i]
		}
		draft.Warnings = append(draft.Warnings, contract.Warning{
			Severity: sev,
			Source:   src,
			Title:    "w",
			Message:  "m",
		})
	}
	for _, dest := range snap.ActionDestinations {
		draft.Actions = append(draft.Actions, contract.Action{
			Destination: dest,
			Title:       "a",
		})
	}
	return draft
}

// RescoreRunOffline re-evaluates semantic expectations without calling upstream AI.
func RescoreRunOffline(c EvaluationCase, snap StructuredSnapshot) SemanticResult {
	return CheckExpectations(c, DraftFromSnapshot(snap))
}

// RescoreRunOfflineV2 re-evaluates v2 semantic expectations from a saved snapshot.
func RescoreRunOfflineV2(c EvaluationCase, snap StructuredSnapshot, explanationPass, provenancePass bool) V2SemanticResult {
	return CheckExplanationExpectationsV2(c, DraftFromSnapshot(snap), explanationPass, provenancePass)
}

// contractStageAuditNote returns a diagnostic note for non-assessed contract-stage failures.
func contractStageAuditNote(stages ContractStages) string {
	switch {
	case stages.FactValidation == "fail":
		return "fact validation failure; semantic stages not assessed"
	case stages.GatewaySchemaValidation == "fail":
		return "schema validation failure; semantic stages not assessed"
	case stages.ExplanationAlignment == "fail":
		return "explanation alignment failure; semantic stages not assessed"
	case stages.ProvenanceAssembly == "fail":
		return "provenance assembly failure; semantic stages not assessed"
	case stages.DraftDTODecode == "fail":
		return "model DTO decode failure; semantic stages not assessed"
	case !stages.HTTP2xxSuccess && !stages.HTTPSuccess:
		return "transport/provider failure; semantic stages not assessed"
	default:
		return ""
	}
}

func formatContractStageAuditNote(stages ContractStages) string {
	note := strings.TrimSpace(contractStageAuditNote(stages))
	if note != "" {
		return note
	}
	return "transport/provider failure; semantic stages not assessed"
}
