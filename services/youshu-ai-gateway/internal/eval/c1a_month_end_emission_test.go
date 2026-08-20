package eval

import (
	"context"
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/config"
	"github.com/youshu/youshu-ai-gateway/internal/factpack"
)

func TestC1AProvenanceEmissionMatrixSevenOfSeven(t *testing.T) {
	summary, err := BuildProvenanceEmissionMatrixSummary()
	if err != nil {
		t.Fatal(err)
	}
	if summary.TotalReasons != 7 {
		t.Fatalf("totalReasons=%d", summary.TotalReasons)
	}
	if summary.ProductionEmittedPassed != 7 {
		t.Fatalf("productionEmittedPassed=%d", summary.ProductionEmittedPassed)
	}
	if summary.FactAvailabilityPassed != 7 {
		t.Fatalf("factAvailabilityPassed=%d", summary.FactAvailabilityPassed)
	}
	if !summary.Ready {
		t.Fatal("provenance emission matrix not ready")
	}
}

func TestC1AMonthEndBelowSafeBalanceProductionEmission(t *testing.T) {
	fixture, err := LoadProvenanceEmissionFixture(monthEndBelowSafeFallbackScenario)
	if err != nil {
		t.Fatal(err)
	}
	if len(fixture.FinancialRiskAssessment.Signals) != 1 {
		t.Fatalf("signals=%+v", fixture.FinancialRiskAssessment.Signals)
	}
	signal := fixture.FinancialRiskAssessment.Signals[0]
	if signal.ReasonCode != "monthEndBelowSafeBalance" {
		t.Fatalf("reasonCode=%s", signal.ReasonCode)
	}
	if signal.Level != "warning" {
		t.Fatalf("level=%s", signal.Level)
	}
	if fixture.FinancialRiskAssessment.OverallLevel != "warning" {
		t.Fatalf("overallLevel=%s", fixture.FinancialRiskAssessment.OverallLevel)
	}
	wantKeys := []string{"estimatedMonthEndBalance", "safeBalance"}
	if len(signal.SourceFactKeys) != len(wantKeys) {
		t.Fatalf("sourceFactKeys=%v", signal.SourceFactKeys)
	}
	for i, key := range wantKeys {
		if signal.SourceFactKeys[i] != key {
			t.Fatalf("sourceFactKeys=%v want %v", signal.SourceFactKeys, wantKeys)
		}
	}
	if fixture.MonthlySummaryFacts.MinimumBalance != nil {
		t.Fatal("minimumBalance must be absent for month-end fallback scenario")
	}
	if fixture.MonthlySummaryFacts.EstimatedMonthEndBalance.Amount != "500" {
		t.Fatalf("monthEnd=%s", fixture.MonthlySummaryFacts.EstimatedMonthEndBalance.Amount)
	}
	if fixture.MonthlySummaryFacts.SafeBalance == nil || fixture.MonthlySummaryFacts.SafeBalance.Amount != "2000" {
		t.Fatalf("safeBalance=%v", fixture.MonthlySummaryFacts.SafeBalance)
	}
	if err := factpack.ValidateRiskSourceFactAvailability(&fixture.FinancialRiskAssessment, &fixture.MonthlySummaryFacts); err != nil {
		t.Fatal(err)
	}
}

func TestC1AMonthEndBelowSafeBalanceProvenanceAvailability(t *testing.T) {
	entry := ProvenanceEmissionEntry{
		ReasonCode:        "monthEndBelowSafeBalance",
		OfflineScenarioID: monthEndBelowSafeFallbackScenario,
		SourceFactKeys:    []string{"estimatedMonthEndBalance", "safeBalance"},
	}
	if err := ValidateProvenanceEmissionPipeline(entry); err != nil {
		t.Fatal(err)
	}
}

func TestC1AAllProvenanceEmissionPipeline(t *testing.T) {
	for _, entry := range V1ProvenanceEmissionMatrix {
		if err := ValidateProvenanceEmissionPipeline(entry); err != nil {
			t.Fatalf("%s: %v", entry.ReasonCode, err)
		}
	}
}

