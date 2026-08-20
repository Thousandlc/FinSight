package eval

import (
	"fmt"
	"strings"

	"github.com/youshu/youshu-ai-gateway/internal/config"
)

// CredentialPreflightStatus reports safe credential readiness (never exposes secrets).
type CredentialPreflightStatus struct {
	Configured           bool     `json:"configured"`
	APIKey               string   `json:"apiKey"` // "configured" | "missing"
	BaseURL              string   `json:"baseUrl"`
	Model                string   `json:"model"`
	UpstreamProvider     string   `json:"upstreamProvider"`
	StructuredOutputMode string   `json:"structuredOutputMode"`
	Missing              []string `json:"missing,omitempty"`
}

// SmokeOfflinePreflightStatus reports offline smoke gates before live HTTP.
type SmokeOfflinePreflightStatus struct {
	GoldenBackedCases          int  `json:"goldenBackedCases"`
	GoldenParityPassed         int  `json:"goldenParityPassed"`
	DynamicSchemaOfflinePassed int  `json:"dynamicSchemaOfflinePassed"`
	EvaluatorFalsePositives    int  `json:"evaluatorFalsePositives"`
	RunPlanCaseCount           int  `json:"runPlanCaseCount"`
	RunPlanRunCount            int  `json:"runPlanRunCount"`
	Passed                     bool `json:"passed"`
	BlockReason                string `json:"blockReason,omitempty"`
}

// FullOfflinePreflightStatus reports offline golden closure gates before full live evaluation.
type FullOfflinePreflightStatus struct {
	DatasetCases               int  `json:"datasetCases"`
	GoldenCoverage             int  `json:"goldenCoverage"`
	GoldenParityPassed         int  `json:"goldenParityPassed"`
	ProvenancePassed           int  `json:"provenancePassed"`
	ProvenanceEmissionPassed   int  `json:"provenanceEmissionPassed"`
	ProvenanceEmissionTotal    int  `json:"provenanceEmissionTotal"`
	DynamicSchemaPassed        int  `json:"dynamicSchemaPassed"`
	LegacyFallbackCount        int  `json:"legacyFallbackCount"`
	PlannedRuns                int  `json:"plannedRuns"`
	Passed                     bool `json:"passed"`
	BlockReason                string `json:"blockReason,omitempty"`
}

// LiveExecutionReadiness separates offline fixture readiness from live credential readiness.
type LiveExecutionReadiness struct {
	OfflineReadyForLiveSmoke bool `json:"offlineReadyForLiveSmoke"`
	LiveConfigurationReady   bool `json:"liveConfigurationReady"`
	ReadyForLiveExecution    bool `json:"readyForLiveExecution"`
}

// LivePreflightResult summarizes pre-HTTP checks for a live evaluation run.
type LivePreflightResult struct {
	Passed             bool                        `json:"passed"`
	RunStatus          string                      `json:"runStatus"`
	BlockReason        string                      `json:"blockReason,omitempty"`
	Credentials        CredentialPreflightStatus   `json:"credentials"`
	SmokeOffline       *SmokeOfflinePreflightStatus `json:"smokeOffline,omitempty"`
	FullOffline        *FullOfflinePreflightStatus  `json:"fullOffline,omitempty"`
	LiveReadiness      LiveExecutionReadiness      `json:"liveReadiness"`
}

