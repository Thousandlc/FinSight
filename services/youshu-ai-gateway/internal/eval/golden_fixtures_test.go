package eval_test

import (
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/eval"
)

func TestSmokeGoldenFixturesDecode(t *testing.T) {
	for _, caseID := range eval.SmokeGoldenCaseIDs {
		fixture, err := eval.LoadEvaluationGolden(caseID)
		if err != nil {
			t.Fatalf("load golden %s: %v", caseID, err)
		}
		if fixture.AssessmentTruthSource != eval.AssessmentTruthSourceSwiftGolden {
			t.Fatalf("unexpected truth source for %s: %s", caseID, fixture.AssessmentTruthSource)
		}
		if fixture.FinancialRiskAssessment.OverallLevel == "" {
			t.Fatalf("missing assessment for %s", caseID)
		}
	}
}

func TestSmokeCasesUseGoldenAssessments(t *testing.T) {
	for _, caseID := range eval.SmokeGoldenCaseIDs {
		golden, err := eval.GoldenBackedAssessment(caseID)
		if err != nil {
			t.Fatal(err)
		}
		c := findCase(t, caseID)
		if c.Assessment.OverallLevel != golden.OverallLevel {
			t.Fatalf("%s overallLevel mismatch", caseID)
		}
		if c.Assessment.DebtDataState != golden.DebtDataState {
			t.Fatalf("%s debtDataState mismatch", caseID)
		}
	}
}

func TestDynamicSchemaOfflineSmokeCases(t *testing.T) {
	for _, caseID := range eval.SmokeGoldenCaseIDs {
		c := findCase(t, caseID)
		if err := eval.ValidateDynamicSchemaOffline(c, c.Assessment); err != nil {
			t.Fatalf("%s dynamic schema offline failed: %v", caseID, err)
		}
	}
}

func TestEvaluatorFalsePositiveFixturesZero(t *testing.T) {
	result := eval.EvaluateClassifierFixtures()
	if result.EvaluatorFalsePositives != 0 {
		t.Fatalf("evaluator false positives=%d failures=%v", result.EvaluatorFalsePositives, result.Failures)
	}
	if result.ConfirmedCorrectClassifications == 0 {
		t.Fatal("expected classifier fixtures to run")
	}
}

func TestSmokeV2ReadinessReady(t *testing.T) {
	readiness, err := eval.BuildSmokeV2Readiness()
	if err != nil {
		t.Fatal(err)
	}
	if readiness.SmokeCaseCount != 6 || readiness.SmokeRuns != 12 {
		t.Fatalf("unexpected smoke sizing: %+v", readiness)
	}
	if readiness.GoldenBackedCases != 6 {
		t.Fatalf("expected 6 golden-backed cases, got %d", readiness.GoldenBackedCases)
	}
	if readiness.EvaluatorFalsePositives != 0 {
		t.Fatalf("evaluator false positives must be 0 before live smoke")
	}
	if !readiness.ReadyForLiveSmoke {
		t.Fatalf("expected readyForLiveSmoke=true, got %+v", readiness)
	}
	if !readiness.OfflineReadyForLiveSmoke {
		t.Fatal("expected offlineReadyForLiveSmoke=true")
	}
	if readiness.FullEvalFixtureMigrationPending {
		t.Fatal("full eval golden closure should be complete after C1")
	}
	if readiness.FullEvalGoldenCoverage != "29/29" {
		t.Fatalf("unexpected coverage: %s", readiness.FullEvalGoldenCoverage)
	}
}

func TestAssessmentMigrationTruthSourceSmokeCases(t *testing.T) {
	rows, err := eval.BuildAssessmentMigrationTable(eval.AllCases())
	if err != nil {
		t.Fatal(err)
	}
	smokeVerified := 0
	for _, row := range rows {
		for _, smokeID := range eval.SmokeGoldenCaseIDs {
			if row.CaseID != smokeID {
				continue
			}
			if row.AssessmentTruthSource != eval.AssessmentTruthSourceSwiftGolden {
				t.Fatalf("%s truth source=%s", row.CaseID, row.AssessmentTruthSource)
			}
			if !row.GoldenParityVerified {
				t.Fatalf("%s golden parity not verified", row.CaseID)
			}
			smokeVerified++
		}
	}
	if smokeVerified != 6 {
		t.Fatalf("expected 6 verified smoke rows, got %d", smokeVerified)
	}
}

func TestC03GoldenUsesDTISignalNotDebtPressure(t *testing.T) {
	assessment, err := eval.GoldenBackedAssessment("C03_high_monthly_payment")
	if err != nil {
		t.Fatal(err)
	}
	if len(assessment.Signals) != 1 || assessment.Signals[0].ReasonCode != "highDebtPaymentToIncome" {
		t.Fatalf("unexpected C03 signals: %+v", assessment.Signals)
	}
}

func TestB04GoldenUsesMinimumBalanceProvenance(t *testing.T) {
	assessment, err := eval.GoldenBackedAssessment("B04_short_term_negative_balance")
	if err != nil {
		t.Fatal(err)
	}
	if len(assessment.Signals) != 1 {
		t.Fatal("expected one B04 signal")
	}
	if assessment.Signals[0].ReasonCode != "negativeProjectedBalance" {
		t.Fatalf("unexpected reason: %s", assessment.Signals[0].ReasonCode)
	}
	if len(assessment.Signals[0].SourceFactKeys) != 1 || assessment.Signals[0].SourceFactKeys[0] != "minimumBalance" {
		t.Fatalf("unexpected provenance: %+v", assessment.Signals[0].SourceFactKeys)
	}
}
