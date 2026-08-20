package provider

import (
	"fmt"
	"strings"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/factpack"
)

// AssembleRiskExplanations maps model explanation text to gateway explanations with
// deterministic citations copied from assessment signal sourceFactKeys.
func AssembleRiskExplanations(
	modelExplanations []contract.ModelRiskExplanationDTO,
	assessment *contract.FinancialRiskAssessmentDTO,
) ([]contract.RiskExplanationDTO, error) {
	if assessment == nil {
		if len(modelExplanations) > 0 {
			return nil, explanationValidationError("missing financialRiskAssessment")
		}
		return []contract.RiskExplanationDTO{}, nil
	}
	signalByReason := make(map[string]contract.FinancialRiskSignalDTO, len(assessment.Signals))
	for _, signal := range assessment.Signals {
		if signal.Level == "safe" {
			continue
		}
		signalByReason[signal.ReasonCode] = signal
	}

	out := make([]contract.RiskExplanationDTO, 0, len(modelExplanations))
	for _, explanation := range modelExplanations {
		code := strings.TrimSpace(explanation.ReasonCode)
		signal, ok := signalByReason[code]
		if !ok {
			return nil, explanationValidationError("riskExplanationReasonNotInAssessment")
		}
		out = append(out, contract.RiskExplanationDTO{
			ReasonCode:    signal.ReasonCode,
			Text:          explanation.Text,
			CitedFactKeys: cloneSignalSourceFactKeys(signal),
		})
	}
	return out, nil
}

// ValidateAssembledRiskExplanationProvenance verifies post-assembly citations exactly
// match assessment signal provenance and remain registered facts.
func ValidateAssembledRiskExplanationProvenance(
	explanations []contract.RiskExplanationDTO,
	assessment *contract.FinancialRiskAssessmentDTO,
	keys factpack.KeySets,
) error {
	if assessment == nil {
		return explanationValidationError("missing financialRiskAssessment")
	}
	signalByReason := make(map[string]contract.FinancialRiskSignalDTO, len(assessment.Signals))
	for _, signal := range assessment.Signals {
		if signal.Level == "safe" {
			continue
		}
		signalByReason[signal.ReasonCode] = signal
	}
	allowedFacts := make(map[string]struct{}, len(keys.AllowedFactKeys))
	for _, key := range keys.AllowedFactKeys {
		allowedFacts[key] = struct{}{}
	}

	for _, explanation := range explanations {
		signal, ok := signalByReason[explanation.ReasonCode]
		if !ok {
			return explanationValidationError("riskExplanationReasonNotInAssessment")
		}
		expected := cloneSignalSourceFactKeys(signal)
		if !equalStringSlices(explanation.CitedFactKeys, expected) {
			return explanationValidationError("assembledRiskExplanationProvenanceMismatch")
		}
		for _, key := range explanation.CitedFactKeys {
			trimmed := strings.TrimSpace(key)
			if trimmed == "" {
				return explanationValidationError("empty riskExplanation citedFactKey")
			}
			if _, ok := allowedFacts[trimmed]; !ok {
				return explanationValidationError("unregistered riskExplanation citedFactKey")
			}
		}
	}
	return nil
}

func cloneSignalSourceFactKeys(signal contract.FinancialRiskSignalDTO) []string {
	if len(signal.SourceFactKeys) == 0 {
		return []string{}
	}
	out := make([]string, len(signal.SourceFactKeys))
	copy(out, signal.SourceFactKeys)
	return out
}

func equalStringSlices(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

// ParseProvenanceAssemblyFailureCode extracts the machine-readable provenance failure token.
func ParseProvenanceAssemblyFailureCode(err error) string {
	return ParseAlignmentFailureCode(err)
}

// ProvenanceAssemblyErrorKind classifies provenance assembly failures for diagnostics.
func ProvenanceAssemblyErrorKind(err error) string {
	if err == nil {
		return ""
	}
	code := ParseProvenanceAssemblyFailureCode(err)
	switch code {
	case "riskExplanationReasonNotInAssessment":
		return "assessment-signal-missing"
	case "assembledRiskExplanationProvenanceMismatch", "unregistered riskExplanation citedFactKey", "empty riskExplanation citedFactKey":
		return "post-assembly-citation-validation"
	default:
		return "provenance-assembly"
	}
}

// FormatProvenanceAssemblyError wraps assembly errors with a stable prefix.
func FormatProvenanceAssemblyError(err error) error {
	if err == nil {
		return nil
	}
	if _, ok := err.(explanationValidationError); ok {
		return fmt.Errorf("provenance assembly: %s", ParseAlignmentFailureCode(err))
	}
	return fmt.Errorf("provenance assembly: %v", err)
}
