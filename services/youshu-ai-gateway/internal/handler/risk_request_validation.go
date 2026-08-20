package handler

import (
	"fmt"
	"strings"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/factpack"
)

func ValidateRequestEnvelope(req contract.RequestEnvelope) error {
	switch req.Operation {
	case contract.OperationMonthlySummary:
		if req.MonthlySummaryFacts == nil {
			return errValidation("missing monthlySummaryFacts")
		}
		if req.FinancialRiskAssessment == nil {
			return errValidation("missing financialRiskAssessment")
		}
		keySets := factpack.BuildKeySets(req.MonthlySummaryFacts)
		return ValidateFinancialRiskAssessment(*req.FinancialRiskAssessment, keySets.AllowedFactKeys)
	default:
		if req.FinancialRiskAssessment != nil {
			return errValidation("financialRiskAssessment not allowed for operation")
		}
	}
	return nil
}

func ValidateFinancialRiskAssessment(
	assessment contract.FinancialRiskAssessmentDTO,
	allowedFactKeys []string,
) error {
	if !containsString(contract.AllowedRiskOverallLevels, assessment.OverallLevel) {
		return errValidation("invalid overallLevel")
	}
	if strings.TrimSpace(assessment.PolicyVersion) == "" {
		return errValidation("missing policyVersion")
	}
	if !containsString(contract.AllowedDebtDataStates, assessment.DebtDataState) {
		return errValidation("invalid debtDataState")
	}

	seenSignals := make(map[string]struct{})
	highestSignalLevel := "safe"
	for _, signal := range assessment.Signals {
		key := signal.Kind + "|" + signal.ReasonCode
		if _, exists := seenSignals[key]; exists {
			return errValidation("duplicate signal")
		}
		seenSignals[key] = struct{}{}

		if !containsString(contract.AllowedRiskSignalKinds, signal.Kind) {
			return errValidation("invalid signal kind")
		}
		if !containsString(contract.AllowedRiskSignalLevels, signal.Level) {
			return errValidation("invalid signal level")
		}
		if !containsString(contract.AllowedRiskSignalReasonCodes, signal.ReasonCode) {
			return errValidation("invalid signal reasonCode")
		}
		if !containsString(allowedEmittedReasonCodesForPolicy(assessment.PolicyVersion), signal.ReasonCode) {
			return errValidation("reasonCodeNotAllowedForPolicyVersion")
		}
		if len(signal.SourceFactKeys) == 0 {
			return errValidation("empty sourceFactKeys")
		}
		if hasDuplicateStrings(signal.SourceFactKeys) {
			return errValidation("duplicate sourceFactKeys")
		}
		for _, dest := range signal.RecommendedActionDestinations {
			if !containsString(contract.AllowedRiskActionDestinations, dest) {
				return errValidation("invalid action destination")
			}
		}
		highestSignalLevel = maxRiskLevel(highestSignalLevel, signal.Level)
	}

	if err := factpack.ValidateSignalSourceFactKeys(assessment.Signals, allowedFactKeys); err != nil {
		return errValidation("unregistered sourceFactKey")
	}

	if err := validateOverallLevelInvariant(assessment.OverallLevel, highestSignalLevel); err != nil {
		return err
	}
	if err := validateDebtSemanticInvariant(assessment); err != nil {
		return err
	}
	if err := validateCompletenessInvariant(assessment); err != nil {
		return err
	}
	if err := validateRequiredUnknownInvariant(assessment); err != nil {
		return err
	}
	return nil
}

func validateOverallLevelInvariant(overallLevel, highestSignalLevel string) error {
	expected := "safe"
	if highestSignalLevel == "risk" {
		expected = "risk"
	} else if highestSignalLevel == "warning" {
		expected = "warning"
	}
	if overallLevel != expected {
		return errValidation("overallLevel mismatch")
	}
	return nil
}

func validateDebtSemanticInvariant(assessment contract.FinancialRiskAssessmentDTO) error {
	if assessment.DebtDataState != "knownNoDebt" {
		return nil
	}
	for _, signal := range assessment.Signals {
		if containsString(contract.KnownNoDebtIncompatibleSignalReasonCodes, signal.ReasonCode) {
			return errValidation("knownNoDebt incompatible signal")
		}
	}
	return nil
}

