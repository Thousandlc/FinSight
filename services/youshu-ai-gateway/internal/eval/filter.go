package eval

import (
	"fmt"
	"os"
	"strconv"
	"strings"
)

// FilterOptions controls which cases run and repeat count.
type FilterOptions struct {
	CaseID         string
	Category       string
	RepeatOverride int
	PilotMode      bool
	PilotCaseIDs   []string
	SmokeV2Mode           bool
	SmokeV2CaseIDs        []string
	ConnectivityProbeMode bool
	E01DiagnosticMode     bool
	C2CTargetedMode       bool
	C2CTargetedCaseIDs    []string
}

// LoadFilterOptions reads filter env vars.
func LoadFilterOptions() FilterOptions {
	opts := FilterOptions{
		CaseID:   strings.TrimSpace(os.Getenv("YOUSHU_EVAL_CASE")),
		Category: strings.TrimSpace(os.Getenv("YOUSHU_EVAL_CATEGORY")),
	}
	if v := strings.TrimSpace(os.Getenv("YOUSHU_EVAL_REPEAT")); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			opts.RepeatOverride = n
		}
	}
	if v := strings.TrimSpace(os.Getenv("YOUSHU_EVAL_CONNECTIVITY_PROBE")); v == "1" || strings.EqualFold(v, "true") {
		opts.ConnectivityProbeMode = true
		opts.CaseID = ConnectivityProbeCaseID
		opts.RepeatOverride = 1
	} else if v := strings.TrimSpace(os.Getenv("YOUSHU_EVAL_E01_DIAGNOSTIC")); v == "1" || strings.EqualFold(v, "true") {
		opts.E01DiagnosticMode = true
		opts.CaseID = E01DiagnosticCaseID
		opts.RepeatOverride = 2
	} else if v := strings.TrimSpace(os.Getenv("YOUSHU_EVAL_C2C_TARGETED")); v == "1" || strings.EqualFold(v, "true") {
		opts.C2CTargetedMode = true
		opts.C2CTargetedCaseIDs = C2CTargetedCaseIDs()
		opts.RepeatOverride = C2CTargetedRepeatCount
	} else if v := strings.TrimSpace(os.Getenv("YOUSHU_EVAL_CASES")); v != "" {
		parts := strings.Split(v, ",")
		if len(parts) == 1 {
			opts.CaseID = strings.TrimSpace(parts[0])
		}
	} else if v := strings.TrimSpace(os.Getenv("YOUSHU_EVAL_SMOKE_V2")); v == "1" || strings.EqualFold(v, "true") {
		opts.SmokeV2Mode = true
		opts.SmokeV2CaseIDs = SmokeGoldenCaseIDs
		opts.RepeatOverride = SmokeV2RepeatCount
	} else if v := strings.TrimSpace(os.Getenv("YOUSHU_EVAL_PILOT")); v == "1" || strings.EqualFold(v, "true") {
		opts.PilotMode = true
		opts.PilotCaseIDs = defaultPilotCaseIDs()
	}
	return opts
}

func defaultPilotCaseIDs() []string {
	return []string{
		"A01_healthy_cashflow",
		"B01_minimum_below_safe",
		"C03_high_monthly_payment",
		"D02_zero_income_month",
		"E01_partial_debt_data",
		"E05_missing_debt_data",
		"F06_no_warning_expected",
	}
}

// SmokeV2FilterOptions returns filter options for v2 smoke subset.
func SmokeV2FilterOptions() FilterOptions {
	return FilterOptions{
		SmokeV2Mode:    true,
		SmokeV2CaseIDs: SmokeGoldenCaseIDs,
		RepeatOverride: SmokeV2RepeatCount,
	}
}

// ExpectedSmokeV2Runs returns 12 runs for the v2 smoke subset definition.
func ExpectedSmokeV2Runs() (int, error) {
	cases, err := FilterCases(AllCases(), SmokeV2FilterOptions())
	if err != nil {
		return 0, err
	}
	return CountRuns(cases), nil
}

