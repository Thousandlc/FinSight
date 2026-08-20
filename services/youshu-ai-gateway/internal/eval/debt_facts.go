package eval

// DebtFactsAnalysis describes debt data semantics in evaluation cases.
type DebtFactsAnalysis struct {
	DebtFactsPresent           bool   `json:"debtFactsPresent"`
	DebtFactsKnownZero         bool   `json:"debtFactsKnownZero"`
	DebtFactsMissing           bool   `json:"debtFactsMissing"`
	DebtFactsPartial           bool   `json:"debtFactsPartial"`
	DebtPaymentToIncomePresent bool   `json:"debtPaymentToIncomePresent"`
	DebtSourceLabelPresent     bool   `json:"debtSourceLabelPresent"`
	ExpectedUnknownBehavior    string `json:"expectedUnknownBehavior"`
	Summary                    string `json:"summary"`
}

// AnalyzeDebtFacts inspects an evaluation case to determine debt data semantics.
// Evaluation-only: availability overlay is authoritative; empty string is not a missing sentinel.
func AnalyzeDebtFacts(c EvaluationCase) DebtFactsAnalysis {
	facts := c.Envelope.MonthlySummaryFacts
	if facts == nil {
		return DebtFactsAnalysis{
			DebtFactsMissing:        true,
			ExpectedUnknownBehavior: "unknownRequired when facts nil",
			Summary:                 "no facts provided",
		}
	}

	analysis := DebtFactsAnalysis{
		DebtPaymentToIncomePresent: facts.DebtPaymentToIncomePercent != nil,
	}
	for _, label := range facts.SourceLabels {
		if label == "Debt" {
			analysis.DebtSourceLabelPresent = true
			break
		}
	}

	switch ResolveDebtPaymentAvailability(c) {
	case MoneyMissing:
		analysis.DebtFactsMissing = true
		analysis.ExpectedUnknownBehavior = "unknownRequired: debt payment unavailable and no Debt source"
		analysis.Summary = "genuinely missing debt data"
	case MoneyKnownZero:
		analysis.DebtFactsKnownZero = true
		analysis.DebtFactsPresent = true
		analysis.ExpectedUnknownBehavior = "unknownForbidden/notRequired: known zero debt"
		analysis.Summary = "known zero debt payment"
	case MoneyKnownValue:
		analysis.DebtFactsPresent = true
		analysis.DebtFactsPartial = !analysis.DebtSourceLabelPresent
		if analysis.DebtFactsPartial {
			analysis.ExpectedUnknownBehavior = "unknownNotRequired: partial debt without complete debt profile"
			analysis.Summary = "partial debt data: payment known, debt inventory/profile incomplete"
		} else {
			analysis.ExpectedUnknownBehavior = "unknownNotRequired: complete debt facts"
			analysis.Summary = "complete debt facts present"
		}
	}
	return analysis
}

func isKnownZeroAmount(amount string) bool {
	switch amount {
	case "0", "0.0", "0.00":
		return true
	default:
		return false
	}
}

// UnknownCheckerRule describes the unknown evaluation rule for a case.
func UnknownCheckerRule(c EvaluationCase) string {
	switch ResolveUnknownExpectation(c) {
	case UnknownRequired:
		return "unknownRequired → len(unknowns)>0"
	case UnknownForbidden:
		return "unknownForbidden → len(unknowns)==0"
	default:
		return "unknownNotRequired → no unknown check"
	}
}

// UnknownCheckerRisk reports false positive/negative risks.
func UnknownCheckerRisk(c EvaluationCase) (falsePositiveRisk, falseNegativeRisk string) {
	debt := AnalyzeDebtFacts(c)
	exp := ResolveUnknownExpectation(c)

	if debt.DebtFactsPartial && exp == UnknownRequired {
		return "high: partial debt should not require unknowns", "low"
	}
	if debt.DebtFactsMissing && exp == UnknownNotRequired {
		return "low", "high: missing debt should require unknowns"
	}
	if exp == UnknownRequired {
		return "low when data truly missing", "medium: model may use warnings instead of unknowns"
	}
	return "none", "none"
}
