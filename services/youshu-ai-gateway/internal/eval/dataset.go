package eval

import (
	"fmt"
	"strings"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/factpack"
)

// Category constants for evaluation scenarios.
const (
	CategoryHealthyFinance   = "healthy_finance"
	CategoryCashFlowRisk     = "cash_flow_risk"
	CategoryDebt             = "debt"
	CategoryIncomeExpense    = "income_expense_anomaly"
	CategoryInsufficientData = "insufficient_data"
	CategoryEdgeCase         = "edge_case"
)

// RiskLevel describes expected warning severity behavior.
type RiskLevel string

const (
	RiskLevelNone    RiskLevel = "none"
	RiskLevelSafe    RiskLevel = "safe"
	RiskLevelWarning RiskLevel = "warning"
	RiskLevelRisk    RiskLevel = "risk"
)

// EvaluationCase defines one synthetic monthly-summary evaluation scenario.
type EvaluationCase struct {
	ID          string
	Category    string
	Description string

	Envelope contract.RequestEnvelope
	Repeats  int

	ExpectedFacts       []string
	DiagnosticKeywords  []string
	ForbiddenClaims     []string
	ExpectedRiskLevel   RiskLevel
	AllowedActions      []string
	UnknownExpectation  UnknownExpectation
	RequiredUnknowns    bool // deprecated: use UnknownExpectation
	ForbiddenReferences []string
	RequiredFactKeys    []string
	ForbiddenFactKeys   []string // legacy deprecated: use ForbiddenKeyFactSources / ForbiddenCitationFactKeys
	ForbiddenKeyFactSources   []string
	ForbiddenCitationFactKeys []string
	StructuredConclusion StructuredConclusionExpectation
	ManualReviewRequired bool

	// FactOverlay holds evaluation-only availability for facts that production DTO cannot omit.
	FactOverlay EvalFactOverlay

	// Assessment is the deterministic iOS policy output fixture for this case (v2 evaluation input).
	Assessment contract.FinancialRiskAssessmentDTO
}

// AllCases returns the full evaluation dataset with assessment fixtures attached.
func AllCases() []EvaluationCase {
	raw := allEvaluationCases()
	cases, err := attachAssessmentFixtures(raw)
	if err != nil {
		panic("eval dataset: " + err.Error())
	}
	return cases
}

// ValidateDataset checks structural integrity of all cases.
func ValidateDataset(cases []EvaluationCase) error {
	seen := map[string]struct{}{}
	for _, c := range cases {
		if strings.TrimSpace(c.ID) == "" {
			return fmt.Errorf("case missing id")
		}
		if _, ok := seen[c.ID]; ok {
			return fmt.Errorf("duplicate case id: %s", c.ID)
		}
		seen[c.ID] = struct{}{}
		if strings.TrimSpace(c.Category) == "" {
			return fmt.Errorf("case %s missing category", c.ID)
		}
		if c.Envelope.MonthlySummaryFacts == nil {
			return fmt.Errorf("case %s missing monthlySummaryFacts", c.ID)
		}
		if c.Envelope.Operation != contract.OperationMonthlySummary {
			return fmt.Errorf("case %s operation must be monthlySummary", c.ID)
		}
		if c.Repeats < 1 {
			return fmt.Errorf("case %s repeats must be >= 1", c.ID)
		}
		if err := validateRiskLevel(c.ExpectedRiskLevel); err != nil {
			return fmt.Errorf("case %s: %w", c.ID, err)
		}
		if err := validateUnknownExpectation(c); err != nil {
			return fmt.Errorf("case %s: %w", c.ID, err)
		}
		if err := ValidateMoneyOverlay(c); err != nil {
			return err
		}
		if strings.TrimSpace(c.Assessment.OverallLevel) == "" {
			return fmt.Errorf("case %s missing assessment fixture", c.ID)
		}
		if c.Envelope.FinancialRiskAssessment == nil {
			return fmt.Errorf("case %s envelope missing financialRiskAssessment", c.ID)
		}
		if err := validateCaseRiskSourceFactAvailability(c); err != nil {
			return err
		}
	}
	return validateDatasetExtensions(cases)
}

func validateDatasetExtensions(cases []EvaluationCase) error {
	if err := ValidateDebtDataSemantics(cases); err != nil {
		return err
	}
	if err := ValidateInsufficientDataSemantics(cases); err != nil {
		return err
	}
	return ValidateForbiddenScopeSemantics(cases)
}

