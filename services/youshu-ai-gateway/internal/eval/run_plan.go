package eval

import (
	"fmt"
)

// Run plan types describe which evaluation subset is selected.
const (
	RunPlanTypeFull    = "full"
	RunPlanTypePilot   = "pilot"
	RunPlanTypeSmokeV2           = "smoke"
	RunPlanTypeConnectivityProbe = "connectivity-probe"
	RunPlanTypeE01Diagnostic     = "e01-diagnostic"
	RunPlanTypeC2CTargeted       = "c2c-targeted"
	RunPlanTypeCustom            = "custom"
)

const ConnectivityProbeCaseID = "A01_healthy_cashflow"

// Run execution status distinguishes blocked runs from semantic failures.
const (
	RunStatusExecuted             = "executed"
	RunStatusConfigurationBlocked = "configurationBlocked"
	RunStatusPreflightFailed      = "preflightFailed"
	RunStatusNotRequested         = "notRequested"
)

// SmokeV2RepeatCount is the canonical repeat policy for live smoke (6 × 2 = 12).
const SmokeV2RepeatCount = 2

// EvaluationRunPlan is the single source of truth for expected case/run counts.
type EvaluationRunPlan struct {
	Type              string   `json:"type"`
	EvaluationMode    string   `json:"evaluationMode"`
	SelectedCaseIDs   []string `json:"selectedCaseIDs"`
	RepeatCount       int      `json:"repeatCount,omitempty"`
	ExpectedCaseCount int      `json:"expectedCaseCount"`
	ExpectedRunCount  int      `json:"expectedRunCount"`
	ArtifactPrefix    string   `json:"artifactPrefix,omitempty"`
}

// BuildRunPlan resolves filter options into a run plan and filtered cases.
func BuildRunPlan(opts FilterOptions) (EvaluationRunPlan, []EvaluationCase, error) {
	cases, err := FilterCases(AllCases(), opts)
	if err != nil {
		return EvaluationRunPlan{}, nil, err
	}
	return runPlanFromCases(cases, opts), cases, nil
}

func runPlanFromCases(cases []EvaluationCase, opts FilterOptions) EvaluationRunPlan {
	ids := make([]string, len(cases))
	for i, c := range cases {
		ids[i] = c.ID
	}

	plan := EvaluationRunPlan{
		EvaluationMode:    ResolveEvaluationMode(),
		SelectedCaseIDs:   append([]string(nil), ids...),
		ExpectedCaseCount: len(cases),
		ExpectedRunCount:  CountRuns(cases),
	}

	switch {
	case opts.ConnectivityProbeMode:
		plan.Type = RunPlanTypeConnectivityProbe
		plan.RepeatCount = 1
		plan.ArtifactPrefix = "connectivity-probe"
	case opts.E01DiagnosticMode:
		plan.Type = RunPlanTypeE01Diagnostic
		plan.RepeatCount = 2
		plan.ArtifactPrefix = "e01-diagnostic-v2"
	case opts.C2CTargetedMode:
		plan.Type = RunPlanTypeC2CTargeted
		plan.RepeatCount = C2CTargetedRepeatCount
		plan.ArtifactPrefix = "c2c-keyfact-targeted"
	case opts.SmokeV2Mode:
		plan.Type = RunPlanTypeSmokeV2
		plan.RepeatCount = SmokeV2RepeatCount
		plan.ArtifactPrefix = "smoke-v2"
	case opts.PilotMode:
		plan.Type = RunPlanTypePilot
		plan.ArtifactPrefix = "pilot"
	case opts.CaseID != "" || opts.Category != "" || opts.RepeatOverride > 0:
		plan.Type = RunPlanTypeCustom
	default:
		plan.Type = RunPlanTypeFull
		plan.ArtifactPrefix = "full-v2"
	}
	return plan
}

// BuildFullRunPlan returns the canonical full v2 evaluation plan from dataset policy.
func BuildFullRunPlan() (EvaluationRunPlan, error) {
	cases := AllCases()
	return runPlanFromCases(cases, FilterOptions{}), nil
}

// ConnectivityProbeFilterOptions returns A01 × 1 live connectivity probe options.
func ConnectivityProbeFilterOptions() FilterOptions {
	return FilterOptions{
		ConnectivityProbeMode: true,
		CaseID:                ConnectivityProbeCaseID,
		RepeatOverride:        1,
	}
}
func BuildSmokeV2RunPlan() (EvaluationRunPlan, error) {
	cases, err := FilterCases(AllCases(), SmokeV2FilterOptions())
	if err != nil {
		return EvaluationRunPlan{}, err
	}
	plan := runPlanFromCases(cases, SmokeV2FilterOptions())
	if plan.ExpectedCaseCount != len(SmokeGoldenCaseIDs) {
		return EvaluationRunPlan{}, fmt.Errorf("smoke case count: got %d want %d", plan.ExpectedCaseCount, len(SmokeGoldenCaseIDs))
	}
	if plan.ExpectedRunCount != len(SmokeGoldenCaseIDs)*SmokeV2RepeatCount {
		return EvaluationRunPlan{}, fmt.Errorf("smoke run count: got %d want %d", plan.ExpectedRunCount, len(SmokeGoldenCaseIDs)*SmokeV2RepeatCount)
	}
	return plan, nil
}

// BuildPilotRunPlan returns the canonical pilot plan.
func BuildPilotRunPlan() (EvaluationRunPlan, error) {
	cases, err := FilterCases(AllCases(), PilotFilterOptions())
	if err != nil {
		return EvaluationRunPlan{}, err
	}
	return runPlanFromCases(cases, PilotFilterOptions()), nil
}

// ValidateRunPlanCompletion verifies an executed report matches the run plan.
func ValidateRunPlanCompletion(plan EvaluationRunPlan, report EvaluationReport) error {
	if report.Metadata.TotalCases != plan.ExpectedCaseCount {
		return fmt.Errorf("case count: got %d want %d", report.Metadata.TotalCases, plan.ExpectedCaseCount)
	}
	if report.Metadata.TotalRuns != plan.ExpectedRunCount {
		return fmt.Errorf("run count: got %d want %d", report.Metadata.TotalRuns, plan.ExpectedRunCount)
	}
	if len(report.Results) != plan.ExpectedRunCount {
		return fmt.Errorf("results: got %d want %d", len(report.Results), plan.ExpectedRunCount)
	}
	return nil
}

// SmokeCaseIDsMatchGolden verifies smoke plan case IDs equal SmokeGoldenCaseIDs exactly.
func SmokeCaseIDsMatchGolden(plan EvaluationRunPlan) bool {
	if len(plan.SelectedCaseIDs) != len(SmokeGoldenCaseIDs) {
		return false
	}
	for i, id := range SmokeGoldenCaseIDs {
		if plan.SelectedCaseIDs[i] != id {
			return false
		}
	}
	return true
}