package eval

import (
	"fmt"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
)

// AssessmentFixture returns the Swift-policy golden assessment for a case.
func AssessmentFixture(caseID string) (*contract.FinancialRiskAssessmentDTO, error) {
	assessment, err := GoldenBackedAssessment(caseID)
	if err != nil {
		return nil, err
	}
	copy := assessment
	return &copy, nil
}

func attachAssessmentFixtures(cases []EvaluationCase) ([]EvaluationCase, error) {
	out := make([]EvaluationCase, len(cases))
	for i, c := range cases {
		assessment, err := GoldenBackedAssessment(c.ID)
		if err != nil {
			return nil, fmt.Errorf("case %s: %w", c.ID, err)
		}
		copy := c
		copy.Assessment = assessment
		env := copy.Envelope
		env.FinancialRiskAssessment = cloneAssessment(&assessment)
		copy.Envelope = env
		out[i] = copy
	}
	if len(out) != len(EvaluationGoldenCaseIDs) {
		return nil, fmt.Errorf("assessment fixture count mismatch: got %d want %d", len(out), len(EvaluationGoldenCaseIDs))
	}
	return out, nil
}

func cloneAssessment(a *contract.FinancialRiskAssessmentDTO) *contract.FinancialRiskAssessmentDTO {
	if a == nil {
		return nil
	}
	copy := *a
	copy.Signals = append([]contract.FinancialRiskSignalDTO(nil), a.Signals...)
	copy.DataCompleteness.RequiredUnknownReasonCodes = append(
		[]string(nil), a.DataCompleteness.RequiredUnknownReasonCodes...,
	)
	return &copy
}

// AssessmentMigrationRow documents legacy vs v2 assessment semantics for reporting.
type AssessmentMigrationRow struct {
	CaseID                string    `json:"caseId"`
	LegacyExpectedRisk    RiskLevel `json:"legacyExpectedRisk"`
	V2OverallLevel        string    `json:"v2OverallLevel"`
	DebtDataState         string    `json:"debtDataState"`
	SignalReasonCodes     []string  `json:"signalReasonCodes"`
	RequiredUnknowns      []string  `json:"requiredUnknowns"`
	NarrativeConstraint   string    `json:"narrativeConstraint,omitempty"`
	MigrationStatus       string    `json:"migrationStatus"`
	AssessmentTruthSource string    `json:"assessmentTruthSource"`
	GoldenParityVerified  bool      `json:"goldenParityVerified"`
}

// BuildAssessmentMigrationTable returns the 29-case migration audit table.
func BuildAssessmentMigrationTable(cases []EvaluationCase) ([]AssessmentMigrationRow, error) {
	rows := make([]AssessmentMigrationRow, 0, len(cases))
	for _, c := range cases {
		a := c.Assessment
		if a.OverallLevel == "" {
			return nil, fmt.Errorf("case %s missing assessment fixture", c.ID)
		}
		reasons := make([]string, 0, len(a.Signals))
		for _, s := range a.Signals {
			if s.Level != "safe" {
				reasons = append(reasons, s.ReasonCode)
			}
		}
		constraint := narrativeConstraintForCase(c)
		status := "aligned"
		if legacyRiskLevel(c.ExpectedRiskLevel) != a.OverallLevel && len(reasons) == 0 && a.OverallLevel == "safe" {
			if c.ExpectedRiskLevel == RiskLevelWarning || c.ExpectedRiskLevel == RiskLevelRisk {
				status = "legacyExpectedRiskDiffers_policyOwnsRisk"
			}
		}
		truthSource := AssessmentTruthSourceSwiftGolden
		goldenVerified := false
		if isGoldenBackedCase(c.ID) {
			golden, err := LoadEvaluationGolden(c.ID)
			if err == nil && assessmentsEqual(golden.FinancialRiskAssessment, a) {
				goldenVerified = true
			}
		}
		rows = append(rows, AssessmentMigrationRow{
			CaseID:                c.ID,
			LegacyExpectedRisk:    c.ExpectedRiskLevel,
			V2OverallLevel:        a.OverallLevel,
			DebtDataState:         a.DebtDataState,
			SignalReasonCodes:     reasons,
			RequiredUnknowns:      append([]string(nil), a.DataCompleteness.RequiredUnknownReasonCodes...),
			NarrativeConstraint:   constraint,
			MigrationStatus:       status,
			AssessmentTruthSource: truthSource,
			GoldenParityVerified:  goldenVerified,
		})
	}
	return rows, nil
}

func legacyRiskLevel(level RiskLevel) string {
	switch level {
	case RiskLevelRisk:
		return "risk"
	case RiskLevelWarning:
		return "warning"
	default:
		return "safe"
	}
}

func narrativeConstraintForCase(c EvaluationCase) string {
	switch c.Assessment.DebtDataState {
	case "knownNoDebt":
		return "noDebtPressureClaims"
	case "missing":
		return "acknowledgeMissingDebt"
	case "partial":
		return "partialDebtOnly"
	}
	if len(c.Assessment.DataCompleteness.RequiredUnknownReasonCodes) > 0 && c.Assessment.OverallLevel == "safe" {
		return "safePlusMissing"
	}
	return ""
}

func assessmentsEqual(a, b contract.FinancialRiskAssessmentDTO) bool {
	if a.OverallLevel != b.OverallLevel || a.PolicyVersion != b.PolicyVersion || a.DebtDataState != b.DebtDataState {
		return false
	}
	if len(a.Signals) != len(b.Signals) {
		return false
	}
	for i := range a.Signals {
		left, right := a.Signals[i], b.Signals[i]
		if left.Kind != right.Kind || left.Level != right.Level || left.ReasonCode != right.ReasonCode {
			return false
		}
		if !stringSliceEqual(left.SourceFactKeys, right.SourceFactKeys) {
			return false
		}
		if !stringSliceEqual(sortedStrings(left.RecommendedActionDestinations), sortedStrings(right.RecommendedActionDestinations)) {
			return false
		}
	}
	leftC, rightC := a.DataCompleteness, b.DataCompleteness
	if leftC.Debt != rightC.Debt || leftC.CashFlowProjection != rightC.CashFlowProjection ||
		leftC.Income != rightC.Income || leftC.Expense != rightC.Expense {
		return false
	}
	return stringSliceEqual(leftC.RequiredUnknownReasonCodes, rightC.RequiredUnknownReasonCodes)
}

func stringSliceEqual(a, b []string) bool {
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
