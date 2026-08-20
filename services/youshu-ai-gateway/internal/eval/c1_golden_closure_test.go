package eval

import (
	"context"
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/config"
	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/factpack"
)

func TestC1GoldenCoverageSummary29Of29(t *testing.T) {
	summary, err := BuildGoldenCoverageSummary()
	if err != nil {
		t.Fatal(err)
	}
	if summary.DatasetCases != 29 {
		t.Fatalf("datasetCases=%d", summary.DatasetCases)
	}
	if summary.PlannedRuns != 37 {
		t.Fatalf("plannedRuns=%d want 37", summary.PlannedRuns)
	}
	if summary.GoldenCoverage != 29 {
		t.Fatalf("goldenCoverage=%d", summary.GoldenCoverage)
	}
	if summary.GoldenParityPassed != 29 {
		t.Fatalf("goldenParityPassed=%d", summary.GoldenParityPassed)
	}
	if summary.ProvenancePassed != 29 {
		t.Fatalf("provenancePassed=%d", summary.ProvenancePassed)
	}
	if summary.DynamicSchemaPassed != 29 {
		t.Fatalf("dynamicSchemaPassed=%d", summary.DynamicSchemaPassed)
	}
	if summary.LegacyFallbackCount != 0 {
		t.Fatalf("legacyFallbackCount=%d", summary.LegacyFallbackCount)
	}
	if !summary.ReadyForFullEval {
		t.Fatalf("readyForFullEval=false: %+v", summary)
	}
}

func TestC1AllCasesSwiftPolicyGoldenTruthSource(t *testing.T) {
	for _, caseID := range EvaluationGoldenCaseIDs {
		fixture, err := LoadEvaluationGolden(caseID)
		if err != nil {
			t.Fatalf("%s: %v", caseID, err)
		}
		if fixture.AssessmentTruthSource != AssessmentTruthSourceSwiftGolden {
			t.Fatalf("%s truthSource=%s", caseID, fixture.AssessmentTruthSource)
		}
	}
}

func TestC1EvaluationGoldenCaseIDsMatchDataset(t *testing.T) {
	cases := AllCases()
	if len(cases) != 29 || len(EvaluationGoldenCaseIDs) != 29 {
		t.Fatalf("case count mismatch")
	}
	for i, c := range cases {
		if c.ID != EvaluationGoldenCaseIDs[i] {
			t.Fatalf("ordering mismatch at %d: %s vs %s", i, c.ID, EvaluationGoldenCaseIDs[i])
		}
	}
}

func TestC1DebtPressureLevelKnownDebtOnly(t *testing.T) {
	for _, c := range AllCases() {
		facts := c.Envelope.MonthlySummaryFacts
		if facts.DebtPressureLevel == nil {
			continue
		}
		if c.Assessment.DebtDataState != "knownDebt" {
			t.Fatalf("%s registers debtPressureLevel with debtDataState=%s", c.ID, c.Assessment.DebtDataState)
		}
	}
	for _, caseID := range []string{"E01_partial_debt_data", "E05_missing_debt_data", "C01_no_debt"} {
		c, err := findCaseByID(caseID)
		if err != nil {
			t.Fatal(err)
		}
		if c.Envelope.MonthlySummaryFacts.DebtPressureLevel != nil {
			t.Fatalf("%s must not register debtPressureLevel", caseID)
		}
	}
}

func TestC1HighDebtPressureScoreFixture(t *testing.T) {
	c, err := findCaseByID("C04_multiple_debts")
	if err != nil {
		t.Fatal(err)
	}
	if len(c.Assessment.Signals) != 1 || c.Assessment.Signals[0].ReasonCode != "highDebtPressureScore" {
		t.Fatalf("unexpected C04 signals: %+v", c.Assessment.Signals)
	}
	if c.Envelope.MonthlySummaryFacts.DebtPressureLevel == nil || *c.Envelope.MonthlySummaryFacts.DebtPressureLevel != "high" {
		t.Fatal("C04 must register debtPressureLevel=high")
	}
	if err := factpack.ValidateRiskSourceFactAvailability(&c.Assessment, c.Envelope.MonthlySummaryFacts); err != nil {
		t.Fatal(err)
	}
}

