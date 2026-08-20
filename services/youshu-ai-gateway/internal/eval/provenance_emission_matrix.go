package eval

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sync"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/factpack"
	"github.com/youshu/youshu-ai-gateway/internal/provider"
)

const (
	provenanceEmissionMatrixSize     = 7
	monthEndBelowSafeFallbackScenario = "month_end_below_safe_fallback"
)

// ProvenanceEmissionFixture is an offline policy-emitted scenario outside the 29-case dataset.
type ProvenanceEmissionFixture struct {
	ScenarioID              string                              `json:"scenarioId"`
	ReasonCode              string                              `json:"reasonCode"`
	AssessmentTruthSource   string                              `json:"assessmentTruthSource"`
	GenerationPath          string                              `json:"generationPath"`
	FinancialRiskAssessment contract.FinancialRiskAssessmentDTO `json:"financialRiskAssessment"`
	MonthlySummaryFacts     contract.MonthlySummaryFactsDTO     `json:"monthlySummaryFacts"`
}

// ProvenanceEmissionEntry describes one v1 reason code production-emitted path.
type ProvenanceEmissionEntry struct {
	ReasonCode        string
	EvalCaseID        string
	OfflineScenarioID string
	SourceFactKeys    []string
}

// V1ProvenanceEmissionMatrix lists all seven v1 emitted signal reason codes and their fixtures.
// EvalCaseID entries must emit the reason via Swift Production Policy golden assessment.
// OfflineScenarioID entries use dedicated provenance-emission fixtures (not eval cases).
var V1ProvenanceEmissionMatrix = []ProvenanceEmissionEntry{
	{ReasonCode: "negativeProjectedBalance", EvalCaseID: "B04_short_term_negative_balance", SourceFactKeys: []string{"minimumBalance"}},
	{ReasonCode: "cashFlowBelowSafeBalance", EvalCaseID: "B01_minimum_below_safe", SourceFactKeys: []string{"minimumBalance", "safeBalance"}},
	{ReasonCode: "monthEndBelowSafeBalance", OfflineScenarioID: monthEndBelowSafeFallbackScenario, SourceFactKeys: []string{"estimatedMonthEndBalance", "safeBalance"}},
	{ReasonCode: "highDebtPressureScore", EvalCaseID: "C04_multiple_debts", SourceFactKeys: []string{"debtPressureLevel"}},
	{ReasonCode: "criticalDebtPressure", EvalCaseID: "C06_debt_but_adequate_cashflow", SourceFactKeys: []string{"debtPressureLevel"}},
	{ReasonCode: "highDebtPaymentToIncome", EvalCaseID: "E01_partial_debt_data", SourceFactKeys: []string{"debtPaymentToIncomePercent"}},
	{ReasonCode: "zeroIncomeWithExpenses", EvalCaseID: "D02_zero_income_month", SourceFactKeys: []string{"monthlyIncome", "monthlyExpense"}},
}

// ProvenanceEmissionMatrixSummary reports production-emitted path coverage for v1 reason codes.
type ProvenanceEmissionMatrixSummary struct {
	TotalReasons            int  `json:"totalReasons"`
	ProductionEmittedPassed int  `json:"productionEmittedPassed"`
	FactAvailabilityPassed  int  `json:"factAvailabilityPassed"`
	Ready                   bool `json:"ready"`
}

var (
	offlineEmissionFixtures     map[string]ProvenanceEmissionFixture
	offlineEmissionFixturesErr  error
	offlineEmissionFixturesOnce sync.Once
)

