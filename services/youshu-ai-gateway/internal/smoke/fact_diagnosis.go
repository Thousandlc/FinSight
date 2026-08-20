package smoke

import (
	"fmt"
	"sort"
	"strings"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/factpack"
)

const (
	FactRuleInventedAmount              = "inventedAmount"
	FactRuleCitedUnknownFact            = "citedUnknownFact"
	FactRuleCitedDuplicate              = "citedDuplicate"
	FactRuleInvalidKeyFactSource        = "invalidKeyFactSource"
	FactRuleKeyFactSourceNotAllowed     = "keyFactSourceNotAllowed"
	FactRuleInvalidKeyFactMoneySource   = "invalidKeyFactMoneySource"
	FactRuleInvalidKeyFactTextSource    = "invalidKeyFactTextSource"
	FactRuleInvalidKeyFactPercentSource = "invalidKeyFactPercentSource"
	FactRuleKeyFactValueMismatch        = "keyFactValueMismatch"
	FactRuleInvalidReference            = "invalidReference"
	FactRuleInvalidWarningSource        = "invalidWarningSource"
	FactRuleInvalidActionDestination    = "invalidActionDestination"
	FactRuleMissingFacts                = "missingFacts"
)

// FactDiagnostics captures granular monthly-summary fact validation results.
type FactDiagnostics struct {
	Passed bool

	AmountFactsValid       bool
	CitedFactKeysValid     bool
	CitedFactKeysDuplicate bool
	KeyFactSourcesValid    bool
	KeyFactValuesValid     bool
	ReferencesValid        bool
	ActionsValid           bool
	WarningSourcesValid    bool
	PercentFactsValid      bool
	DateFactsValid         bool

	InventedFactCount         int
	InvalidReferenceCount     int
	InvalidActionCount        int
	InvalidCitedKeyCount      int
	InvalidKeyFactCount       int
	InvalidWarningSourceCount int

	FailureRules      []string
	InvalidFactRule   string
	InvalidFactKey    string
	InvalidFactSource string
	ExpectedFactKey   string
	ActualFactKey     string

	Errors []string
}

func (d FactDiagnostics) FailureRulesSummary() string {
	return strings.Join(d.FailureRules, ",")
}

// DiagnoseFacts evaluates monthly-summary fact validation rules on a gateway draft.
func DiagnoseFacts(draft contract.AssistantAnswerDraftDTO, facts *contract.MonthlySummaryFactsDTO) FactDiagnostics {
	return DiagnoseFactsWithKeySets(draft, facts, factpack.BuildKeySets(facts))
}