func TestC1CriticalDebtPressureFixture(t *testing.T) {
	c, err := findCaseByID("C06_debt_but_adequate_cashflow")
	if err != nil {
		t.Fatal(err)
	}
	if len(c.Assessment.Signals) != 1 || c.Assessment.Signals[0].ReasonCode != "criticalDebtPressure" {
		t.Fatalf("unexpected C06 signals: %+v", c.Assessment.Signals)
	}
	if c.Envelope.MonthlySummaryFacts.DebtPressureLevel == nil || *c.Envelope.MonthlySummaryFacts.DebtPressureLevel != "critical" {
		t.Fatal("C06 must register debtPressureLevel=critical")
	}
	if err := factpack.ValidateRiskSourceFactAvailability(&c.Assessment, c.Envelope.MonthlySummaryFacts); err != nil {
		t.Fatal(err)
	}
}

func TestC1RunFullOfflinePreflightPasses(t *testing.T) {
	plan, err := BuildFullRunPlan()
	if err != nil {
		t.Fatal(err)
	}
	status, err := RunFullOfflinePreflight(plan)
	if err != nil {
		t.Fatal(err)
	}
	if !status.Passed {
		t.Fatalf("full offline preflight failed: %s", status.BlockReason)
	}
}

func TestC1FullEvalPreflightBlocksIncompleteGoldenCoverage(t *testing.T) {
	plan := EvaluationRunPlan{
		Type:              RunPlanTypeFull,
		ExpectedCaseCount: 28,
		ExpectedRunCount:  37,
	}
	status, err := RunFullOfflinePreflight(plan)
	if err != nil {
		t.Fatal(err)
	}
	if status.Passed {
		t.Fatal("expected block for 28/29 plan")
	}
}


func TestC1FullEvalLivePreflightBlocksWithZeroHTTP(t *testing.T) {
	old := validateDynamicSchemaOfflineFn
	t.Cleanup(func() { validateDynamicSchemaOfflineFn = old })
	validateDynamicSchemaOfflineFn = func(EvaluationCase, contract.FinancialRiskAssessmentDTO) error {
		return errDynamicSchemaBlocked
	}
	cfg := config.Config{
		UpstreamAIProvider:          config.UpstreamBailian,
		BailianAPIKey:               "test-key",
		BailianBaseURL:              "https://example.test",
		BailianModel:                "qwen3.7-plus",
		BailianStructuredOutputMode: config.StructuredOutputJSONSchemaStrict,
	}
	t.Setenv(EnvEvalLive, "1")
	t.Setenv(EnvEvalFull, "1")
	plan, err := BuildFullRunPlan()
	if err != nil {
		t.Fatal(err)
	}
	result, err := RunLivePreflight(cfg, plan)
	if err != nil {
		t.Fatal(err)
	}
	if result.Passed {
		t.Fatal("expected full eval preflight failure")
	}
	if result.RunStatus != RunStatusPreflightFailed {
		t.Fatalf("runStatus=%s", result.RunStatus)
	}
	upstream := &noopUpstream{}
	report, err := RunEvaluation(context.Background(), cfg, upstream, FilterOptions{})
	if err != nil {
		t.Fatal(err)
	}
	if upstream.calls != 0 {
		t.Fatalf("expected 0 HTTP attempts, got %d", upstream.calls)
	}
	if report.RunStatus != RunStatusPreflightFailed {
		t.Fatalf("report runStatus=%s", report.RunStatus)
	}
}

func TestC1LegacyMigrationDeltaReport(t *testing.T) {
	report := BuildLegacyMigrationDeltaReport(AllCases())
	if report.MigratedBeforeC1 != 6 {
		t.Fatalf("migratedBeforeC1=%d", report.MigratedBeforeC1)
	}
	if report.NewlyMigratedInC1 != 23 {
		t.Fatalf("newlyMigratedInC1=%d", report.NewlyMigratedInC1)
	}
}

func TestC1ZeroIncomeFactRegistered(t *testing.T) {
	c, err := findCaseByID("D02_zero_income_month")
	if err != nil {
		t.Fatal(err)
	}
	if c.Envelope.MonthlySummaryFacts.MonthlyIncome.Amount != "0" {
		t.Fatal("monthlyIncome=0 must be present, not absent")
	}
	if !containsFactKey(c.Envelope.MonthlySummaryFacts, "monthlyIncome") {
		t.Fatal("monthlyIncome must register in FactPack")
	}
}
