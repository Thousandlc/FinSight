package handler

import (
	"fmt"
	"sort"
	"strings"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
)

// Structured output enum sets aligned with Swift Domain raw values.
var (
	AllowedKeyFactKinds = []string{
		"balance", "income", "expense", "debt", "cashFlow", "savings", "purchase", "other",
	}
	AllowedWarningSeverities = []string{"safe", "warning", "risk"}
	AllowedActionDestinations = []string{"cashFlow", "debt", "transactions", "accounts"}
	AllowedKeyFactValueTypes = []string{"money", "text", "percent", "date"}
)

// EnumValueDiagnostics records safe enum tokens from a decoded draft.
type EnumValueDiagnostics struct {
	KeyFactKinds         []string
	KeyFactValueTypes    []string
	WarningSeverities    []string
	ActionDestinations   []string
}

// EnumComplianceDiagnostics reports per-field enum/value contract checks.
type EnumComplianceDiagnostics struct {
	KeyFactKindValid         bool
	KeyFactValueValid        bool
	WarningSeverityValid     bool
	ActionDestinationValid   bool
	InvalidEnumField         string
	InvalidEnumValue         string
}

func (d EnumComplianceDiagnostics) AllValid() bool {
	return d.KeyFactKindValid && d.KeyFactValueValid && d.WarningSeverityValid && d.ActionDestinationValid
}

func ExtractEnumValues(d contract.AssistantAnswerDraftDTO) EnumValueDiagnostics {
	kinds := make([]string, 0, len(d.KeyFacts))
	valueTypes := make([]string, 0, len(d.KeyFacts))
	for _, fact := range d.KeyFacts {
		kinds = append(kinds, fact.Kind)
		valueTypes = append(valueTypes, fact.Value.Type)
	}
	severities := make([]string, 0, len(d.Warnings))
	for _, warning := range d.Warnings {
		severities = append(severities, warning.Severity)
	}
	destinations := make([]string, 0, len(d.Actions))
	for _, action := range d.Actions {
		destinations = append(destinations, action.Destination)
	}
	return EnumValueDiagnostics{
		KeyFactKinds:       kinds,
		KeyFactValueTypes:  valueTypes,
		WarningSeverities:  severities,
		ActionDestinations: destinations,
	}
}

func DiagnoseEnumCompliance(d contract.AssistantAnswerDraftDTO) EnumComplianceDiagnostics {
	diag := EnumComplianceDiagnostics{
		KeyFactKindValid:       true,
		KeyFactValueValid:      true,
		WarningSeverityValid:   true,
		ActionDestinationValid: true,
	}
	for _, fact := range d.KeyFacts {
		if !isValidKind(fact.Kind) {
			diag.KeyFactKindValid = false
			diag.InvalidEnumField = "keyFacts.kind"
			diag.InvalidEnumValue = fact.Kind
			return diag
		}
		if !isValidKeyFactValueType(fact.Value.Type) {
			diag.KeyFactValueValid = false
			diag.InvalidEnumField = "keyFacts.value.type"
			diag.InvalidEnumValue = fact.Value.Type
			return diag
		}
		if !isValidKeyFactValue(fact.Value) {
			diag.KeyFactValueValid = false
			diag.InvalidEnumField = keyFactValueInvalidField(fact.Value)
			diag.InvalidEnumValue = keyFactValueInvalidValue(fact.Value)
			return diag
		}
	}
	for _, warning := range d.Warnings {
		if !isValidSeverity(warning.Severity) {
			diag.WarningSeverityValid = false
			diag.InvalidEnumField = "warnings.severity"
			diag.InvalidEnumValue = warning.Severity
			return diag
		}
	}
	for _, action := range d.Actions {
		if !isValidDestination(action.Destination) {
			diag.ActionDestinationValid = false
			diag.InvalidEnumField = "actions.destination"
			diag.InvalidEnumValue = action.Destination
			return diag
		}
	}
	return diag
}

func AllowedEnumSet(name string) []string {
	switch name {
	case "keyFacts.kind":
		return append([]string(nil), AllowedKeyFactKinds...)
	case "keyFacts.value.type":
		return append([]string(nil), AllowedKeyFactValueTypes...)
	case "warnings.severity":
		return append([]string(nil), AllowedWarningSeverities...)
	case "actions.destination":
		return append([]string(nil), AllowedActionDestinations...)
	default:
		return nil
	}
}

func isValidKeyFactValueType(valueType string) bool {
	return containsString(AllowedKeyFactValueTypes, valueType)
}

func keyFactValueInvalidField(v contract.KeyFactValue) string {
	switch v.Type {
	case "money":
		if v.Amount == nil {
			return "keyFacts.value.amount"
		}
		if v.CurrencyCode == nil || strings.TrimSpace(*v.CurrencyCode) == "" {
			return "keyFacts.value.currencyCode"
		}
	case "text":
		if v.TextValue == nil || strings.TrimSpace(*v.TextValue) == "" {
			return "keyFacts.value.value"
		}
	case "percent":
		if v.PercentValue == nil {
			return "keyFacts.value.value"
		}
	case "date":
		if v.Date == nil || strings.TrimSpace(*v.Date) == "" {
			return "keyFacts.value.date"
		}
	default:
		return "keyFacts.value.type"
	}
	return "keyFacts.value"
}

func keyFactValueInvalidValue(v contract.KeyFactValue) string {
	switch v.Type {
	case "money":
		if v.Amount == nil {
			return "<missing>"
		}
		if v.CurrencyCode == nil || strings.TrimSpace(*v.CurrencyCode) == "" {
			if v.CurrencyCode == nil {
				return "<missing>"
			}
			return *v.CurrencyCode
		}
	case "text":
		if v.TextValue == nil {
			return "<missing>"
		}
		return *v.TextValue
	case "percent":
		if v.PercentValue == nil {
			return "<missing>"
		}
		return fmt.Sprintf("%v", *v.PercentValue)
	case "date":
		if v.Date == nil {
			return "<missing>"
		}
		return *v.Date
	default:
		return v.Type
	}
	return ""
}

func containsString(values []string, target string) bool {
	for _, value := range values {
		if value == target {
			return true
		}
	}
	return false
}

func sortedCopy(values []string) []string {
	out := append([]string(nil), values...)
	sort.Strings(out)
	return out
}
