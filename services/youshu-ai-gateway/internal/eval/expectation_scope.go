package eval

import "fmt"

// ForbiddenScopeResolution holds resolved evaluator forbidden-fact scopes for one case.
type ForbiddenScopeResolution struct {
	KeyFactSources      []string
	CitationFactKeys    []string
	LegacyCombined      bool
	LegacyForbiddenKeys []string
}

// ResolveForbiddenScopes returns explicit post-C2CB scopes with documented legacy fallback.
//
// Precedence:
//  1. Explicit ForbiddenKeyFactSources / ForbiddenCitationFactKeys when either is non-empty.
//  2. Legacy ForbiddenFactKeys applied to BOTH scopes (historical combined semantics).
func ResolveForbiddenScopes(c EvaluationCase) ForbiddenScopeResolution {
	out := ForbiddenScopeResolution{
		LegacyForbiddenKeys: cloneScopeStringSlice(c.ForbiddenFactKeys),
	}
	if len(c.ForbiddenKeyFactSources) > 0 || len(c.ForbiddenCitationFactKeys) > 0 {
		out.KeyFactSources = cloneScopeStringSlice(c.ForbiddenKeyFactSources)
		out.CitationFactKeys = cloneScopeStringSlice(c.ForbiddenCitationFactKeys)
		return out
	}
	if len(c.ForbiddenFactKeys) > 0 {
		out.LegacyCombined = true
		out.KeyFactSources = cloneScopeStringSlice(c.ForbiddenFactKeys)
		out.CitationFactKeys = cloneScopeStringSlice(c.ForbiddenFactKeys)
	}
	return out
}

// ValidateForbiddenScopeSemantics ensures migrated cases declare explicit scopes.
func ValidateForbiddenScopeSemantics(cases []EvaluationCase) error {
	explicitCases := map[string]struct{}{
		"C01_no_debt":              {},
		"E01_partial_debt_data":    {},
		"E04_partial_facts_missing": {},
		"E05_missing_debt_data":    {},
	}
	for _, c := range cases {
		if _, ok := explicitCases[c.ID]; !ok {
			if len(c.ForbiddenKeyFactSources) > 0 || len(c.ForbiddenCitationFactKeys) > 0 {
				return fmt.Errorf("case %s: unexpected explicit forbidden scope fields", c.ID)
			}
			continue
		}
		if len(c.ForbiddenKeyFactSources) == 0 && len(c.ForbiddenCitationFactKeys) == 0 && len(c.ForbiddenFactKeys) == 0 {
			return fmt.Errorf("case %s: missing explicit forbidden scope migration", c.ID)
		}
	}
	return nil
}

func cloneScopeStringSlice(items []string) []string {
	if len(items) == 0 {
		return nil
	}
	return append([]string(nil), items...)
}
