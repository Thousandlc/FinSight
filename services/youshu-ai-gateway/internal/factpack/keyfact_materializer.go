package factpack

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
)

const (
	CodeUnknownFactSource      = "unknownFactSource"
	CodeMaterializationFailure = "materializationFailure"
)

// MaterializationError is a stable, payload-free Gateway materializer failure.
// Error() is an allowlisted code only — never amounts, sources, or fact values.
type MaterializationError struct {
	Code string
}

func (e *MaterializationError) Error() string {
	if e == nil || strings.TrimSpace(e.Code) == "" {
		return CodeMaterializationFailure
	}
	return e.Code
}

func materializationError(code string) error {
	return &MaterializationError{Code: code}
}

// MaterializeKeyFact builds a gateway keyFact with canonical typed value from FactPack.
func MaterializeKeyFact(
	source, label, kind string,
	facts *contract.MonthlySummaryFactsDTO,
) (contract.KeyFact, error) {
	if facts == nil {
		return contract.KeyFact{}, materializationError(CodeMaterializationFailure)
	}
	amountKeys, factKeys, _ := AllowedKeys(facts)
	if money, ok := amountKeys[source]; ok {
		value, err := materializeMoneyValue(money)
		if err != nil {
			return contract.KeyFact{}, materializationError(CodeMaterializationFailure)
		}
		return contract.KeyFact{
			Label:  label,
			Kind:   kind,
			Source: source,
			Value:  value,
		}, nil
	}
	if text, ok := factKeys[source]; ok && strings.TrimSpace(text) != "" {
		value, err := materializeTextOrPercentValue(source, text)
		if err != nil {
			return contract.KeyFact{}, materializationError(CodeMaterializationFailure)
		}
		return contract.KeyFact{
			Label:  label,
			Kind:   kind,
			Source: source,
			Value:  value,
		}, nil
	}
	return contract.KeyFact{}, materializationError(CodeUnknownFactSource)
}

// MaterializeKeyFacts materializes all model-selected keyFacts from FactPack canonical values.
func MaterializeKeyFacts(
	modelFacts []contract.ModelKeyFactDTO,
	facts *contract.MonthlySummaryFactsDTO,
) ([]contract.KeyFact, error) {
	out := make([]contract.KeyFact, 0, len(modelFacts))
	for _, fact := range modelFacts {
		materialized, err := MaterializeKeyFact(fact.Source, fact.Label, fact.Kind, facts)
		if err != nil {
			return nil, err
		}
		out = append(out, materialized)
	}
	return out, nil
}

func materializeMoneyValue(money contract.MoneyDTO) (contract.KeyFactValue, error) {
	amount, err := parseCanonicalAmount(money.Amount)
	if err != nil {
		return contract.KeyFactValue{}, fmt.Errorf("invalid money amount")
	}
	currency := strings.TrimSpace(money.CurrencyCode)
	if currency == "" {
		return contract.KeyFactValue{}, fmt.Errorf("missing currencyCode")
	}
	return contract.KeyFactValue{
		Type:         "money",
		Amount:       &amount,
		CurrencyCode: &currency,
	}, nil
}

func materializeTextOrPercentValue(source, canonical string) (contract.KeyFactValue, error) {
	trimmed := strings.TrimSpace(canonical)
	if strings.HasSuffix(trimmed, "%") || source == "debtPaymentToIncomePercent" {
		pct, err := parseCanonicalAmount(strings.TrimSuffix(trimmed, "%"))
		if err != nil {
			return contract.KeyFactValue{}, fmt.Errorf("invalid percent value")
		}
		return contract.KeyFactValue{Type: "percent", PercentValue: &pct}, nil
	}
	text := trimmed
	return contract.KeyFactValue{Type: "text", TextValue: &text}, nil
}

func parseCanonicalAmount(raw string) (float64, error) {
	value, err := strconv.ParseFloat(strings.TrimSpace(raw), 64)
	if err != nil {
		return 0, err
	}
	return value, nil
}
