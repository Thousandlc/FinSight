package provider

import (
	"fmt"
	"sort"
	"strings"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/factpack"
)

// ValidateExplanationAlignment checks model explanations against deterministic risk assessment.
func ValidateExplanationAlignment(
	model contract.ModelAssistantAnswerDraftDTO,
	assessment *contract.FinancialRiskAssessmentDTO,
	keys factpack.KeySets,
) error {
	_ = keys
	if assessment == nil {
		return explanationValidationError("missing financialRiskAssessment")
	}

	expectedRiskReasons := expectedSignalReasonCodes(assessment)
	if err := validateRiskExplanationCoverage(model.RiskExplanations, expectedRiskReasons); err != nil {
		return err
	}

	expectedUnknowns := append([]string(nil), assessment.DataCompleteness.RequiredUnknownReasonCodes...)
	sort.Strings(expectedUnknowns)
	if err := validateUnknownExplanationCoverage(model.UnknownExplanations, expectedUnknowns); err != nil {
		return err
	}
	return nil
}

func expectedSignalReasonCodes(assessment *contract.FinancialRiskAssessmentDTO) []string {
	var reasons []string
	for _, signal := range assessment.Signals {
		if signal.Level == "safe" {
			continue
		}
		reasons = append(reasons, signal.ReasonCode)
	}
	sort.Strings(reasons)
	return reasons
}

func validateRiskExplanationCoverage(explanations []contract.ModelRiskExplanationDTO, expected []string) error {
	actual := make([]string, 0, len(explanations))
	seen := make(map[string]struct{}, len(explanations))
	for _, item := range explanations {
		code := strings.TrimSpace(item.ReasonCode)
		if code == "" {
			return explanationValidationError("empty riskExplanation reasonCode")
		}
		if _, ok := seen[code]; ok {
			return explanationValidationError("duplicate riskExplanation reasonCode")
		}
		seen[code] = struct{}{}
		actual = append(actual, code)
	}
	sort.Strings(actual)
	if len(actual) != len(expected) {
		return explanationValidationError("riskExplanationCoverageMismatch")
	}
	for i := range expected {
		if actual[i] != expected[i] {
			return explanationValidationError("riskExplanationCoverageMismatch")
		}
	}
	return nil
}

func validateUnknownExplanationCoverage(
	explanations []contract.ModelUnknownExplanationDTO,
	expected []string,
) error {
	actual := make([]string, 0, len(explanations))
	seen := make(map[string]struct{}, len(explanations))
	for _, item := range explanations {
		code := strings.TrimSpace(item.ReasonCode)
		if code == "" {
			return explanationValidationError("empty unknownExplanation reasonCode")
		}
		if _, ok := seen[code]; ok {
			return explanationValidationError("duplicate unknownExplanation reasonCode")
		}
		seen[code] = struct{}{}
		actual = append(actual, code)
	}
	sort.Strings(actual)
	if len(actual) != len(expected) {
		return explanationValidationError("unknownExplanationCoverageMismatch")
	}
	for i := range expected {
		if actual[i] != expected[i] {
			return explanationValidationError("unknownExplanationCoverageMismatch")
		}
	}
	return nil
}

func primarySourceFactKey(signal contract.FinancialRiskSignalDTO) string {
	if len(signal.SourceFactKeys) > 0 {
		return signal.SourceFactKeys[0]
	}
	return signal.ReasonCode
}

type explanationValidationError string

func (e explanationValidationError) Error() string {
	return fmt.Sprintf("explanation alignment: %s", string(e))
}

// ParseAlignmentFailureCode extracts the machine-readable alignment failure token.
func ParseAlignmentFailureCode(err error) string {
	if err == nil {
		return ""
	}
	const prefix = "explanation alignment: "
	msg := err.Error()
	if strings.HasPrefix(msg, prefix) {
		return strings.TrimSpace(strings.TrimPrefix(msg, prefix))
	}
	return "unknown"
}