// DiagnoseFactsWithKeySets evaluates fact validation using assessment-aware keyFact selection policy.
func DiagnoseFactsWithKeySets(
	draft contract.AssistantAnswerDraftDTO,
	facts *contract.MonthlySummaryFactsDTO,
	keySets factpack.KeySets,
) FactDiagnostics {
	diag := FactDiagnostics{
		AmountFactsValid:       true,
		CitedFactKeysValid:     true,
		CitedFactKeysDuplicate: false,
		KeyFactSourcesValid:    true,
		KeyFactValuesValid:     true,
		ReferencesValid:        true,
		ActionsValid:           true,
		WarningSourcesValid:    true,
		PercentFactsValid:      true,
		DateFactsValid:         true,
	}
	if facts == nil {
		diag.AmountFactsValid = false
		diag.record(FactRuleMissingFacts, "", "", "", "")
		diag.syncPassed()
		return diag
	}

	amountKeys, factKeys, refKeys := AllowedKeys(facts)
	allowedKeys := mergeKeySets(amountKeys, factKeys)
	allowedKeyFactKeys := buildAllowedKeyFactKeySet(keySets)
	allowedAmounts := buildAmountMap(facts)

	seenCited := map[string]struct{}{}
	for _, key := range draft.CitedFactKeys {
		if _, dup := seenCited[key]; dup {
			diag.CitedFactKeysDuplicate = true
		}
		seenCited[key] = struct{}{}
		if _, ok := allowedKeys[key]; !ok {
			diag.CitedFactKeysValid = false
			diag.InvalidCitedKeyCount++
			diag.record(FactRuleCitedUnknownFact, key, key, key, key)
		}
	}

	for _, text := range []string{draft.Body, draft.Answer} {
		for _, token := range extractYuanAmounts(text) {
			if !allowedAmounts[token] {
				diag.AmountFactsValid = false
				diag.InventedFactCount++
				diag.record(FactRuleInventedAmount, token, token, token, token)
			}
		}
	}

	for _, fact := range draft.KeyFacts {
		sourceAllowed := false
		if _, ok := allowedKeys[fact.Source]; ok {
			sourceAllowed = true
		} else {
			diag.KeyFactSourcesValid = false
			diag.InvalidKeyFactCount++
			diag.record(FactRuleInvalidKeyFactSource, fact.Source, fact.Source, fact.Source, fact.Source)
			continue
		}
		if _, ok := allowedKeyFactKeys[fact.Source]; !ok {
			diag.KeyFactSourcesValid = false
			diag.InvalidKeyFactCount++
			diag.record(FactRuleKeyFactSourceNotAllowed, fact.Source, fact.Source, fact.Source, fact.Source)
			continue
		}

		switch fact.Value.Type {
		case "money":
			expected, ok := amountKeys[fact.Source]
			if !ok {
				diag.KeyFactSourcesValid = false
				diag.InvalidKeyFactCount++
				diag.record(FactRuleInvalidKeyFactMoneySource, fact.Source, fact.Source, fact.Source, fact.Source)
				continue
			}
			if fact.Value.Amount == nil || fact.Value.CurrencyCode == nil {
				diag.KeyFactValuesValid = false
				diag.InvalidKeyFactCount++
				diag.record(FactRuleKeyFactValueMismatch, fact.Source, fact.Source, fact.Source, fact.Source)
				continue
			}
			if normalizeAmount(*fact.Value.Amount) != normalizeAmount(parseAmount(expected.Amount)) ||
				*fact.Value.CurrencyCode != expected.CurrencyCode {
				diag.KeyFactValuesValid = false
				diag.InvalidKeyFactCount++
				diag.record(FactRuleKeyFactValueMismatch, fact.Source, fact.Source, fact.Source, fact.Source)
			}
		case "text":
			expected, ok := factKeys[fact.Source]
			if !ok || expected == "" {
				diag.KeyFactSourcesValid = false
				diag.InvalidKeyFactCount++
				diag.record(FactRuleInvalidKeyFactTextSource, fact.Source, fact.Source, fact.Source, fact.Source)
				continue
			}
			if fact.Value.TextValue == nil || strings.TrimSpace(*fact.Value.TextValue) != expected {
				diag.KeyFactValuesValid = false
				diag.InvalidKeyFactCount++
				diag.record(FactRuleKeyFactValueMismatch, fact.Source, fact.Source, fact.Source, fact.Source)
			}
		case "percent":
			expected, ok := factKeys[fact.Source]
			if !ok || expected == "" {
				diag.KeyFactSourcesValid = false
				diag.PercentFactsValid = false
				diag.InvalidKeyFactCount++
				diag.record(FactRuleInvalidKeyFactPercentSource, fact.Source, fact.Source, fact.Source, fact.Source)
				continue
			}
			if fact.Value.PercentValue == nil ||
				normalizeAmount(*fact.Value.PercentValue) != normalizeAmount(parseAmount(expected)) {
				diag.KeyFactValuesValid = false
				diag.PercentFactsValid = false
				diag.InvalidKeyFactCount++
				diag.record(FactRuleKeyFactValueMismatch, fact.Source, fact.Source, fact.Source, fact.Source)
			}
		case "date":
			// Current smoke validator does not evaluate date keyFacts.
			diag.DateFactsValid = true
		default:
			if sourceAllowed {
				diag.KeyFactValuesValid = false
				diag.InvalidKeyFactCount++
				diag.record(FactRuleKeyFactValueMismatch, fact.Source, fact.Source, fact.Source, fact.Source)
			}
		}
	}

	for _, ref := range draft.References {
		if _, ok := refKeys[ref.Key]; !ok {
			diag.ReferencesValid = false
			diag.InvalidReferenceCount++
			diag.record(FactRuleInvalidReference, ref.Key, ref.Key, ref.Key, ref.Key)
		}
	}

	for _, warning := range draft.Warnings {
		_, refOK := refKeys[warning.Source]
		_, keyOK := allowedKeys[warning.Source]
		if !refOK && !keyOK {
			diag.WarningSourcesValid = false
			diag.InvalidWarningSourceCount++
			diag.record(FactRuleInvalidWarningSource, warning.Source, warning.Source, warning.Source, warning.Source)
		}
	}

	for _, action := range draft.Actions {
		if _, ok := validDestinations[action.Destination]; !ok {
			diag.ActionsValid = false
			diag.InvalidActionCount++
			diag.record(FactRuleInvalidActionDestination, action.Destination, action.Destination, action.Destination, action.Destination)
		}
	}

	diag.syncPassed()
	return diag
}

