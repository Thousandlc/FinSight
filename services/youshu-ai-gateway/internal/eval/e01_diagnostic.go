package eval

import (
	"sort"
	"strings"

	"github.com/youshu/youshu-ai-gateway/internal/provider"
)

const (
	E01DiagnosticCaseID = "E01_partial_debt_data"

	E01FailureSignalOmission     = "signalOmission"
	E01FailureWrongReason        = "wrongReason"
	E01FailureDuplicateReason    = "duplicateReason"
	E01FailureCitationMissing    = "citationMissing"
	E01FailureCitationUnsupported = "citationUnsupported"
	E01FailureUnexpectedUnknown  = "unexpectedUnknown"
	E01FailureOther              = "other"
)

// E01StructuredFailureAnalysis classifies E01 explanation contract failures.
type E01StructuredFailureAnalysis struct {
	FailureType              string `json:"failureType"`
	AlignmentFailureCode       string `json:"alignmentFailureCode,omitempty"`
	ExpectedRiskReasons        []string `json:"expectedRiskReasons,omitempty"`
	ActualRiskReasons          []string `json:"actualRiskReasons,omitempty"`
	ExpectedUnknownReasons     []string `json:"expectedUnknownReasons,omitempty"`
	ActualUnknownReasons       []string `json:"actualUnknownReasons,omitempty"`
	ExplanationAlignmentPass   bool   `json:"explanationAlignmentPass"`
	ConfirmedModelFailure      bool   `json:"confirmedModelFailure"`
}

// E01PostArchitectureReadiness summarizes full post-B5E E01 pipeline readiness.
type E01PostArchitectureReadiness struct {
	Verdict                    string `json:"verdict"`
	HTTP2xxSuccessCount        int    `json:"http2xxSuccessCount"`
	AssessedSampleCount        int    `json:"assessedSampleCount"`
	ReasonAlignmentPassCount   int    `json:"reasonAlignmentPassCount"`
	ProvenanceAssemblyPassCount int   `json:"provenanceAssemblyPassCount"`
	EndToEndPassCount          int    `json:"endToEndPassCount"`
	PreProviderBlockedCount    int    `json:"preProviderBlockedCount"`
	NextStep                   string `json:"nextStep,omitempty"`
}

// E01TargetedDiagnosticReadiness summarizes a 2-run E01 targeted diagnostic batch.
type E01TargetedDiagnosticReadiness struct {
	Verdict                 string `json:"verdict"`
	HTTP2xxSuccessCount     int    `json:"http2xxSuccessCount"`
	ExplanationPassCount    int    `json:"explanationPassCount"`
	StableFailurePattern    bool   `json:"stableFailurePattern"`
	ConfirmedModelFailures  int    `json:"confirmedModelFailures"`
	SignalOmissionCount     int    `json:"signalOmissionCount"`
	WrongReasonCount        int    `json:"wrongReasonCount"`
	DuplicateReasonCount    int    `json:"duplicateReasonCount"`
	CitationFailureCount    int    `json:"citationFailureCount"`
	UnexpectedUnknownCount  int    `json:"unexpectedUnknownCount"`
	RecommendedPromptTarget string `json:"recommendedPromptTarget,omitempty"`
	NextStep                string `json:"nextStep,omitempty"`
}

// E01TargetedDiagnosticFilterOptions returns E01 × 2 targeted live diagnostic options.
func E01TargetedDiagnosticFilterOptions() FilterOptions {
	return FilterOptions{
		E01DiagnosticMode: true,
		CaseID:            E01DiagnosticCaseID,
		RepeatOverride:    2,
	}
}