// CheckLiveCredentials verifies required Bailian configuration without logging secrets.
func CheckLiveCredentials(cfg config.Config) CredentialPreflightStatus {
	status := CredentialPreflightStatus{
		APIKey:               credentialFieldStatus(cfg.BailianAPIKey),
		BaseURL:              displayOrMissing(cfg.BailianBaseURL),
		Model:                displayOrMissing(cfg.BailianModel),
		UpstreamProvider:     displayOrMissing(cfg.UpstreamAIProvider),
		StructuredOutputMode: displayOrMissing(cfg.BailianStructuredOutputMode),
	}

	var missing []string
	if strings.TrimSpace(cfg.UpstreamAIProvider) != config.UpstreamBailian {
		missing = append(missing, "UPSTREAM_AI_PROVIDER=bailian")
	}
	if cfg.BailianAPIKey == "" {
		missing = append(missing, "BAILIAN_API_KEY")
	}
	if cfg.BailianBaseURL == "" {
		missing = append(missing, "BAILIAN_BASE_URL")
	}
	if cfg.BailianModel == "" {
		missing = append(missing, "BAILIAN_MODEL")
	}
	mode := strings.TrimSpace(cfg.BailianStructuredOutputMode)
	if mode == "" {
		missing = append(missing, "BAILIAN_STRUCTURED_OUTPUT_MODE")
	} else if mode != config.StructuredOutputJSONSchemaStrict && mode != config.StructuredOutputJSONObject {
		missing = append(missing, "BAILIAN_STRUCTURED_OUTPUT_MODE")
	}

	status.Missing = missing
	status.Configured = len(missing) == 0
	return status
}

// RunSmokeOfflinePreflight verifies golden/schema/classifier/run-plan gates for smoke.
func RunSmokeOfflinePreflight(plan EvaluationRunPlan) (SmokeOfflinePreflightStatus, error) {
	status := SmokeOfflinePreflightStatus{
		RunPlanCaseCount: plan.ExpectedCaseCount,
		RunPlanRunCount:  plan.ExpectedRunCount,
	}

	if plan.Type != RunPlanTypeSmokeV2 {
		status.Passed = true
		return status, nil
	}

	if plan.ExpectedCaseCount != len(SmokeGoldenCaseIDs) || plan.ExpectedRunCount != len(SmokeGoldenCaseIDs)*SmokeV2RepeatCount {
		status.BlockReason = fmt.Sprintf("run plan must be 6 cases / 12 runs, got %d/%d", plan.ExpectedCaseCount, plan.ExpectedRunCount)
		return status, nil
	}
	if !SmokeCaseIDsMatchGolden(plan) {
		status.BlockReason = "smoke case IDs do not match SmokeGoldenCaseIDs"
		return status, nil
	}

	for _, caseID := range SmokeGoldenCaseIDs {
		fixture, err := LoadEvaluationGolden(caseID)
		if err != nil {
			return status, err
		}
		if fixture.AssessmentTruthSource != AssessmentTruthSourceSwiftGolden {
			status.BlockReason = fmt.Sprintf("%s assessmentTruthSource=%s (want swift-policy-golden)", caseID, fixture.AssessmentTruthSource)
			return status, nil
		}
		status.GoldenBackedCases++

		c, err := findCaseByID(caseID)
		if err != nil {
			return status, err
		}
		goldenAssessment, err := GoldenBackedAssessment(caseID)
		if err != nil {
			return status, err
		}
		if !assessmentsEqual(c.Assessment, goldenAssessment) {
			status.BlockReason = fmt.Sprintf("%s golden parity mismatch (possible legacy-go-fixture fallback)", caseID)
			return status, nil
		}
		status.GoldenParityPassed++

		if err := validateDynamicSchemaOfflineFn(c, c.Assessment); err != nil {
			status.BlockReason = fmt.Sprintf("%s dynamic schema offline failed: %v", caseID, err)
			return status, nil
		}
		status.DynamicSchemaOfflinePassed++
	}

	classifier := evaluateClassifierFixturesFn()
	status.EvaluatorFalsePositives = classifier.EvaluatorFalsePositives
	if classifier.EvaluatorFalsePositives > 0 {
		status.BlockReason = fmt.Sprintf("evaluator false positives=%d", classifier.EvaluatorFalsePositives)
		return status, nil
	}

	status.Passed = true
	return status, nil
}

