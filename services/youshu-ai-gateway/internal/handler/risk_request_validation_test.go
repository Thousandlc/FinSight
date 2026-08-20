package handler_test

import (
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/factpack"
	"github.com/youshu/youshu-ai-gateway/internal/handler"
)

func repoRoot(t *testing.T) string {
	t.Helper()
	_, file, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime caller failed")
	}
	return filepath.Clean(filepath.Join(filepath.Dir(file), "..", "..", "..", ".."))
}

func loadGoldenRisk(t *testing.T, name string) contract.FinancialRiskAssessmentDTO {
	t.Helper()
	path := filepath.Join(repoRoot(t), "TestFixtures", "FinancialRiskGateway", name)
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var assessment contract.FinancialRiskAssessmentDTO
	if err := json.Unmarshal(data, &assessment); err != nil {
		t.Fatal(err)
	}
	return assessment
}

func sampleAllowedFactKeys() []string {
	facts := sampleRequest().MonthlySummaryFacts
	return factpack.BuildKeySets(facts).AllowedFactKeys
}

func TestGoldenSafeKnownNoDebt(t *testing.T) {
	assessment := loadGoldenRisk(t, "golden_safe_known_no_debt.json")
	if err := handler.ValidateFinancialRiskAssessment(assessment, sampleAllowedFactKeys()); err != nil {
		t.Fatal(err)
	}
}

func TestGoldenWarningKnownDebt(t *testing.T) {
	assessment := loadGoldenRisk(t, "golden_warning_known_debt.json")
	if err := handler.ValidateFinancialRiskAssessment(assessment, sampleAllowedFactKeys()); err != nil {
		t.Fatal(err)
	}
}

func TestGoldenMissingDebt(t *testing.T) {
	assessment := loadGoldenRisk(t, "golden_missing_debt.json")
	if err := handler.ValidateFinancialRiskAssessment(assessment, sampleAllowedFactKeys()); err != nil {
		t.Fatal(err)
	}
}

func TestSafeNoSignalsPass(t *testing.T) {
	assessment := loadGoldenRisk(t, "golden_safe_known_no_debt.json")
	if err := handler.ValidateFinancialRiskAssessment(assessment, sampleAllowedFactKeys()); err != nil {
		t.Fatal(err)
	}
}

func TestWarningSignalPass(t *testing.T) {
	assessment := loadGoldenRisk(t, "golden_warning_known_debt.json")
	if err := handler.ValidateFinancialRiskAssessment(assessment, sampleAllowedFactKeys()); err != nil {
		t.Fatal(err)
	}
}

func TestOverallSafeWithWarningSignalFails(t *testing.T) {
	assessment := loadGoldenRisk(t, "golden_warning_known_debt.json")
	assessment.OverallLevel = "safe"
	if err := handler.ValidateFinancialRiskAssessment(assessment, sampleAllowedFactKeys()); err == nil {
		t.Fatal("expected overallLevel mismatch")
	}
}

func TestKnownNoDebtWithDebtPressureFails(t *testing.T) {
	assessment := loadGoldenRisk(t, "golden_warning_known_debt.json")
	assessment.DebtDataState = "knownNoDebt"
	assessment.DataCompleteness.Debt = "known"
	if err := handler.ValidateFinancialRiskAssessment(assessment, sampleAllowedFactKeys()); err == nil {
		t.Fatal("expected knownNoDebt incompatible signal")
	}
}

func TestMissingDebtWithoutUnknownFails(t *testing.T) {
	assessment := loadGoldenRisk(t, "golden_missing_debt.json")
	assessment.DataCompleteness.RequiredUnknownReasonCodes = []string{}
	if err := handler.ValidateFinancialRiskAssessment(assessment, sampleAllowedFactKeys()); err == nil {
		t.Fatal("expected missing debtDataMissing unknown")
	}
}

