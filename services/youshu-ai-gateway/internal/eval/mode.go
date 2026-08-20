package eval

import (
	"os"
	"strings"
)

const (
	EvaluationVersionV2 = "v2-explanation-alignment"

	// EvaluationModeLegacyRiskDecision scores semantic quality using P0-4.4 warning-severity heuristics.
	EvaluationModeLegacyRiskDecision = "legacyRiskDecision"
	// EvaluationModeExplanationAlignmentV2 scores AI explanation fidelity against deterministic assessment fixtures.
	EvaluationModeExplanationAlignmentV2 = "explanationAlignmentV2"
)

// ResolveEvaluationMode returns the active evaluation mode from YOUSHU_EVAL_MODE.
// Default: explanationAlignmentV2 (P0-4.5.6+).
func ResolveEvaluationMode() string {
	mode := strings.TrimSpace(os.Getenv("YOUSHU_EVAL_MODE"))
	switch mode {
	case EvaluationModeLegacyRiskDecision, EvaluationModeExplanationAlignmentV2:
		return mode
	case "":
		return EvaluationModeExplanationAlignmentV2
	default:
		return EvaluationModeExplanationAlignmentV2
	}
}

func IsLegacyEvaluationMode(mode string) bool {
	return mode == EvaluationModeLegacyRiskDecision
}

func IsV2EvaluationMode(mode string) bool {
	return mode == EvaluationModeExplanationAlignmentV2
}
