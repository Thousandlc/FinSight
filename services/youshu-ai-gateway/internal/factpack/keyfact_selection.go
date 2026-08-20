package factpack

import (
	"sort"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
)

// ForbiddenKeyFactSources returns fact keys that may exist in FactPack but must not
// be selected as salient keyFacts for the given assessment context.
func ForbiddenKeyFactSources(assessment *contract.FinancialRiskAssessmentDTO) []string {
	if assessment == nil {
		return nil
	}
	switch assessment.DebtDataState {
	case "knownNoDebt":
		return []string{"monthlyDebtPayment"}
	default:
		return nil
	}
}

// BuildKeySetsForRequest derives allowed key sets including assessment-aware keyFact selection policy.
func BuildKeySetsForRequest(
	facts *contract.MonthlySummaryFactsDTO,
	assessment *contract.FinancialRiskAssessmentDTO,
) KeySets {
	keys := BuildKeySets(facts)
	forbidden := ForbiddenKeyFactSources(assessment)
	keys.ForbiddenKeyFactKeys = append([]string(nil), forbidden...)
	keys.AllowedKeyFactKeys = subtractKeys(keys.AllowedFactKeys, forbidden)
	return keys
}

func subtractKeys(allowed []string, forbidden []string) []string {
	if len(forbidden) == 0 {
		return append([]string(nil), allowed...)
	}
	block := make(map[string]struct{}, len(forbidden))
	for _, key := range forbidden {
		block[key] = struct{}{}
	}
	out := make([]string, 0, len(allowed))
	for _, key := range allowed {
		if _, ok := block[key]; ok {
			continue
		}
		out = append(out, key)
	}
	sort.Strings(out)
	return out
}