// RunFullOfflinePreflight verifies 29/29 golden closure before full live evaluation.
func RunFullOfflinePreflight(plan EvaluationRunPlan) (FullOfflinePreflightStatus, error) {
	status := FullOfflinePreflightStatus{
		DatasetCases: plan.ExpectedCaseCount,
		PlannedRuns:  plan.ExpectedRunCount,
	}
	if plan.Type != RunPlanTypeFull {
		status.Passed = true
		return status, nil
	}
	if plan.ExpectedCaseCount != len(EvaluationGoldenCaseIDs) || plan.ExpectedRunCount != 37 {
		status.BlockReason = fmt.Sprintf("full run plan must be 29 cases / 37 runs, got %d/%d", plan.ExpectedCaseCount, plan.ExpectedRunCount)
		return status, nil
	}

	summary, err := BuildGoldenCoverageSummary()
	if err != nil {
		return status, err
	}
	status.GoldenCoverage = summary.GoldenCoverage
	status.GoldenParityPassed = summary.GoldenParityPassed
	status.ProvenancePassed = summary.ProvenancePassed
	status.DynamicSchemaPassed = summary.DynamicSchemaPassed
	status.LegacyFallbackCount = summary.LegacyFallbackCount
	status.PlannedRuns = summary.PlannedRuns
	emission, err := BuildProvenanceEmissionMatrixSummary()
	if err != nil {
		return status, err
	}
	status.ProvenanceEmissionPassed = emission.ProductionEmittedPassed
	status.ProvenanceEmissionTotal = emission.TotalReasons

	if summary.LegacyFallbackCount > 0 {
		status.BlockReason = fmt.Sprintf("legacy risk truth fallback count=%d (want 0)", summary.LegacyFallbackCount)
		return status, nil
	}
	if !summary.ReadyForFullEval {
		status.BlockReason = fmt.Sprintf(
			"golden closure incomplete: coverage=%d parity=%d provenance=%d schema=%d plannedRuns=%d",
			summary.GoldenCoverage, summary.GoldenParityPassed, summary.ProvenancePassed,
			summary.DynamicSchemaPassed, summary.PlannedRuns,
		)
		return status, nil
	}
	if !emission.Ready {
		status.BlockReason = fmt.Sprintf(
			"provenance emission matrix incomplete: productionEmitted=%d/%d factAvailability=%d/%d",
			emission.ProductionEmittedPassed, emission.TotalReasons,
			emission.FactAvailabilityPassed, emission.TotalReasons,
		)
		return status, nil
	}

	classifier := evaluateClassifierFixturesFn()
	if classifier.EvaluatorFalsePositives > 0 {
		status.BlockReason = fmt.Sprintf("evaluator false positives=%d", classifier.EvaluatorFalsePositives)
		return status, nil
	}

	status.Passed = true
	return status, nil
}

// BuildLiveExecutionReadiness combines offline smoke readiness with credential status.
func BuildLiveExecutionReadiness(cfg config.Config) (LiveExecutionReadiness, error) {
	offline, err := BuildSmokeV2Readiness()
	if err != nil {
		return LiveExecutionReadiness{}, err
	}
	cred := CheckLiveCredentials(cfg)
	return LiveExecutionReadiness{
		OfflineReadyForLiveSmoke: offline.OfflineReadyForLiveSmoke,
		LiveConfigurationReady:   cred.Configured,
		ReadyForLiveExecution:    offline.OfflineReadyForLiveSmoke && cred.Configured,
	}, nil
}

// RunLivePreflight performs all pre-HTTP checks for a live evaluation run.
func RunLivePreflight(cfg config.Config, plan EvaluationRunPlan) (LivePreflightResult, error) {
	result := LivePreflightResult{
		Credentials: CheckLiveCredentials(cfg),
	}

	gate := ResolveLiveRunGate(cfg, plan)
	if !gate.Eligible {
		result.RunStatus = gate.RunStatus
		result.BlockReason = gate.BlockReason
		return result, nil
	}

	readiness, err := BuildLiveExecutionReadiness(cfg)
	if err != nil {
		return result, err
	}
	result.LiveReadiness = readiness

	if plan.Type == RunPlanTypeSmokeV2 {
		smokeOffline, err := RunSmokeOfflinePreflight(plan)
		if err != nil {
			return result, err
		}
		result.SmokeOffline = &smokeOffline
		if !smokeOffline.Passed {
			result.RunStatus = RunStatusPreflightFailed
			result.BlockReason = smokeOffline.BlockReason
			return result, nil
		}
	}
	if plan.Type == RunPlanTypeFull {
		fullOffline, err := RunFullOfflinePreflight(plan)
		if err != nil {
			return result, err
		}
		result.FullOffline = &fullOffline
		if !fullOffline.Passed {
			result.RunStatus = RunStatusPreflightFailed
			result.BlockReason = fullOffline.BlockReason
			return result, nil
		}
	}

	result.Passed = true
	result.RunStatus = RunStatusExecuted
	return result, nil
}

