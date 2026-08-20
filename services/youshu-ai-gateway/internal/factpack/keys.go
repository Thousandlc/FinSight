package factpack

import (
	"sort"
	"strings"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
)

// StandardReferenceKeys lists navigation/section reference keys that may be cited even when
// absent from the current MonthlySummaryFacts payload (e.g. cashFlow30 → 现金流页).
// Fact-backed keys (amounts, semantic facts, DTI, debtPressureLevel, purchase facts, etc.)
// must NOT appear here; they register dynamically via AllowedKeys amountKeys/factKeys when present.
var StandardReferenceKeys = []string{
	"cashFlow30",
	"cashFlow",
	"debt",
	"transactions",
	"accounts",
}

// KeySets holds allowed key collections for prompts, JSON Schema, and fact validation.
type KeySets struct {
	AmountKeys map[string]contract.MoneyDTO
	FactKeys   map[string]string
	RefKeys    map[string]struct{}

	AmountKeyList      []string
	FactKeyList        []string
	ReferenceKeyList   []string
	AllowedFactKeys      []string
	AllowedKeyFactKeys   []string
	ForbiddenKeyFactKeys []string
	WarningSourceKeys    []string
}

// BuildKeySets derives all allowed key sets from MonthlySummaryFacts.
func BuildKeySets(facts *contract.MonthlySummaryFactsDTO) KeySets {
	amountKeys, factKeys, refKeys := AllowedKeys(facts)
	return KeySets{
		AmountKeys:        amountKeys,
		FactKeys:          factKeys,
		RefKeys:           refKeys,
		AmountKeyList:     sortedKeys(amountKeys),
		FactKeyList:       sortedStringMapKeys(factKeys),
		ReferenceKeyList:  sortedStructKeys(refKeys),
		AllowedFactKeys:      sortedUnionKeys(amountKeys, factKeys),
		AllowedKeyFactKeys:   sortedUnionKeys(amountKeys, factKeys),
		ForbiddenKeyFactKeys: nil,
		WarningSourceKeys:    sortedWarningSources(amountKeys, factKeys, refKeys),
	}
}

// AllowedKeys returns amount, text-fact, and reference key sets used by fact validation.
func AllowedKeys(facts *contract.MonthlySummaryFactsDTO) (
	amountKeys map[string]contract.MoneyDTO,
	factKeys map[string]string,
	refKeys map[string]struct{},
) {
	amountKeys = map[string]contract.MoneyDTO{
		"availableCash":            facts.AvailableCash,
		"monthlyIncome":            facts.MonthlyIncome,
		"monthlyExpense":           facts.MonthlyExpense,
		"monthlyDebtPayment":       facts.MonthlyDebtPayment,
		"estimatedMonthEndBalance": facts.EstimatedMonthEndBalance,
	}
	if facts.SafeBalance != nil {
		amountKeys["safeBalance"] = *facts.SafeBalance
	}
	if facts.MinimumBalance != nil {
		amountKeys["minimumBalance"] = *facts.MinimumBalance
	}

	factKeys = map[string]string{"primaryPressure": facts.PrimaryPressure}
	if facts.DebtPaymentToIncomePercent != nil {
		factKeys["debtPaymentToIncomePercent"] = strings.TrimSpace(*facts.DebtPaymentToIncomePercent)
	}
	if facts.CashFlowRiskExplanation != nil && strings.TrimSpace(*facts.CashFlowRiskExplanation) != "" {
		factKeys["cashFlowRiskExplanation"] = strings.TrimSpace(*facts.CashFlowRiskExplanation)
	}
	if facts.DebtPressureLevel != nil && strings.TrimSpace(*facts.DebtPressureLevel) != "" {
		factKeys["debtPressureLevel"] = strings.TrimSpace(*facts.DebtPressureLevel)
	}

	refKeys = make(map[string]struct{})
	for _, k := range StandardReferenceKeys {
		refKeys[k] = struct{}{}
	}
	for k := range amountKeys {
		refKeys[k] = struct{}{}
	}
	for k := range factKeys {
		refKeys[k] = struct{}{}
	}
	return amountKeys, factKeys, refKeys
}

func sortedKeys(amounts map[string]contract.MoneyDTO) []string {
	out := make([]string, 0, len(amounts))
	for k := range amounts {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

func sortedStringMapKeys(facts map[string]string) []string {
	out := make([]string, 0, len(facts))
	for k := range facts {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

func sortedStructKeys(keys map[string]struct{}) []string {
	out := make([]string, 0, len(keys))
	for k := range keys {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

func sortedUnionKeys(amounts map[string]contract.MoneyDTO, facts map[string]string) []string {
	set := make(map[string]struct{}, len(amounts)+len(facts))
	for k := range amounts {
		set[k] = struct{}{}
	}
	for k := range facts {
		set[k] = struct{}{}
	}
	return sortedStructKeys(set)
}

func sortedWarningSources(
	amounts map[string]contract.MoneyDTO,
	facts map[string]string,
	refKeys map[string]struct{},
) []string {
	set := make(map[string]struct{}, len(refKeys))
	for k := range amounts {
		set[k] = struct{}{}
	}
	for k := range facts {
		set[k] = struct{}{}
	}
	for k := range refKeys {
		set[k] = struct{}{}
	}
	return sortedStructKeys(set)
}
