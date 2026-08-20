package eval

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"sync"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
)

const (
	AssessmentTruthSourceSwiftGolden = "swift-policy-golden"
	AssessmentTruthSourceLegacyGo    = "legacy-go-fixture"
)

// EvaluationGoldenFixture is the canonical cross-language assessment fixture.
type EvaluationGoldenFixture struct {
	CaseID                  string                              `json:"caseId"`
	AssessmentTruthSource   string                              `json:"assessmentTruthSource"`
	GenerationPath          string                              `json:"generationPath"`
	PolicyVectorID          *string                             `json:"policyVectorId"`
	ProductionScenario      *string                             `json:"productionScenario"`
	FinancialRiskAssessment contract.FinancialRiskAssessmentDTO `json:"financialRiskAssessment"`
}

// SmokeGoldenCaseIDs lists the six v2 smoke cases backed by Swift policy goldens.
var SmokeGoldenCaseIDs = []string{
	"A01_healthy_cashflow",
	"C03_high_monthly_payment",
	"B04_short_term_negative_balance",
	"C01_no_debt",
	"E05_missing_debt_data",
	"E01_partial_debt_data",
}

// EvaluationGoldenCaseIDs lists all 29 evaluation cases with Swift-policy goldens.
var EvaluationGoldenCaseIDs = []string{
	"A01_healthy_cashflow",
	"A02_high_income_low_expense",
	"A03_balanced_budget",
	"A04_mild_month_end_pressure",
	"B01_minimum_below_safe",
	"B02_month_end_below_safe",
	"B03_month_end_near_zero",
	"B04_short_term_negative_balance",
	"C01_no_debt",
	"C02_low_debt_pressure",
	"C03_high_monthly_payment",
	"C04_multiple_debts",
	"C05_high_dti",
	"C06_debt_but_adequate_cashflow",
	"D01_high_expense_month",
	"D02_zero_income_month",
	"D03_income_decline",
	"D04_expense_increase",
	"E01_partial_debt_data",
	"E02_no_cashflow_projection",
	"E03_no_budget",
	"E04_partial_facts_missing",
	"E05_missing_debt_data",
	"F01_all_amounts_zero",
	"F02_tiny_balance",
	"F03_large_amounts",
	"F04_decimal_amounts",
	"F05_same_amount_multiple_facts",
	"F06_no_warning_expected",
}

var (
	goldenCache     map[string]EvaluationGoldenFixture
	goldenCacheErr  error
	goldenCacheOnce sync.Once
)

func repoRoot() (string, error) {
	_, file, _, ok := runtime.Caller(0)
	if !ok {
		return "", fmt.Errorf("runtime caller failed")
	}
	return filepath.Clean(filepath.Join(filepath.Dir(file), "..", "..", "..", "..")), nil
}

func loadAllGoldenFixtures() (map[string]EvaluationGoldenFixture, error) {
	goldenCacheOnce.Do(func() {
		root, err := repoRoot()
		if err != nil {
			goldenCacheErr = err
			return
		}
		dir := filepath.Join(root, "TestFixtures", "FinancialRiskEvaluationV2")
		goldenCache = map[string]EvaluationGoldenFixture{}
		for _, caseID := range EvaluationGoldenCaseIDs {
			path := filepath.Join(dir, caseID+".json")
			data, err := os.ReadFile(path)
			if err != nil {
				goldenCacheErr = fmt.Errorf("read golden %s: %w", caseID, err)
				return
			}
			var fixture EvaluationGoldenFixture
			if err := json.Unmarshal(data, &fixture); err != nil {
				goldenCacheErr = fmt.Errorf("decode golden %s: %w", caseID, err)
				return
			}
			if fixture.CaseID != caseID {
				goldenCacheErr = fmt.Errorf("golden caseId mismatch for %s", caseID)
				return
			}
			if fixture.AssessmentTruthSource != AssessmentTruthSourceSwiftGolden {
				goldenCacheErr = fmt.Errorf("%s assessmentTruthSource=%s want swift-policy-golden", caseID, fixture.AssessmentTruthSource)
				return
			}
			goldenCache[caseID] = fixture
		}
	})
	return goldenCache, goldenCacheErr
}

// LoadEvaluationGolden returns the canonical golden fixture for a case.
func LoadEvaluationGolden(caseID string) (EvaluationGoldenFixture, error) {
	fixtures, err := loadAllGoldenFixtures()
	if err != nil {
		return EvaluationGoldenFixture{}, err
	}
	fixture, ok := fixtures[caseID]
	if !ok {
		return EvaluationGoldenFixture{}, fmt.Errorf("missing golden fixture for case %s", caseID)
	}
	return fixture, nil
}

// GoldenBackedAssessment returns the Swift-policy golden assessment for a case.
func GoldenBackedAssessment(caseID string) (contract.FinancialRiskAssessmentDTO, error) {
	fixture, err := LoadEvaluationGolden(caseID)
	if err != nil {
		return contract.FinancialRiskAssessmentDTO{}, err
	}
	return fixture.FinancialRiskAssessment, nil
}

func isGoldenBackedCase(caseID string) bool {
	for _, id := range EvaluationGoldenCaseIDs {
		if id == caseID {
			return true
		}
	}
	return false
}