// FormatRunSummary prints a non-sensitive pre-run summary for live smoke.
func FormatRunSummary(cfg config.Config, plan EvaluationRunPlan, preflight LivePreflightResult) string {
	var b strings.Builder
	b.WriteString("=== Live Evaluation Preflight Summary ===\n")
	b.WriteString(fmt.Sprintf("Evaluation: %s\n", EvaluationVersionV2))
	b.WriteString(fmt.Sprintf("Run type: %s\n", plan.Type))
	b.WriteString(fmt.Sprintf("Cases: %s\n", strings.Join(plan.SelectedCaseIDs, ",")))
	if plan.RepeatCount > 0 {
		b.WriteString(fmt.Sprintf("Repeats: %d\n", plan.RepeatCount))
	}
	b.WriteString(fmt.Sprintf("Expected runs: %d\n", plan.ExpectedRunCount))
	b.WriteString(fmt.Sprintf("Provider: %s\n", preflight.Credentials.UpstreamProvider))
	b.WriteString(fmt.Sprintf("Model: %s\n", preflight.Credentials.Model))
	b.WriteString(fmt.Sprintf("Structured output: %s\n", preflight.Credentials.StructuredOutputMode))
	if preflight.SmokeOffline != nil {
		b.WriteString(fmt.Sprintf("Golden: %d/%d\n", preflight.SmokeOffline.GoldenBackedCases, len(SmokeGoldenCaseIDs)))
		b.WriteString(fmt.Sprintf("Dynamic schema: %d/%d\n", preflight.SmokeOffline.DynamicSchemaOfflinePassed, len(SmokeGoldenCaseIDs)))
		b.WriteString(fmt.Sprintf("Evaluator FP: %d\n", preflight.SmokeOffline.EvaluatorFalsePositives))
	}
	if preflight.FullOffline != nil {
		b.WriteString(fmt.Sprintf("Golden coverage: %d/%d\n", preflight.FullOffline.GoldenCoverage, len(EvaluationGoldenCaseIDs)))
		b.WriteString(fmt.Sprintf("Golden parity: %d/%d\n", preflight.FullOffline.GoldenParityPassed, len(EvaluationGoldenCaseIDs)))
		b.WriteString(fmt.Sprintf("Provenance: %d/%d\n", preflight.FullOffline.ProvenancePassed, len(EvaluationGoldenCaseIDs)))
		b.WriteString(fmt.Sprintf("Provenance emission: %d/%d\n", preflight.FullOffline.ProvenanceEmissionPassed, preflight.FullOffline.ProvenanceEmissionTotal))
		b.WriteString(fmt.Sprintf("Dynamic schema: %d/%d\n", preflight.FullOffline.DynamicSchemaPassed, len(EvaluationGoldenCaseIDs)))
		b.WriteString(fmt.Sprintf("Legacy fallback: %d\n", preflight.FullOffline.LegacyFallbackCount))
	}
	b.WriteString(fmt.Sprintf("Credentials: %s\n", credentialFieldStatus(cfg.BailianAPIKey)))
	b.WriteString(fmt.Sprintf("runStatus: %s\n", preflight.RunStatus))
	if preflight.BlockReason != "" {
		b.WriteString(fmt.Sprintf("blockReason: %s\n", preflight.BlockReason))
	}
	return b.String()
}

func credentialFieldStatus(value string) string {
	if strings.TrimSpace(value) == "" {
		return "missing"
	}
	return "configured"
}

func displayOrMissing(value string) string {
	if strings.TrimSpace(value) == "" {
		return "missing"
	}
	return value
}

// Test hooks for offline preflight failure paths (overridden in tests only).
var (
	evaluateClassifierFixturesFn  = EvaluateClassifierFixtures
	validateDynamicSchemaOfflineFn = ValidateDynamicSchemaOffline
)