func validateCompletenessInvariant(assessment contract.FinancialRiskAssessmentDTO) error {
	c := assessment.DataCompleteness
	for _, value := range []string{c.Debt, c.CashFlowProjection, c.Income, c.Expense} {
		if !containsString(contract.AllowedFieldAvailability, value) {
			return errValidation("invalid completeness field")
		}
	}
	expectedDebt, ok := contract.DebtDataStateToCompletenessDebt[assessment.DebtDataState]
	if !ok {
		return errValidation("invalid debtDataState completeness mapping")
	}
	if c.Debt != expectedDebt {
		return errValidation("debt completeness mismatch")
	}
	for _, code := range c.RequiredUnknownReasonCodes {
		if !containsString(contract.AllowedRiskReasonCodes, code) {
			return errValidation("invalid requiredUnknownReasonCode")
		}
	}
	if hasDuplicateStrings(c.RequiredUnknownReasonCodes) {
		return errValidation("duplicate requiredUnknownReasonCode")
	}
	return nil
}

func validateRequiredUnknownInvariant(assessment contract.FinancialRiskAssessmentDTO) error {
	codes := assessment.DataCompleteness.RequiredUnknownReasonCodes
	if assessment.DebtDataState == "missing" && !containsString(codes, "debtDataMissing") {
		return errValidation("missing debtDataMissing unknown")
	}
	if assessment.DataCompleteness.CashFlowProjection == "missing" &&
		!containsString(codes, "cashFlowProjectionMissing") {
		return errValidation("missing cashFlowProjectionMissing unknown")
	}
	return nil
}

func maxRiskLevel(current, candidate string) string {
	order := map[string]int{"safe": 0, "warning": 1, "risk": 2}
	if order[candidate] > order[current] {
		return candidate
	}
	return current
}

func allowedEmittedReasonCodesForPolicy(policyVersion string) []string {
	if codes, ok := contract.AllowedRiskSignalReasonCodesByPolicyVersion[policyVersion]; ok {
		return codes
	}
	return nil
}

func hasDuplicateStrings(values []string) bool {
	seen := make(map[string]struct{}, len(values))
	for _, value := range values {
		if _, exists := seen[value]; exists {
			return true
		}
		seen[value] = struct{}{}
	}
	return false
}

func riskValidationFailureCode(err error) string {
	if err == nil {
		return ""
	}
	msg := err.Error()
	switch {
	case strings.Contains(msg, "missing financialRiskAssessment"):
		return "missingFinancialRiskAssessment"
	case strings.Contains(msg, "financialRiskAssessment not allowed"):
		return "unexpectedFinancialRiskAssessment"
	case strings.Contains(msg, "overallLevel mismatch"):
		return "overallLevelMismatch"
	case strings.Contains(msg, "knownNoDebt incompatible"):
		return "knownNoDebtIncompatibleSignal"
	case strings.Contains(msg, "debt completeness mismatch"):
		return "debtCompletenessMismatch"
	case strings.Contains(msg, "missing debtDataMissing"):
		return "missingDebtDataMissingUnknown"
	case strings.Contains(msg, "missing cashFlowProjectionMissing"):
		return "missingCashFlowProjectionMissingUnknown"
	case strings.Contains(msg, "unregistered sourceFactKey"):
		return "unregisteredSourceFactKey"
	case strings.Contains(msg, "duplicate signal"):
		return "duplicateSignal"
	case strings.Contains(msg, "reasonCodeNotAllowedForPolicyVersion"):
		return "reasonCodeNotAllowedForPolicyVersion"
	default:
		return "invalidFinancialRiskAssessment"
	}
}

func formatRiskValidationError(err error) string {
	code := riskValidationFailureCode(err)
	if code == "" {
		return "financial risk request contract invalid"
	}
	return fmt.Sprintf("financial risk request contract invalid: %s", code)
}
