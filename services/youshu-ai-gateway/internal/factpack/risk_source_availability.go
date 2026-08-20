package factpack

import (
	"fmt"
	"strings"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
)

const RiskSourceFactUnavailableCode = "riskSourceFactUnavailable"

// RiskSourceFactAvailabilityError reports assessment provenance missing from FactPack.
type RiskSourceFactAvailabilityError struct {
	MissingKey string
	ReasonCode string
}

func (e RiskSourceFactAvailabilityError) Error() string {
	if e.MissingKey != "" && e.ReasonCode != "" {
		return fmt.Sprintf("unregistered sourceFactKey: %s for signal %s", e.MissingKey, e.ReasonCode)
	}
	if e.MissingKey != "" {
		return fmt.Sprintf("unregistered sourceFactKey: %s", e.MissingKey)
	}
	return "risk source fact unavailable"
}

// ValidateRiskSourceFactAvailability enforces Assessment Provenance ⊆ Request FactPack.
// Every non-safe signal sourceFactKey must be registered in the current MonthlySummaryFacts FactPack.
func ValidateRiskSourceFactAvailability(
	assessment *contract.FinancialRiskAssessmentDTO,
	facts *contract.MonthlySummaryFactsDTO,
) error {
	if assessment == nil {
		return fmt.Errorf("missing financialRiskAssessment")
	}
	if facts == nil {
		return fmt.Errorf("missing monthlySummaryFacts")
	}
	allowed := allowedFactKeySet(BuildKeySets(facts).AllowedFactKeys)
	return validateSignalSourceFactAvailability(assessment.Signals, allowed)
}

// ValidateSignalSourceFactKeys checks signal provenance against an explicit allowed key list.
func ValidateSignalSourceFactKeys(
	signals []contract.FinancialRiskSignalDTO,
	allowedFactKeys []string,
) error {
	return validateSignalSourceFactAvailability(signals, allowedFactKeySetFromSlice(allowedFactKeys))
}

func allowedFactKeySetFromSlice(keys []string) map[string]struct{} {
	return allowedFactKeySet(keys)
}

func validateSignalSourceFactAvailability(
	signals []contract.FinancialRiskSignalDTO,
	allowed map[string]struct{},
) error {
	for _, signal := range signals {
		if signal.Level == "safe" {
			continue
		}
		for _, key := range signal.SourceFactKeys {
			trimmed := strings.TrimSpace(key)
			if trimmed == "" {
				return RiskSourceFactAvailabilityError{ReasonCode: signal.ReasonCode}
			}
			if _, ok := allowed[trimmed]; !ok {
				return RiskSourceFactAvailabilityError{
					MissingKey: trimmed,
					ReasonCode: signal.ReasonCode,
				}
			}
		}
	}
	return nil
}

func allowedFactKeySet(keys []string) map[string]struct{} {
	out := make(map[string]struct{}, len(keys))
	for _, key := range keys {
		out[key] = struct{}{}
	}
	return out
}

// ParseRiskSourceFactAvailabilityFailureCode extracts a stable machine-readable token.
func ParseRiskSourceFactAvailabilityFailureCode(err error) string {
	if err == nil {
		return ""
	}
	var availErr RiskSourceFactAvailabilityError
	if ok := asRiskSourceFactAvailabilityError(err, &availErr); ok {
		return RiskSourceFactUnavailableCode
	}
	msg := err.Error()
	if strings.Contains(msg, "unregistered sourceFactKey") {
		return RiskSourceFactUnavailableCode
	}
	return ""
}

func asRiskSourceFactAvailabilityError(err error, target *RiskSourceFactAvailabilityError) bool {
	if err == nil {
		return false
	}
	if e, ok := err.(RiskSourceFactAvailabilityError); ok {
		*target = e
		return true
	}
	return false
}
