package smoke

import (
	"math"
	"regexp"
	"strconv"
	"strings"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/factpack"
)

var yuanAmountPattern = regexp.MustCompile(`¥\s*([0-9]+(?:,[0-9]{3})*(?:\.[0-9]+)?)`)

var validDestinations = map[string]struct{}{
	"cashFlow": {}, "debt": {}, "transactions": {}, "accounts": {},
}

// FactValidationResult captures domain-style fact checks for smoke acceptance.
type FactValidationResult struct {
	InventedFactCount     int
	InvalidReferenceCount int
	InvalidActionCount    int
	InvalidCitedKeyCount  int
	InvalidKeyFactCount   int
	Errors                []string
}

func (r FactValidationResult) Passed() bool {
	return r.InventedFactCount == 0 &&
		r.InvalidReferenceCount == 0 &&
		r.InvalidActionCount == 0 &&
		r.InvalidCitedKeyCount == 0 &&
		r.InvalidKeyFactCount == 0 &&
		len(r.Errors) == 0
}

func AllowedKeys(facts *contract.MonthlySummaryFactsDTO) (amountKeys map[string]contract.MoneyDTO, factKeys map[string]string, refKeys map[string]struct{}) {
	return factpack.AllowedKeys(facts)
}

func mergeKeySets(amounts map[string]contract.MoneyDTO, facts map[string]string) map[string]struct{} {
	out := make(map[string]struct{})
	for k := range amounts {
		out[k] = struct{}{}
	}
	for k := range facts {
		out[k] = struct{}{}
	}
	return out
}

func buildAmountMap(facts *contract.MonthlySummaryFactsDTO) map[string]bool {
	amounts, _, _ := AllowedKeys(facts)
	set := make(map[string]bool)
	for _, m := range amounts {
		set[normalizeAmount(parseAmount(m.Amount))] = true
	}
	return set
}

func extractYuanAmounts(text string) []string {
	matches := yuanAmountPattern.FindAllStringSubmatch(text, -1)
	out := make([]string, 0, len(matches))
	for _, m := range matches {
		if len(m) > 1 {
			raw := strings.ReplaceAll(m[1], ",", "")
			out = append(out, normalizeAmount(parseAmount(raw)))
		}
	}
	return out
}

func parseAmount(s string) float64 {
	v, _ := strconv.ParseFloat(strings.TrimSpace(s), 64)
	return v
}

func normalizeAmount(v float64) string {
	return strconv.FormatFloat(math.Round(v*100)/100, 'f', -1, 64)
}