func TestUnregisteredSourceFactKeyFails(t *testing.T) {
	assessment := loadGoldenRisk(t, "golden_warning_known_debt.json")
	assessment.Signals[0].SourceFactKeys = []string{"notARegisteredFactKey"}
	if err := handler.ValidateFinancialRiskAssessment(assessment, sampleAllowedFactKeys()); err == nil {
		t.Fatal("expected unregistered sourceFactKey")
	}
}

func TestDuplicateSignalFails(t *testing.T) {
	assessment := loadGoldenRisk(t, "golden_warning_known_debt.json")
	assessment.Signals = append(assessment.Signals, assessment.Signals[0])
	if err := handler.ValidateFinancialRiskAssessment(assessment, sampleAllowedFactKeys()); err == nil {
		t.Fatal("expected duplicate signal")
	}
}

func TestMonthlySummaryRequiresRiskAssessment(t *testing.T) {
	req := sampleRequest()
	req.FinancialRiskAssessment = nil
	if err := handler.ValidateRequestEnvelope(req); err == nil {
		t.Fatal("expected missing financialRiskAssessment")
	}
}

func TestNonMonthlySummaryRejectsRiskAssessment(t *testing.T) {
	req := sampleRequest()
	req.Operation = contract.OperationAsk
	assessment := loadGoldenRisk(t, "golden_safe_known_no_debt.json")
	req.FinancialRiskAssessment = &assessment
	if err := handler.ValidateRequestEnvelope(req); err == nil {
		t.Fatal("expected unexpected financialRiskAssessment")
	}
}

func TestInvalidReasonCodeFails(t *testing.T) {
	assessment := loadGoldenRisk(t, "golden_warning_known_debt.json")
	assessment.Signals[0].ReasonCode = "notARealReasonCode"
	if err := handler.ValidateFinancialRiskAssessment(assessment, sampleAllowedFactKeys()); err == nil {
		t.Fatal("expected invalid signal reasonCode")
	}
}

func TestInvalidActionDestinationFails(t *testing.T) {
	assessment := loadGoldenRisk(t, "golden_warning_known_debt.json")
	assessment.Signals[0].RecommendedActionDestinations = []string{"notAllowed"}
	if err := handler.ValidateFinancialRiskAssessment(assessment, sampleAllowedFactKeys()); err == nil {
		t.Fatal("expected invalid action destination")
	}
}

func TestRiskLevelWithRiskSignalPass(t *testing.T) {
	assessment := loadGoldenRisk(t, "golden_warning_known_debt.json")
	assessment.OverallLevel = "risk"
	assessment.Signals = []contract.FinancialRiskSignalDTO{
		{
			Kind:                          "cashFlow",
			Level:                         "risk",
			ReasonCode:                    "negativeProjectedBalance",
			SourceFactKeys:                []string{"minimumBalance"},
			RecommendedActionDestinations: []string{"cashFlow"},
		},
	}
	if err := handler.ValidateFinancialRiskAssessment(assessment, sampleAllowedFactKeys()); err != nil {
		t.Fatal(err)
	}
}

func TestPartialDebtWithDTIWarningPass(t *testing.T) {
	assessment := loadGoldenRisk(t, "golden_warning_known_debt.json")
	assessment.DebtDataState = "partial"
	assessment.DataCompleteness.Debt = "partial"
	if err := handler.ValidateFinancialRiskAssessment(assessment, sampleAllowedFactKeys()); err != nil {
		t.Fatal(err)
	}
}

func TestDuplicateSourceFactKeysFails(t *testing.T) {
	assessment := loadGoldenRisk(t, "golden_warning_known_debt.json")
	assessment.Signals[0].SourceFactKeys = []string{
		"debtPaymentToIncomePercent",
		"debtPaymentToIncomePercent",
	}
	if err := handler.ValidateFinancialRiskAssessment(assessment, sampleAllowedFactKeys()); err == nil {
		t.Fatal("expected duplicate sourceFactKeys")
	}
}