// ClassifyE01StructuredFailure maps snapshot + alignment code to failure taxonomy.
func ClassifyE01StructuredFailure(snap EvaluationDiagnosticSnapshot, explanationPass bool) E01StructuredFailureAnalysis {
	analysis := E01StructuredFailureAnalysis{
		FailureType:            E01FailureOther,
		AlignmentFailureCode:   snap.AlignmentFailureCode,
		ExpectedRiskReasons:    cloneStringSlice(snap.ExpectedRiskReasons),
		ActualRiskReasons:      cloneStringSlice(snap.ActualRiskExplanationReasons),
		ExpectedUnknownReasons: cloneStringSlice(snap.ExpectedUnknownReasons),
		ActualUnknownReasons:   cloneStringSlice(snap.ActualUnknownExplanationReasons),
		ExplanationAlignmentPass: explanationPass,
	}
	if explanationPass {
		return analysis
	}
	analysis.ConfirmedModelFailure = true

	if len(snap.ExpectedUnknownReasons) == 0 && len(snap.ActualUnknownExplanationReasons) > 0 {
		analysis.FailureType = E01FailureUnexpectedUnknown
		return analysis
	}

	code := snap.AlignmentFailureCode
	switch code {
	case "duplicate riskExplanation reasonCode", "duplicateRiskExplanation":
		analysis.FailureType = E01FailureDuplicateReason
		return analysis
	case "duplicate riskExplanation citedFactKey":
		analysis.FailureType = E01FailureDuplicateReason
		return analysis
	case "riskExplanation missingPrimarySource":
		analysis.FailureType = E01FailureCitationMissing
		return analysis
	case "riskExplanation citedFactKeyNotInSignalSources", "unregistered riskExplanation citedFactKey":
		analysis.FailureType = E01FailureCitationUnsupported
		return analysis
	case "riskExplanationReasonNotInAssessment", "unsupportedRiskExplanation":
		analysis.FailureType = E01FailureWrongReason
		return analysis
	case "unknownExplanationCoverageMismatch", "unsupportedUnknownExplanation":
		analysis.FailureType = E01FailureUnexpectedUnknown
		return analysis
	}

	if len(snap.ActualRiskExplanationReasons) == 0 && len(snap.ExpectedRiskReasons) > 0 {
		analysis.FailureType = E01FailureSignalOmission
		return analysis
	}
	if hasWrongReason(snap.ExpectedRiskReasons, snap.ActualRiskExplanationReasons) {
		analysis.FailureType = E01FailureWrongReason
		return analysis
	}
	if hasDuplicateReason(snap.RiskExplanations) {
		analysis.FailureType = E01FailureDuplicateReason
		return analysis
	}
	if code == "riskExplanationCoverageMismatch" {
		if len(snap.ActualRiskExplanationReasons) == 0 {
			analysis.FailureType = E01FailureSignalOmission
		} else {
			analysis.FailureType = E01FailureWrongReason
		}
		return analysis
	}
	if strings.Contains(code, "missingPrimarySource") {
		analysis.FailureType = E01FailureCitationMissing
		return analysis
	}
	if strings.Contains(code, "citedFactKey") {
		analysis.FailureType = E01FailureCitationUnsupported
		return analysis
	}
	return analysis
}

func hasWrongReason(expected, actual []string) bool {
	if len(actual) == 0 {
		return false
	}
	expectedSet := map[string]struct{}{}
	for _, item := range expected {
		expectedSet[item] = struct{}{}
	}
	for _, item := range actual {
		if _, ok := expectedSet[item]; !ok {
			return true
		}
	}
	sort.Strings(expected)
	sort.Strings(actual)
	return !equalStringSlices(expected, actual)
}

func hasDuplicateReason(items []EvalRiskExplanationSnapshot) bool {
	seen := map[string]int{}
	for _, item := range items {
		code := strings.TrimSpace(item.ReasonCode)
		if code == "" {
			continue
		}
		seen[code]++
		if seen[code] > 1 {
			return true
		}
	}
	return false
}

