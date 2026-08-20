package eval

import "github.com/youshu/youshu-ai-gateway/internal/contract"

// Risk mismatch direction constants for semantic audit.
const (
	RiskMismatchNone              = ""
	RiskMismatchOverclassified    = "overclassified"
	RiskMismatchUnderclassified   = "underclassified"
	RiskMismatchUnexpectedWarning = "unexpectedWarning"
	RiskMismatchMissingWarning    = "missingWarning"
)

// DeriveActualRisk maps warning severities to an evaluation risk level.
// Algorithm:
//   - warningCount == 0 → RiskLevelNone
//   - max severity across warnings:
//     safe → RiskLevelSafe
//     warning → RiskLevelWarning
//     risk → RiskLevelRisk
func DeriveActualRisk(warnings []contract.Warning) RiskLevel {
	if len(warnings) == 0 {
		return RiskLevelNone
	}
	max := MaxWarningSeverity(warnings)
	switch max {
	case "safe":
		return RiskLevelSafe
	case "warning":
		return RiskLevelWarning
	case "risk":
		return RiskLevelRisk
	default:
		return RiskLevelNone
	}
}

// MaxWarningSeverity returns the highest severity rank among warnings.
// Rank: ""=0, safe=1, warning=2, risk=3. Multiple warnings use MAX aggregation.
func MaxWarningSeverity(warnings []contract.Warning) string {
	rank := map[string]int{"": 0, "safe": 1, "warning": 2, "risk": 3}
	max := ""
	for _, w := range warnings {
		if rank[w.Severity] > rank[max] {
			max = w.Severity
		}
	}
	return max
}

// CheckRiskLevelMatch is the production risk checker rule used by CheckExpectations.
func CheckRiskLevelMatch(expected RiskLevel, warnings []contract.Warning) bool {
	if expected == "" {
		return true
	}
	maxSeverity := MaxWarningSeverity(warnings)
	switch expected {
	case RiskLevelNone, RiskLevelSafe:
		return maxSeverity == "" || maxSeverity == "safe"
	case RiskLevelWarning:
		return maxSeverity == "warning" || maxSeverity == "risk"
	case RiskLevelRisk:
		return maxSeverity == "risk"
	default:
		return true
	}
}

// DiagnoseRiskMismatch compares expected vs warnings and returns match + direction.
func DiagnoseRiskMismatch(expected RiskLevel, warnings []contract.Warning) (matched bool, direction string) {
	if CheckRiskLevelMatch(expected, warnings) {
		return true, RiskMismatchNone
	}
	actual := DeriveActualRisk(warnings)
	return false, classifyRiskMismatchDirection(expected, actual, MaxWarningSeverity(warnings))
}

func classifyRiskMismatchDirection(expected, actual RiskLevel, maxSeverity string) string {
	expRank := riskLevelRank(expected)
	actRank := riskLevelRank(actual)

	if expected == RiskLevelNone && (maxSeverity == "warning" || maxSeverity == "risk") {
		return RiskMismatchUnexpectedWarning
	}
	if actRank > expRank {
		return RiskMismatchOverclassified
	}
	if actRank < expRank || (expected == RiskLevelWarning && maxSeverity == "") {
		return RiskMismatchMissingWarning
	}
	return RiskMismatchUnderclassified
}

func riskLevelRank(level RiskLevel) int {
	switch level {
	case RiskLevelNone:
		return 0
	case RiskLevelSafe:
		return 1
	case RiskLevelWarning:
		return 2
	case RiskLevelRisk:
		return 3
	default:
		return 0
	}
}

// RiskAudit captures per-run risk evaluation diagnostics.
type RiskAudit struct {
	ExpectedRiskLevel RiskLevel `json:"expectedRiskLevel"`
	ActualDerivedRisk RiskLevel `json:"actualDerivedRisk"`
	MaxSeverity       string    `json:"maxSeverity"`
	WarningCount      int       `json:"warningCount"`
	Matched           bool      `json:"matched"`
	MismatchDirection string    `json:"riskMismatchDirection,omitempty"`
}

// BuildRiskAudit constructs risk audit from case expectation and draft warnings.
func BuildRiskAudit(expected RiskLevel, warnings []contract.Warning) RiskAudit {
	actual := DeriveActualRisk(warnings)
	matched, direction := DiagnoseRiskMismatch(expected, warnings)
	return RiskAudit{
		ExpectedRiskLevel: expected,
		ActualDerivedRisk: actual,
		MaxSeverity:       MaxWarningSeverity(warnings),
		WarningCount:      len(warnings),
		Matched:           matched,
		MismatchDirection: direction,
	}
}