func TestDuplicateRequiredUnknownFails(t *testing.T) {
	assessment := loadGoldenRisk(t, "golden_missing_debt.json")
	assessment.DataCompleteness.RequiredUnknownReasonCodes = []string{
		"debtDataMissing",
		"debtDataMissing",
	}
	if err := handler.ValidateFinancialRiskAssessment(assessment, sampleAllowedFactKeys()); err == nil {
		t.Fatal("expected duplicate requiredUnknownReasonCode")
	}
}

func debtPressureAllowedFactKeys(t *testing.T) []string {
	t.Helper()
	level := "high"
	facts := sampleRequest().MonthlySummaryFacts
	facts.DebtPressureLevel = &level
	return factpack.BuildKeySets(facts).AllowedFactKeys
}

func TestGoldenDebtPressureHigh(t *testing.T) {
	assessment := loadGoldenRisk(t, "golden_debt_pressure_high.json")
	if err := handler.ValidateFinancialRiskAssessment(assessment, debtPressureAllowedFactKeys(t)); err != nil {
		t.Fatal(err)
	}
}

func TestDebtPressureLevelRegisteredWhenPresent(t *testing.T) {
	level := "high"
	facts := sampleRequest().MonthlySummaryFacts
	facts.DebtPressureLevel = &level
	keys := factpack.BuildKeySets(facts)
	if _, ok := keys.FactKeys["debtPressureLevel"]; !ok {
		t.Fatal("expected debtPressureLevel in FactKeys when present")
	}
}

func TestDebtPressureLevelOmittedWhenAbsent(t *testing.T) {
	facts := sampleRequest().MonthlySummaryFacts
	facts.DebtPressureLevel = nil
	keys := factpack.BuildKeySets(facts)
	if _, ok := keys.FactKeys["debtPressureLevel"]; ok {
		t.Fatal("debtPressureLevel must not register when absent")
	}
	if _, ok := keys.RefKeys["debtPressureLevel"]; ok {
		t.Fatal("debtPressureLevel reference must not register when absent")
	}
}

func TestDebtPressureFakeSourceFails(t *testing.T) {
	assessment := loadGoldenRisk(t, "golden_debt_pressure_high.json")
	assessment.Signals[0].SourceFactKeys = []string{"fakeDebtPressure"}
	if err := handler.ValidateFinancialRiskAssessment(assessment, debtPressureAllowedFactKeys(t)); err == nil {
		t.Fatal("expected unregistered sourceFactKey")
	}
}

func TestPolicyV1ValidReasonPass(t *testing.T) {
	assessment := loadGoldenRisk(t, "golden_warning_known_debt.json")
	if err := handler.ValidateFinancialRiskAssessment(assessment, sampleAllowedFactKeys()); err != nil {
		t.Fatal(err)
	}
}

func TestPolicyV1CriticalDebtPaymentToIncomeFails(t *testing.T) {
	assessment := loadGoldenRisk(t, "golden_warning_known_debt.json")
	assessment.Signals[0].ReasonCode = "criticalDebtPaymentToIncome"
	if err := handler.ValidateFinancialRiskAssessment(assessment, sampleAllowedFactKeys()); err == nil {
		t.Fatal("expected reasonCodeNotAllowedForPolicyVersion")
	}
}

func TestPolicyV1HealthyCashBufferFails(t *testing.T) {
	assessment := loadGoldenRisk(t, "golden_safe_known_no_debt.json")
	assessment.Signals = []contract.FinancialRiskSignalDTO{
		{
			Kind:           "cashFlow",
			Level:          "warning",
			ReasonCode:     "healthyCashBuffer",
			SourceFactKeys: []string{"availableCash"},
		},
	}
	assessment.OverallLevel = "warning"
	if err := handler.ValidateFinancialRiskAssessment(assessment, sampleAllowedFactKeys()); err == nil {
		t.Fatal("expected reasonCodeNotAllowedForPolicyVersion")
	}
}