func loadOfflineProvenanceEmissionFixtures() (map[string]ProvenanceEmissionFixture, error) {
	offlineEmissionFixturesOnce.Do(func() {
		root, err := repoRoot()
		if err != nil {
			offlineEmissionFixturesErr = err
			return
		}
		dir := filepath.Join(root, "TestFixtures", "FinancialRiskProvenanceEmission")
		offlineEmissionFixtures = map[string]ProvenanceEmissionFixture{}
		for _, entry := range V1ProvenanceEmissionMatrix {
			if entry.OfflineScenarioID == "" {
				continue
			}
			path := filepath.Join(dir, entry.OfflineScenarioID+".json")
			data, err := os.ReadFile(path)
			if err != nil {
				offlineEmissionFixturesErr = fmt.Errorf("read provenance emission %s: %w", entry.OfflineScenarioID, err)
				return
			}
			var fixture ProvenanceEmissionFixture
			if err := json.Unmarshal(data, &fixture); err != nil {
				offlineEmissionFixturesErr = fmt.Errorf("decode provenance emission %s: %w", entry.OfflineScenarioID, err)
				return
			}
			if fixture.ScenarioID != entry.OfflineScenarioID {
				offlineEmissionFixturesErr = fmt.Errorf("scenarioId mismatch for %s", entry.OfflineScenarioID)
				return
			}
			if fixture.ReasonCode != entry.ReasonCode {
				offlineEmissionFixturesErr = fmt.Errorf("%s reasonCode=%s want %s", entry.OfflineScenarioID, fixture.ReasonCode, entry.ReasonCode)
				return
			}
			if fixture.AssessmentTruthSource != AssessmentTruthSourceSwiftGolden {
				offlineEmissionFixturesErr = fmt.Errorf("%s truthSource=%s", entry.OfflineScenarioID, fixture.AssessmentTruthSource)
				return
			}
			offlineEmissionFixtures[entry.OfflineScenarioID] = fixture
		}
	})
	return offlineEmissionFixtures, offlineEmissionFixturesErr
}

// LoadProvenanceEmissionFixture returns an offline production-emitted scenario fixture.
func LoadProvenanceEmissionFixture(scenarioID string) (ProvenanceEmissionFixture, error) {
	fixtures, err := loadOfflineProvenanceEmissionFixtures()
	if err != nil {
		return ProvenanceEmissionFixture{}, err
	}
	fixture, ok := fixtures[scenarioID]
	if !ok {
		return ProvenanceEmissionFixture{}, fmt.Errorf("missing provenance emission fixture %s", scenarioID)
	}
	return fixture, nil
}

// BuildProvenanceEmissionMatrixSummary validates 7/7 production-emitted provenance paths.
func BuildProvenanceEmissionMatrixSummary() (ProvenanceEmissionMatrixSummary, error) {
	summary := ProvenanceEmissionMatrixSummary{TotalReasons: len(V1ProvenanceEmissionMatrix)}
	for _, entry := range V1ProvenanceEmissionMatrix {
		assessment, facts, err := resolveProvenanceEmissionScenario(entry)
		if err != nil {
			return ProvenanceEmissionMatrixSummary{}, err
		}
		signal, ok := findSignalByReasonCode(assessment, entry.ReasonCode)
		if !ok {
			continue
		}
		if !signalSourceFactKeysMatch(signal, entry.SourceFactKeys) {
			continue
		}
		summary.ProductionEmittedPassed++
		if err := factpack.ValidateRiskSourceFactAvailability(&assessment, facts); err == nil {
			summary.FactAvailabilityPassed++
		}
	}
	summary.Ready = summary.ProductionEmittedPassed == provenanceEmissionMatrixSize &&
		summary.FactAvailabilityPassed == provenanceEmissionMatrixSize
	return summary, nil
}

// ValidateProvenanceEmissionMatrix verifies all seven reason codes have production-emitted paths.
func ValidateProvenanceEmissionMatrix() error {
	summary, err := BuildProvenanceEmissionMatrixSummary()
	if err != nil {
		return err
	}
	if summary.Ready {
		return nil
	}
	return fmt.Errorf(
		"provenance emission matrix incomplete: productionEmitted=%d/%d factAvailability=%d/%d",
		summary.ProductionEmittedPassed, summary.TotalReasons,
		summary.FactAvailabilityPassed, summary.TotalReasons,
	)
}

func resolveProvenanceEmissionScenario(entry ProvenanceEmissionEntry) (contract.FinancialRiskAssessmentDTO, *contract.MonthlySummaryFactsDTO, error) {
	if entry.OfflineScenarioID != "" {
		fixture, err := LoadProvenanceEmissionFixture(entry.OfflineScenarioID)
		if err != nil {
			return contract.FinancialRiskAssessmentDTO{}, nil, err
		}
		facts := fixture.MonthlySummaryFacts
		return fixture.FinancialRiskAssessment, &facts, nil
	}
	c, err := findCaseByID(entry.EvalCaseID)
	if err != nil {
		return contract.FinancialRiskAssessmentDTO{}, nil, err
	}
	if c.Envelope.MonthlySummaryFacts == nil {
		return contract.FinancialRiskAssessmentDTO{}, nil, fmt.Errorf("%s missing facts", entry.EvalCaseID)
	}
	return c.Assessment, c.Envelope.MonthlySummaryFacts, nil
}

