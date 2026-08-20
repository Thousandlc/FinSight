package eval

import (
	"fmt"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
)

// InsufficientDataClassification describes evaluation-only data availability semantics.
type InsufficientDataClassification string

const (
	DataGenuinelyMissing InsufficientDataClassification = "genuinelyMissing"
	DataPartial          InsufficientDataClassification = "partial"
	DataOptionalAbsent   InsufficientDataClassification = "optionalAbsent"
	DataNotApplicable    InsufficientDataClassification = "notApplicable"
	DataComplete         InsufficientDataClassification = "complete"
)

// InsufficientDataAnalysis describes unknown-expectation semantics for insufficient-data cases.
type InsufficientDataAnalysis struct {
	Classification          InsufficientDataClassification `json:"classification"`
	BudgetInFactContract    bool                           `json:"budgetInFactContract"`
	SafeBalancePresent      bool                           `json:"safeBalancePresent"`
	MinimumBalancePresent   bool                           `json:"minimumBalancePresent"`
	CoreMonthlyFactsPresent bool                           `json:"coreMonthlyFactsPresent"`
	RecommendedExpectation  UnknownExpectation             `json:"recommendedExpectation"`
	Summary                 string                         `json:"summary"`
}

// AnalyzeInsufficientDataCase derives correct unknown expectation from case facts.
func AnalyzeInsufficientDataCase(c EvaluationCase) InsufficientDataAnalysis {
	switch c.ID {
	case "E03_no_budget":
		return analyzeE03Budget(c)
	case "E04_partial_facts_missing":
		return analyzeE04PartialFacts(c)
	case "E05_missing_debt_data":
		return InsufficientDataAnalysis{
			Classification:          DataGenuinelyMissing,
			CoreMonthlyFactsPresent: c.Envelope.MonthlySummaryFacts != nil,
			RecommendedExpectation:  UnknownRequired,
			Summary:                 "debt payment genuinely missing via eval overlay",
		}
	case "E01_partial_debt_data":
		return InsufficientDataAnalysis{
			Classification:          DataPartial,
			CoreMonthlyFactsPresent: true,
			RecommendedExpectation:  UnknownNotRequired,
			Summary:                 "partial debt amount known; DTI/source incomplete",
		}
	case "E02_no_cashflow_projection":
		return InsufficientDataAnalysis{
			Classification:          DataOptionalAbsent,
			CoreMonthlyFactsPresent: true,
			RecommendedExpectation:  UnknownRequired,
			Summary:                 "cash-flow projection fields absent; case expects explicit unknowns",
		}
	default:
		exp := ResolveUnknownExpectation(c)
		return InsufficientDataAnalysis{
			Classification:         DataComplete,
			RecommendedExpectation: exp,
			Summary:                "default case semantics",
		}
	}
}

func analyzeE03Budget(c EvaluationCase) InsufficientDataAnalysis {
	facts := c.Envelope.MonthlySummaryFacts
	analysis := InsufficientDataAnalysis{
		Classification:          DataNotApplicable,
		BudgetInFactContract:    false,
		CoreMonthlyFactsPresent: facts != nil,
		RecommendedExpectation:  UnknownNotRequired,
		Summary:                 "budget is not part of MonthlySummaryFacts; not applicable to this operation",
	}
	if facts != nil {
		analysis.CoreMonthlyFactsPresent = hasCoreMonthlyFacts(facts)
	}
	return analysis
}

func analyzeE04PartialFacts(c EvaluationCase) InsufficientDataAnalysis {
	facts := c.Envelope.MonthlySummaryFacts
	analysis := InsufficientDataAnalysis{
		Classification:          DataOptionalAbsent,
		RecommendedExpectation:  UnknownNotRequired,
		Summary:                 "safeBalance/minimumBalance optional fields absent; core monthly facts complete",
	}
	if facts != nil {
		analysis.SafeBalancePresent = facts.SafeBalance != nil
		analysis.MinimumBalancePresent = facts.MinimumBalance != nil
		analysis.CoreMonthlyFactsPresent = hasCoreMonthlyFacts(facts)
	}
	return analysis
}

func hasCoreMonthlyFacts(facts *contract.MonthlySummaryFactsDTO) bool {
	if facts == nil {
		return false
	}
	return facts.AvailableCash.Amount != "" &&
		facts.MonthlyIncome.Amount != "" &&
		facts.MonthlyExpense.Amount != "" &&
		facts.EstimatedMonthEndBalance.Amount != ""
}

// ValidateInsufficientDataSemantics ensures unknown expectations match fact semantics.
func ValidateInsufficientDataSemantics(cases []EvaluationCase) error {
	for _, c := range cases {
		if c.Category != CategoryInsufficientData {
			continue
		}
		analysis := AnalyzeInsufficientDataCase(c)
		exp := ResolveUnknownExpectation(c)
		if c.ID == "E03_no_budget" && exp != UnknownNotRequired {
			return fmt.Errorf("case %s: budget is not applicable; must use unknownNotRequired", c.ID)
		}
		if c.ID == "E04_partial_facts_missing" && exp != UnknownNotRequired {
			return fmt.Errorf("case %s: optional fields absent; must use unknownNotRequired", c.ID)
		}
		if c.ID == "E05_missing_debt_data" && exp != UnknownRequired {
			return fmt.Errorf("case %s: genuinely missing debt must use unknownRequired", c.ID)
		}
		if exp != analysis.RecommendedExpectation && c.ID != "E02_no_cashflow_projection" {
			// E02 keeps UnknownRequired by explicit scenario design.
			if c.ID == "E03_no_budget" || c.ID == "E04_partial_facts_missing" || c.ID == "E01_partial_debt_data" || c.ID == "E05_missing_debt_data" {
				return fmt.Errorf("case %s: expectation %q does not match recommended %q (%s)",
					c.ID, exp, analysis.RecommendedExpectation, analysis.Summary)
			}
		}
	}
	return nil
}
