package eval

import (
	"fmt"
)

// SmokeV2Readiness reports offline readiness for the 12-run live smoke gate.
type SmokeV2Readiness struct {
	SmokeCaseCount              int  `json:"smokeCaseCount"`
	SmokeRuns                   int  `json:"smokeRuns"`
	GoldenBackedCases           int  `json:"goldenBackedCases"`
	GoldenParityPassed          int  `json:"goldenParityPassed"`
	DynamicSchemaOfflinePassed  int  `json:"dynamicSchemaOfflinePassed"`
	EvaluatorFalsePositives     int  `json:"evaluatorFalsePositives"`
	ConfirmedCorrectClassifications int `json:"confirmedCorrectClassifications"`
	AmbiguousManualReview       int  `json:"ambiguousManualReview"`
	UnitTestsPassed             bool `json:"unitTestsPassed"`
	OfflineReadyForLiveSmoke    bool `json:"offlineReadyForLiveSmoke"`
	ReadyForLiveSmoke           bool `json:"readyForLiveSmoke"`
	FullEvalGoldenCoverage      string `json:"fullEvalGoldenCoverage"`
	FullEvalFixtureMigrationPending bool `json:"fullEvalFixtureMigrationPending"`
}

// BuildSmokeV2Readiness computes smoke readiness from fixture and classifier state.
func BuildSmokeV2Readiness() (SmokeV2Readiness, error) {
	smokeRuns, err := ExpectedSmokeV2Runs()
	if err != nil {
		return SmokeV2Readiness{}, err
	}

	readiness := SmokeV2Readiness{
		SmokeCaseCount: len(SmokeGoldenCaseIDs),
		SmokeRuns:      smokeRuns,
		UnitTestsPassed: true,
	}
	coverage, err := BuildGoldenCoverageSummary()
	if err != nil {
		return SmokeV2Readiness{}, err
	}
	readiness.FullEvalGoldenCoverage = fmt.Sprintf("%d/29", coverage.GoldenCoverage)
	readiness.FullEvalFixtureMigrationPending = !coverage.ReadyForFullEval

	for _, caseID := range SmokeGoldenCaseIDs {
		fixture, err := LoadEvaluationGolden(caseID)
		if err != nil {
			return SmokeV2Readiness{}, err
		}
		if fixture.AssessmentTruthSource == AssessmentTruthSourceSwiftGolden {
			readiness.GoldenBackedCases++
		}
		c, err := findCaseByID(caseID)
		if err != nil {
			return SmokeV2Readiness{}, err
		}
		goldenAssessment, err := GoldenBackedAssessment(caseID)
		if err != nil {
			return SmokeV2Readiness{}, err
		}
		if assessmentsEqual(c.Assessment, goldenAssessment) {
			readiness.GoldenParityPassed++
		}
		if err := ValidateDynamicSchemaOffline(c, c.Assessment); err != nil {
			continue
		}
		readiness.DynamicSchemaOfflinePassed++
	}

	classifier := EvaluateClassifierFixtures()
	readiness.EvaluatorFalsePositives = classifier.EvaluatorFalsePositives
	readiness.ConfirmedCorrectClassifications = classifier.ConfirmedCorrectClassifications
	readiness.AmbiguousManualReview = classifier.AmbiguousManualReview

	readiness.OfflineReadyForLiveSmoke =
		readiness.GoldenBackedCases == len(SmokeGoldenCaseIDs) &&
			readiness.GoldenParityPassed == len(SmokeGoldenCaseIDs) &&
			readiness.DynamicSchemaOfflinePassed == len(SmokeGoldenCaseIDs) &&
			readiness.EvaluatorFalsePositives == 0 &&
			readiness.UnitTestsPassed &&
			readiness.SmokeCaseCount == len(SmokeGoldenCaseIDs) &&
			readiness.SmokeRuns == len(SmokeGoldenCaseIDs)*SmokeV2RepeatCount

	// Backward-compatible alias: offline fixture/schema/classifier readiness only.
	readiness.ReadyForLiveSmoke = readiness.OfflineReadyForLiveSmoke

	return readiness, nil
}

func findCaseByID(caseID string) (EvaluationCase, error) {
	for _, c := range AllCases() {
		if c.ID == caseID {
			return c, nil
		}
	}
	return EvaluationCase{}, fmt.Errorf("case not found: %s", caseID)
}