// GoldenCoverageSummary reports dataset golden closure status.
type GoldenCoverageSummary struct {
	DatasetCases             int  `json:"datasetCases"`
	GoldenCoverage           int  `json:"goldenCoverage"`
	GoldenParityPassed       int  `json:"goldenParityPassed"`
	ProvenancePassed         int  `json:"provenancePassed"`
	ProvenanceEmissionPassed int  `json:"provenanceEmissionPassed"`
	DynamicSchemaPassed      int  `json:"dynamicSchemaPassed"`
	LegacyFallbackCount      int  `json:"legacyFallbackCount"`
	PlannedRuns              int  `json:"plannedRuns"`
	ReadyForFullEval         bool `json:"readyForFullEval"`
}

// BuildGoldenCoverageSummary validates 29/29 golden closure gates offline.
func BuildGoldenCoverageSummary() (GoldenCoverageSummary, error) {
	cases := AllCases()
	summary := GoldenCoverageSummary{
		DatasetCases: len(cases),
		PlannedRuns:  CountRuns(cases),
	}
	for _, caseID := range EvaluationGoldenCaseIDs {
		fixture, err := LoadEvaluationGolden(caseID)
		if err != nil {
			return GoldenCoverageSummary{}, err
		}
		if fixture.AssessmentTruthSource == AssessmentTruthSourceSwiftGolden {
			summary.GoldenCoverage++
		} else {
			summary.LegacyFallbackCount++
		}
		c, err := findCaseByID(caseID)
		if err != nil {
			return GoldenCoverageSummary{}, err
		}
		goldenAssessment, err := GoldenBackedAssessment(caseID)
		if err != nil {
			return GoldenCoverageSummary{}, err
		}
		if assessmentsEqual(c.Assessment, goldenAssessment) {
			summary.GoldenParityPassed++
		}
		if err := factpackValidateRiskSource(c); err == nil {
			summary.ProvenancePassed++
		}
		if err := validateDynamicSchemaOfflineFn(c, c.Assessment); err == nil {
			summary.DynamicSchemaPassed++
		}
	}
	emission, err := BuildProvenanceEmissionMatrixSummary()
	if err != nil {
		return GoldenCoverageSummary{}, err
	}
	summary.ProvenanceEmissionPassed = emission.ProductionEmittedPassed
	summary.ReadyForFullEval =
		summary.DatasetCases == len(EvaluationGoldenCaseIDs) &&
			summary.GoldenCoverage == len(EvaluationGoldenCaseIDs) &&
			summary.GoldenParityPassed == len(EvaluationGoldenCaseIDs) &&
			summary.ProvenancePassed == len(EvaluationGoldenCaseIDs) &&
			summary.ProvenanceEmissionPassed == provenanceEmissionMatrixSize &&
			summary.DynamicSchemaPassed == len(EvaluationGoldenCaseIDs) &&
			summary.LegacyFallbackCount == 0 &&
			summary.PlannedRuns == 37 &&
			emission.Ready
	return summary, nil
}

func factpackValidateRiskSource(c EvaluationCase) error {
	return validateCaseRiskSourceFactAvailability(c)
}

// LegacyMigrationDeltaReport summarizes legacy expectedRisk vs Swift-policy golden deltas.
type LegacyMigrationDeltaReport struct {
	MigratedBeforeC1       int `json:"migratedBeforeC1"`
	NewlyMigratedInC1      int `json:"newlyMigratedInC1"`
	OverallLevelChanged    int `json:"overallLevelChanged"`
	LegacyExpectedWarning  int `json:"legacyExpectedWarning"`
	LegacyExpectedRisk     int `json:"legacyExpectedRisk"`
	GoldenHasSignals       int `json:"goldenHasSignals"`
	SignalPresenceChanged  int `json:"signalPresenceChanged"`
	DebtDataStatePartial   int `json:"debtDataStatePartial"`
	DebtDataStateMissing   int `json:"debtDataStateMissing"`
	DebtDataStateKnownNoDebt int `json:"debtDataStateKnownNoDebt"`
	RequiredUnknownCases   int `json:"requiredUnknownCases"`
}

// BuildLegacyMigrationDeltaReport compares legacy ExpectedRiskLevel with Swift golden truth.
func BuildLegacyMigrationDeltaReport(cases []EvaluationCase) LegacyMigrationDeltaReport {
	preC1 := map[string]struct{}{}
	for _, id := range SmokeGoldenCaseIDs {
		preC1[id] = struct{}{}
	}
	report := LegacyMigrationDeltaReport{MigratedBeforeC1: len(SmokeGoldenCaseIDs)}
	for _, c := range cases {
		if _, ok := preC1[c.ID]; !ok {
			report.NewlyMigratedInC1++
		}
		legacyLevel := legacyRiskLevel(c.ExpectedRiskLevel)
		golden := c.Assessment
		if legacyLevel != golden.OverallLevel {
			report.OverallLevelChanged++
		}
		switch c.ExpectedRiskLevel {
		case RiskLevelWarning:
			report.LegacyExpectedWarning++
		case RiskLevelRisk:
			report.LegacyExpectedRisk++
		}
		goldenHasSignals := len(golden.Signals) > 0
		if goldenHasSignals {
			report.GoldenHasSignals++
		}
		legacyExpectedSignals := c.ExpectedRiskLevel == RiskLevelWarning || c.ExpectedRiskLevel == RiskLevelRisk
		if legacyExpectedSignals != goldenHasSignals {
			report.SignalPresenceChanged++
		}
		switch golden.DebtDataState {
		case "partial":
			report.DebtDataStatePartial++
		case "missing":
			report.DebtDataStateMissing++
		case "knownNoDebt":
			report.DebtDataStateKnownNoDebt++
		}
		if len(golden.DataCompleteness.RequiredUnknownReasonCodes) > 0 {
			report.RequiredUnknownCases++
		}
	}
	return report
}