func TestC1AProvenanceEmissionMatrixNegativePreflight(t *testing.T) {
	oldMatrix := V1ProvenanceEmissionMatrix
	t.Cleanup(func() { V1ProvenanceEmissionMatrix = oldMatrix })
	V1ProvenanceEmissionMatrix = V1ProvenanceEmissionMatrix[:6]

	plan, err := BuildFullRunPlan()
	if err != nil {
		t.Fatal(err)
	}
	status, err := RunFullOfflinePreflight(plan)
	if err != nil {
		t.Fatal(err)
	}
	if status.Passed {
		t.Fatal("expected 6/7 emission matrix to block full preflight")
	}
	if status.ProvenanceEmissionPassed != 6 || status.ProvenanceEmissionTotal != 6 {
		t.Fatalf("emission status=%+v", status)
	}
}

func TestC1AGoldenCoverageIncludesEmissionMatrix(t *testing.T) {
	summary, err := BuildGoldenCoverageSummary()
	if err != nil {
		t.Fatal(err)
	}
	if summary.ProvenanceEmissionPassed != 7 {
		t.Fatalf("provenanceEmissionPassed=%d", summary.ProvenanceEmissionPassed)
	}
	if !summary.ReadyForFullEval {
		t.Fatalf("readyForFullEval=false: %+v", summary)
	}
}

func TestC1AExistingGoldenClosureRegression(t *testing.T) {
	summary, err := BuildGoldenCoverageSummary()
	if err != nil {
		t.Fatal(err)
	}
	if summary.DatasetCases != 29 || summary.PlannedRuns != 37 {
		t.Fatalf("dataset=%d runs=%d", summary.DatasetCases, summary.PlannedRuns)
	}
	if summary.GoldenCoverage != 29 || summary.GoldenParityPassed != 29 {
		t.Fatalf("golden=%d parity=%d", summary.GoldenCoverage, summary.GoldenParityPassed)
	}
	if summary.ProvenancePassed != 29 || summary.DynamicSchemaPassed != 29 {
		t.Fatalf("provenance=%d schema=%d", summary.ProvenancePassed, summary.DynamicSchemaPassed)
	}
	if summary.LegacyFallbackCount != 0 {
		t.Fatalf("legacyFallback=%d", summary.LegacyFallbackCount)
	}
}

func TestC1AFullEvalPreflightBlocksOnIncompleteEmissionMatrix(t *testing.T) {
	oldMatrix := V1ProvenanceEmissionMatrix
	t.Cleanup(func() { V1ProvenanceEmissionMatrix = oldMatrix })
	V1ProvenanceEmissionMatrix = V1ProvenanceEmissionMatrix[:6]

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
		t.Fatal("expected full eval preflight failure for 6/7 emission matrix")
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
		t.Fatalf("runStatus=%s", report.RunStatus)
	}
}

func TestC1AValidateProvenanceEmissionMatrix(t *testing.T) {
	if err := ValidateProvenanceEmissionMatrix(); err != nil {
		t.Fatal(err)
	}
}

func TestC1AProductionEmittedStatusTable(t *testing.T) {
	for _, entry := range V1ProvenanceEmissionMatrix {
		assessment, facts, err := resolveProvenanceEmissionScenario(entry)
		if err != nil {
			t.Fatalf("%s: %v", entry.ReasonCode, err)
		}
		signal, ok := findSignalByReasonCode(assessment, entry.ReasonCode)
		if !ok {
			t.Fatalf("%s: productionEmitted=false", entry.ReasonCode)
		}
		if err := factpack.ValidateRiskSourceFactAvailability(&assessment, facts); err != nil {
			t.Fatalf("%s fact availability: %v", entry.ReasonCode, err)
		}
		if !signalSourceFactKeysMatch(signal, entry.SourceFactKeys) {
			t.Fatalf("%s sourceFactKeys=%v want %v", entry.ReasonCode, signal.SourceFactKeys, entry.SourceFactKeys)
		}
	}
}
