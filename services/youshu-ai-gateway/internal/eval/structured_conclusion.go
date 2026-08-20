package eval

import (
	"strings"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
)

// CheckStructuredConclusion evaluates deterministic structured conclusion rules.
func CheckStructuredConclusion(exp StructuredConclusionExpectation, draft contract.AssistantAnswerDraftDTO) (passed bool, missing []string) {
	if exp.IsZero() {
		return true, nil
	}

	cited := collectCitedKeys(draft)

	for _, key := range exp.RequiredFactKeys {
		if !cited[key] {
			missing = append(missing, "factKey:"+key)
		}
	}

	if len(exp.RequiredAnyWarningSources) > 0 && !anySourcePresent(exp.RequiredAnyWarningSources, warningSources(draft)) {
		missing = append(missing, "warningSource:anyOf("+joinStrings(exp.RequiredAnyWarningSources)+")")
	}

	if len(exp.RequiredAnyReferenceKeys) > 0 && !anySourcePresent(exp.RequiredAnyReferenceKeys, referenceKeys(draft)) {
		missing = append(missing, "referenceKey:anyOf("+joinStrings(exp.RequiredAnyReferenceKeys)+")")
	}

	if exp.RequireWarning && len(draft.Warnings) == 0 {
		missing = append(missing, "warning:required")
	}

	return len(missing) == 0, missing
}

func collectCitedKeys(draft contract.AssistantAnswerDraftDTO) map[string]bool {
	cited := map[string]bool{}
	for _, key := range draft.CitedFactKeys {
		cited[key] = true
	}
	for _, fact := range draft.KeyFacts {
		cited[fact.Source] = true
	}
	return cited
}

func warningSources(draft contract.AssistantAnswerDraftDTO) []string {
	out := make([]string, 0, len(draft.Warnings))
	for _, w := range draft.Warnings {
		out = append(out, w.Source)
	}
	return out
}

func referenceKeys(draft contract.AssistantAnswerDraftDTO) []string {
	out := make([]string, 0, len(draft.References))
	for _, r := range draft.References {
		out = append(out, r.Key)
	}
	return out
}

func anySourcePresent(required, actual []string) bool {
	set := map[string]struct{}{}
	for _, item := range actual {
		set[item] = struct{}{}
	}
	for _, key := range required {
		if _, ok := set[key]; ok {
			return true
		}
	}
	return false
}

// RecordDiagnosticKeywords checks narrative keywords without failing evaluation.
func RecordDiagnosticKeywords(narrative string, keywords []string) []string {
	if len(keywords) == 0 {
		return nil
	}
	var misses []string
	for _, keyword := range keywords {
		if keyword == "" {
			continue
		}
		if !strings.Contains(narrative, strings.ToLower(keyword)) {
			misses = append(misses, keyword)
		}
	}
	return misses
}