func (d *FactDiagnostics) record(rule, factKey, source, expected, actual string) {
	for _, existing := range d.FailureRules {
		if existing == rule && d.InvalidFactRule != "" {
			// keep collecting distinct rules
		}
	}
	d.FailureRules = appendUniqueRule(d.FailureRules, rule)
	d.Errors = appendUniqueError(d.Errors, fmt.Sprintf("%s:%s", rule, factKey))
	if d.InvalidFactRule == "" {
		d.InvalidFactRule = rule
		d.InvalidFactKey = factKey
		d.InvalidFactSource = source
		d.ExpectedFactKey = expected
		d.ActualFactKey = actual
	}
}

func (d *FactDiagnostics) syncPassed() {
	d.Passed = d.AmountFactsValid &&
		d.CitedFactKeysValid &&
		d.KeyFactSourcesValid &&
		d.KeyFactValuesValid &&
		d.ReferencesValid &&
		d.ActionsValid &&
		d.WarningSourcesValid &&
		d.PercentFactsValid &&
		d.DateFactsValid &&
		d.InventedFactCount == 0 &&
		d.InvalidReferenceCount == 0 &&
		d.InvalidActionCount == 0 &&
		d.InvalidCitedKeyCount == 0 &&
		d.InvalidKeyFactCount == 0 &&
		d.InvalidWarningSourceCount == 0 &&
		len(d.Errors) == 0
	sort.Strings(d.FailureRules)
}

func appendUniqueRule(rules []string, rule string) []string {
	for _, existing := range rules {
		if existing == rule {
			return rules
		}
	}
	return append(rules, rule)
}

func appendUniqueError(errors []string, msg string) []string {
	for _, existing := range errors {
		if existing == msg {
			return errors
		}
	}
	return append(errors, msg)
}

func buildAllowedKeyFactKeySet(keySets factpack.KeySets) map[string]struct{} {
	keys := keySets.AllowedKeyFactKeys
	if len(keys) == 0 {
		keys = keySets.AllowedFactKeys
	}
	out := make(map[string]struct{}, len(keys))
	for _, key := range keys {
		out[key] = struct{}{}
	}
	return out
}

// ValidateFacts mirrors iOS AssistantAnswerValidator rules for monthly summary smoke tests.
func ValidateFacts(draft contract.AssistantAnswerDraftDTO, facts *contract.MonthlySummaryFactsDTO) FactValidationResult {
	diag := DiagnoseFacts(draft, facts)
	return FactValidationResult{
		InventedFactCount:     diag.InventedFactCount,
		InvalidReferenceCount: diag.InvalidReferenceCount,
		InvalidActionCount:    diag.InvalidActionCount,
		InvalidCitedKeyCount:  diag.InvalidCitedKeyCount,
		InvalidKeyFactCount:   diag.InvalidKeyFactCount,
		Errors:                append([]string(nil), diag.Errors...),
	}
}