// FilterCases applies env-based filtering and repeat overrides.
func FilterCases(cases []EvaluationCase, opts FilterOptions) ([]EvaluationCase, error) {
	if opts.SmokeV2Mode {
		return filterSmokeCases(cases, opts)
	}
	if opts.C2CTargetedMode {
		return filterOrderedCases(cases, opts.C2CTargetedCaseIDs, opts.RepeatOverride)
	}
	var filtered []EvaluationCase
	for _, c := range cases {
		if opts.SmokeV2Mode && !contains(opts.SmokeV2CaseIDs, c.ID) {
			continue
		}
		if opts.PilotMode && !contains(opts.PilotCaseIDs, c.ID) {
			continue
		}
		if opts.CaseID != "" && c.ID != opts.CaseID {
			continue
		}
		if opts.Category != "" && c.Category != opts.Category {
			continue
		}
		copy := c
		if opts.RepeatOverride > 0 {
			copy.Repeats = opts.RepeatOverride
		}
		filtered = append(filtered, copy)
	}
	if len(filtered) == 0 {
		return nil, fmt.Errorf("no cases matched filter case=%q category=%q pilot=%t", opts.CaseID, opts.Category, opts.PilotMode)
	}
	return filtered, nil
}

func filterOrderedCases(cases []EvaluationCase, caseIDs []string, repeatOverride int) ([]EvaluationCase, error) {
	byID := map[string]EvaluationCase{}
	for _, c := range cases {
		byID[c.ID] = c
	}
	var filtered []EvaluationCase
	for _, id := range caseIDs {
		c, ok := byID[id]
		if !ok {
			return nil, fmt.Errorf("case %q not found in dataset", id)
		}
		copy := c
		if repeatOverride > 0 {
			copy.Repeats = repeatOverride
		}
		filtered = append(filtered, copy)
	}
	if len(filtered) == 0 {
		return nil, fmt.Errorf("no cases matched ordered filter")
	}
	return filtered, nil
}

func filterSmokeCases(cases []EvaluationCase, opts FilterOptions) ([]EvaluationCase, error) {
	byID := map[string]EvaluationCase{}
	for _, c := range cases {
		byID[c.ID] = c
	}
	caseIDs := opts.SmokeV2CaseIDs
	if len(caseIDs) == 0 {
		caseIDs = SmokeGoldenCaseIDs
	}
	var filtered []EvaluationCase
	for _, id := range caseIDs {
		c, ok := byID[id]
		if !ok {
			continue
		}
		copy := c
		if opts.RepeatOverride > 0 {
			copy.Repeats = opts.RepeatOverride
		}
		filtered = append(filtered, copy)
	}
	if len(filtered) == 0 {
		return nil, fmt.Errorf("no smoke cases matched filter case=%q", opts.CaseID)
	}
	return filtered, nil
}

func contains(items []string, target string) bool {
	for _, item := range items {
		if item == target {
			return true
		}
	}
	return false
}

// ExpandRuns expands cases into individual run entries.
func ExpandRuns(cases []EvaluationCase) []runPlan {
	var plans []runPlan
	for _, c := range cases {
		for i := 1; i <= c.Repeats; i++ {
			plans = append(plans, runPlan{Case: c, RunIndex: i})
		}
	}
	return plans
}

// CountRuns returns total expanded runs for the given cases.
func CountRuns(cases []EvaluationCase) int {
	return len(ExpandRuns(cases))
}

// PilotFilterOptions returns filter options for the default pilot subset.
func PilotFilterOptions() FilterOptions {
	return FilterOptions{
		PilotMode:    true,
		PilotCaseIDs: defaultPilotCaseIDs(),
	}
}

// ExpectedPilotRuns computes pilot total runs from case selection and repeat policy.
func ExpectedPilotRuns() (int, error) {
	cases, err := FilterCases(AllCases(), PilotFilterOptions())
	if err != nil {
		return 0, err
	}
	return CountRuns(cases), nil
}

type runPlan struct {
	Case     EvaluationCase
	RunIndex int
}