func equalStringSlices(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

// DeriveE01TargetedDiagnosticReadiness computes targeted diagnostic verdict (not smoke).
func DeriveE01TargetedDiagnosticReadiness(results []RunResult) E01TargetedDiagnosticReadiness {
	readiness := E01TargetedDiagnosticReadiness{}
	if len(results) == 0 {
		readiness.Verdict = ReadinessNotAssessed
		return readiness
	}

	var failureTypes []string
	for _, r := range results {
		if r.CaseID != E01DiagnosticCaseID {
			continue
		}
		if r.Transport.HTTP2xxSuccess || r.ContractStages.HTTP2xxSuccess {
			readiness.HTTP2xxSuccessCount++
		}
		if r.ContractStages.ExplanationAlignment == provider.StagePass || r.ExplanationAlignmentPass {
			readiness.ExplanationPassCount++
			continue
		}
		analysis := ClassifyE01StructuredFailure(r.DiagnosticSnapshot, false)
		readiness.ConfirmedModelFailures++
		failureTypes = append(failureTypes, analysis.FailureType)
		switch analysis.FailureType {
		case E01FailureSignalOmission:
			readiness.SignalOmissionCount++
		case E01FailureWrongReason:
			readiness.WrongReasonCount++
		case E01FailureDuplicateReason:
			readiness.DuplicateReasonCount++
		case E01FailureCitationMissing, E01FailureCitationUnsupported:
			readiness.CitationFailureCount++
		case E01FailureUnexpectedUnknown:
			readiness.UnexpectedUnknownCount++
		}
	}

	switch {
	case readiness.HTTP2xxSuccessCount == 0:
		readiness.Verdict = ReadinessFail
		readiness.NextStep = "fix transport/infrastructure before E01 semantic diagnosis"
	case readiness.ExplanationPassCount == len(results):
		readiness.Verdict = ReadinessPass
		readiness.NextStep = "P0-4.5.6B6 full 12-run smoke with repaired diagnostics"
	case readiness.ExplanationPassCount > 0:
		readiness.Verdict = ReadinessFail
		readiness.StableFailurePattern = false
		readiness.NextStep = "E01 unstable; targeted Prompt iteration before full smoke"
	default:
		readiness.Verdict = ReadinessFail
		readiness.StableFailurePattern = len(failureTypes) >= 2 && failureTypes[0] == failureTypes[1]
		readiness.NextStep = "P0-4.5.6B5C targeted Prompt iteration"
	}

	readiness.RecommendedPromptTarget = recommendE01PromptTarget(readiness)
	return readiness
}

// DeriveE01PostArchitectureReadiness evaluates the full post-B5E E01 pipeline gate.
func DeriveE01PostArchitectureReadiness(results []RunResult) E01PostArchitectureReadiness {
	readiness := E01PostArchitectureReadiness{}
	if len(results) == 0 {
		readiness.Verdict = ReadinessNotAssessed
		return readiness
	}

	for _, r := range results {
		if r.CaseID != E01DiagnosticCaseID {
			continue
		}
		if r.ContractStages.RiskSourceFactAvailability == provider.StageFail {
			readiness.PreProviderBlockedCount++
			continue
		}
		if r.Transport.HTTP2xxSuccess || r.ContractStages.HTTP2xxSuccess {
			readiness.HTTP2xxSuccessCount++
			readiness.AssessedSampleCount++
		}
		if r.ExplanationAlignmentPass {
			readiness.ReasonAlignmentPassCount++
		}
		if r.ProvenanceAssemblyPass {
			readiness.ProvenanceAssemblyPassCount++
		}
		if r.EndToEndPass {
			readiness.EndToEndPassCount++
		}
	}

	requiredSamples := len(results)
	switch {
	case readiness.AssessedSampleCount < requiredSamples:
		readiness.Verdict = ReadinessFail
		readiness.NextStep = "obtain at least 2 HTTP-success E01 assessed samples before B6"
	case readiness.EndToEndPassCount == requiredSamples:
		readiness.Verdict = ReadinessPass
		readiness.NextStep = "P0-4.5.6B6 full 12-run smoke"
	default:
		readiness.Verdict = ReadinessFail
		readiness.NextStep = "fix application pipeline blockers before B6"
	}
	return readiness
}

func recommendE01PromptTarget(readiness E01TargetedDiagnosticReadiness) string {
	switch {
	case readiness.ExplanationPassCount >= 2:
		return ""
	case readiness.SignalOmissionCount > 0:
		return "coverage"
	case readiness.CitationFailureCount > 0:
		return "citation"
	case readiness.WrongReasonCount > 0:
		return "exact-reasonCode"
	case readiness.DuplicateReasonCount > 0:
		return "exactly-once"
	case readiness.UnexpectedUnknownCount > 0:
		return "unknown-discipline"
	default:
		return "other"
	}
}