func validateRiskLevel(level RiskLevel) error {
	switch level {
	case RiskLevelNone, RiskLevelSafe, RiskLevelWarning, RiskLevelRisk, "":
		return nil
	default:
		return fmt.Errorf("invalid expected risk level: %q", level)
	}
}

func validateUnknownExpectation(c EvaluationCase) error {
	exp := ResolveUnknownExpectation(c)
	switch exp {
	case UnknownNotRequired, UnknownRequired, UnknownForbidden, "":
		return nil
	default:
		return fmt.Errorf("invalid unknown expectation: %q", exp)
	}
}

// ValidateDebtDataSemantics ensures known-zero, missing, partial, and known-value debt cases are distinct.
func ValidateDebtDataSemantics(cases []EvaluationCase) error {
	for _, c := range cases {
		debt := AnalyzeDebtFacts(c)
		exp := ResolveUnknownExpectation(c)
		avail := ResolveDebtPaymentAvailability(c)

		if debt.DebtFactsKnownZero && exp == UnknownRequired {
			return fmt.Errorf("case %s: known zero debt must not require unknowns", c.ID)
		}
		if debt.DebtFactsMissing && exp == UnknownForbidden {
			return fmt.Errorf("case %s: genuinely missing debt must not forbid unknowns", c.ID)
		}
		if debt.DebtFactsPartial && debt.DebtFactsMissing {
			return fmt.Errorf("case %s: partial debt must not be classified as missing", c.ID)
		}
		if debt.DebtFactsKnownZero && debt.DebtFactsMissing {
			return fmt.Errorf("case %s: known zero must not be classified as missing", c.ID)
		}
		if c.ID == "E01_partial_debt_data" {
			if exp != UnknownNotRequired {
				return fmt.Errorf("case %s: partial debt must use unknownNotRequired", c.ID)
			}
			if avail != MoneyKnownValue || !debt.DebtFactsPartial {
				return fmt.Errorf("case %s: must be partial known-value debt, not missing", c.ID)
			}
		}
		if c.ID == "E05_missing_debt_data" {
			if exp != UnknownRequired {
				return fmt.Errorf("case %s: missing debt must use unknownRequired", c.ID)
			}
			if avail != MoneyMissing || !debt.DebtFactsMissing {
				return fmt.Errorf("case %s: must use eval overlay MoneyMissing for genuinely absent debt", c.ID)
			}
		}
		if c.ID == "C01_no_debt" {
			if avail != MoneyKnownZero || !debt.DebtFactsKnownZero {
				return fmt.Errorf("case %s: no debt case must use known zero payment", c.ID)
			}
		}
	}
	return nil
}

// CategoryCounts returns case counts grouped by category.
func CategoryCounts(cases []EvaluationCase) map[string]int {
	counts := map[string]int{}
	for _, c := range cases {
		counts[c.Category]++
	}
	return counts
}

// DatasetSummary describes dataset and pilot sizing for reports.
type DatasetSummary struct {
	DatasetCases int `json:"datasetCases"`
	PilotCases   int `json:"pilotCases"`
	FullRuns     int `json:"fullRuns"`
	PilotRuns    int `json:"pilotRuns"`
}

// BuildDatasetSummary computes dataset and pilot counts from case selection and repeat policy.
func BuildDatasetSummary() (DatasetSummary, error) {
	all := AllCases()
	pilot, err := FilterCases(all, PilotFilterOptions())
	if err != nil {
		return DatasetSummary{}, err
	}
	pilotRuns, err := ExpectedPilotRuns()
	if err != nil {
		return DatasetSummary{}, err
	}
	return DatasetSummary{
		DatasetCases: len(all),
		PilotCases:   len(pilot),
		FullRuns:     CountRuns(all),
		PilotRuns:    pilotRuns,
	}, nil
}

func validateCaseRiskSourceFactAvailability(c EvaluationCase) error {
	if _, err := ProductionLikeMonthlySummaryFacts(c); err != nil {
		return fmt.Errorf("case %s risk source fact availability: %w", c.ID, err)
	}
	if err := factpack.ValidateRiskSourceFactAvailability(&c.Assessment, c.Envelope.MonthlySummaryFacts); err != nil {
		return fmt.Errorf("case %s risk source fact availability: %w", c.ID, err)
	}
	return nil
}