func findSignalByReasonCode(assessment contract.FinancialRiskAssessmentDTO, reasonCode string) (contract.FinancialRiskSignalDTO, bool) {
	for _, signal := range assessment.Signals {
		if signal.ReasonCode == reasonCode {
			return signal, true
		}
	}
	return contract.FinancialRiskSignalDTO{}, false
}

func signalSourceFactKeysMatch(signal contract.FinancialRiskSignalDTO, want []string) bool {
	if len(signal.SourceFactKeys) != len(want) {
		return false
	}
	for i := range want {
		if signal.SourceFactKeys[i] != want[i] {
			return false
		}
	}
	return true
}

// ValidateProvenanceEmissionPipeline runs availability, assembler, and post-assembly checks for one entry.
func ValidateProvenanceEmissionPipeline(entry ProvenanceEmissionEntry) error {
	assessment, facts, err := resolveProvenanceEmissionScenario(entry)
	if err != nil {
		return err
	}
	signal, ok := findSignalByReasonCode(assessment, entry.ReasonCode)
	if !ok {
		return fmt.Errorf("%s: production policy did not emit %s", entryLabel(entry), entry.ReasonCode)
	}
	if !signalSourceFactKeysMatch(signal, entry.SourceFactKeys) {
		return fmt.Errorf("%s: sourceFactKeys=%v want %v", entryLabel(entry), signal.SourceFactKeys, entry.SourceFactKeys)
	}
	keys := factpack.BuildKeySets(facts)
	if err := factpack.ValidateRiskSourceFactAvailability(&assessment, facts); err != nil {
		return fmt.Errorf("%s availability: %w", entryLabel(entry), err)
	}
	model := contract.ModelAssistantAnswerDraftDTO{
		RiskExplanations: []contract.ModelRiskExplanationDTO{{
			ReasonCode: entry.ReasonCode,
			Text:       "synthetic compliant explanation",
		}},
	}
	if err := provider.ValidateExplanationAlignment(model, &assessment, keys); err != nil {
		return fmt.Errorf("%s alignment: %w", entryLabel(entry), err)
	}
	assembled, err := provider.AssembleRiskExplanations(model.RiskExplanations, &assessment)
	if err != nil {
		return fmt.Errorf("%s assemble: %w", entryLabel(entry), err)
	}
	if err := provider.ValidateAssembledRiskExplanationProvenance(assembled, &assessment, keys); err != nil {
		return fmt.Errorf("%s post-assembly: %w", entryLabel(entry), err)
	}
	if len(assembled) != 1 || len(assembled[0].CitedFactKeys) != len(signal.SourceFactKeys) {
		return fmt.Errorf("%s assembled citation count mismatch", entryLabel(entry))
	}
	for i, key := range signal.SourceFactKeys {
		if assembled[0].CitedFactKeys[i] != key {
			return fmt.Errorf("%s citation order mismatch at %d", entryLabel(entry), i)
		}
	}
	if err := validateProvenanceEmissionDynamicSchema(assessment, facts); err != nil {
		return fmt.Errorf("%s dynamic schema: %w", entryLabel(entry), err)
	}
	return nil
}

func validateProvenanceEmissionDynamicSchema(assessment contract.FinancialRiskAssessmentDTO, facts *contract.MonthlySummaryFactsDTO) error {
	c := EvaluationCase{
		ID:         "provenance-emission-offline",
		Assessment: assessment,
		Envelope: contract.RequestEnvelope{
			MonthlySummaryFacts: facts,
		},
	}
	return validateDynamicSchemaOfflineFn(c, assessment)
}

func entryLabel(entry ProvenanceEmissionEntry) string {
	if entry.OfflineScenarioID != "" {
		return entry.OfflineScenarioID
	}
	return entry.EvalCaseID
}

// B02DoesNotEmitMonthEndBelowSafeBalance documents B02 fact availability without emission.
func B02DoesNotEmitMonthEndBelowSafeBalance() bool {
	c, err := findCaseByID("B02_month_end_below_safe")
	if err != nil {
		return false
	}
	_, ok := findSignalByReasonCode(c.Assessment, "monthEndBelowSafeBalance")
	return !ok
}
