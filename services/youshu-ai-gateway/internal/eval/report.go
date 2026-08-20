package eval

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"github.com/youshu/youshu-ai-gateway/internal/config"
)

const (
	DefaultOutputDir = ".eval-output"
	LatestReportFile = "latest.json"
)

// RunMetadata describes an evaluation run.
type RunMetadata struct {
	StartedAt            string `json:"startedAt"`
	FinishedAt           string `json:"finishedAt"`
	PilotMode            bool   `json:"pilotMode"`
	SmokeV2Mode          bool   `json:"smokeV2Mode,omitempty"`
	E01DiagnosticMode    bool   `json:"e01DiagnosticMode,omitempty"`
	C2CTargetedMode      bool   `json:"c2cTargetedMode,omitempty"`
	ConnectivityProbeMode bool  `json:"connectivityProbeMode,omitempty"`
	PilotNote            string `json:"pilotNote,omitempty"`
	ContractIdentity     FrozenContractIdentity `json:"contractIdentity,omitempty"`
	C2CPlannedRuns       int    `json:"c2cPlannedRuns,omitempty"`
	C2CActualAttempts    int    `json:"c2cActualAttempts,omitempty"`
	C2CAssessedSamples   int    `json:"c2cAssessedSamples,omitempty"`
	ConfiguredModel      string `json:"configuredModel"`
	UpstreamModel        string `json:"upstreamModel"`
	GatewayModelAlias    string `json:"gatewayModelAlias"`
	StructuredOutputMode string `json:"structuredOutputMode"`
	TotalCases           int    `json:"totalCases"`
	TotalRuns            int    `json:"totalRuns"`
	CaseFilter           string `json:"caseFilter,omitempty"`
	CategoryFilter       string `json:"categoryFilter,omitempty"`
	RepeatOverride       int    `json:"repeatOverride,omitempty"`
}

// EvaluationReport is the serializable evaluation output.
type EvaluationReport struct {
	EvaluationVersion string `json:"evaluationVersion"`
	EvaluationMode    string `json:"evaluationMode"`
	EvaluatorVersion     string `json:"evaluatorVersion,omitempty"`
	EvaluatorFingerprint string `json:"evaluatorFingerprint,omitempty"`

	Metadata RunMetadata      `json:"metadata"`
	Metrics  AggregateMetrics `json:"metrics"`
	Analysis FullEvalAnalysis `json:"analysis,omitempty"`

	LegacyBaseline     LegacyBaseline      `json:"legacyBaseline,omitempty"`
	ContractMetrics    ContractMetrics     `json:"contractMetrics,omitempty"`
	ExplanationMetrics ExplanationMetrics  `json:"explanationMetrics,omitempty"`
	PolicyMetrics      PolicyMetrics       `json:"policyMetrics,omitempty"`
	FactSafetyMetrics  FactSafetyMetrics   `json:"factSafetyMetrics,omitempty"`
	NarrativeMetrics   NarrativeMetrics    `json:"narrativeMetrics,omitempty"`
	LatencyMetrics     LatencyMetrics      `json:"latencyMetrics,omitempty"`
	TokenMetrics       TokenMetrics        `json:"tokenMetrics,omitempty"`
	AdjudicationMetrics AdjudicationMetrics `json:"adjudicationMetrics,omitempty"`
	ModelVerdict       ReadinessVerdicts   `json:"modelVerdict,omitempty"`
	SmokeReadiness     SmokeReadinessVerdicts `json:"smokeReadiness,omitempty"`
	E01TargetedReadiness E01TargetedDiagnosticReadiness `json:"e01TargetedDiagnosticReadiness,omitempty"`
	E01PostArchitectureReadiness E01PostArchitectureReadiness `json:"e01PostArchitectureReadiness,omitempty"`
	C2CTargetedReadiness         C2CTargetedReadiness         `json:"c2cTargetedReadiness,omitempty"`
	AssessmentMigration []AssessmentMigrationRow `json:"assessmentMigration,omitempty"`
	SmokeV2Readiness    SmokeV2Readiness         `json:"smokeV2Readiness,omitempty"`
	RunPlan             EvaluationRunPlan        `json:"runPlan,omitempty"`
	RunStatus           string                   `json:"runStatus,omitempty"`
	PreflightSummary    string                   `json:"preflightSummary,omitempty"`

	Results []RunResult `json:"results"`
	Summary string      `json:"summaryText"`
}

// BuildReport assembles the full evaluation report.
func BuildReport(
	meta RunMetadata,
	results []RunResult,
	metrics AggregateMetrics,
	mode string,
) EvaluationReport {
	analysis := AnalyzeFullEvaluation(results, AllCases(), metrics, mode)
	legacy, contract, explanation, policy, factSafety, narrative, latency, tokens, adjudication :=
		BuildV2MetricSections(metrics, analysis)
	migration, _ := BuildAssessmentMigrationTable(AllCases())
	smokeReadiness, _ := BuildSmokeV2Readiness()

	report := EvaluationReport{
		EvaluationVersion: EvaluationVersionV2,
		EvaluationMode:    mode,
		EvaluatorVersion:     CurrentEvaluatorIdentity().EvaluatorVersion,
		EvaluatorFingerprint: CurrentEvaluatorIdentity().EvaluatorFingerprint,
		Metadata:          meta,
		Metrics:           metrics,
		Analysis:          analysis,
		LegacyBaseline:    legacy,
		ContractMetrics:   contract,
		ExplanationMetrics: explanation,
		PolicyMetrics:     policy,
		FactSafetyMetrics: factSafety,
		NarrativeMetrics:  narrative,
		LatencyMetrics:    latency,
		TokenMetrics:      tokens,
		AdjudicationMetrics: adjudication,
		ModelVerdict:      analysis.ReadinessVerdicts,
		SmokeReadiness:    DeriveSmokeReadinessVerdicts(metrics, analysis),
		AssessmentMigration: migration,
		SmokeV2Readiness:    smokeReadiness,
		Results:           results,
		Summary:           FormatSummary(meta, metrics, analysis, EvaluationVersionV2, mode),
	}
	if meta.E01DiagnosticMode {
		report.E01TargetedReadiness = DeriveE01TargetedDiagnosticReadiness(results)
		report.E01PostArchitectureReadiness = DeriveE01PostArchitectureReadiness(results)
	}
	return report
}

// ReportWriteResult holds paths for evaluation artifact output.
type ReportWriteResult struct {
	LatestPath      string `json:"latestPath"`
	TimestampedPath string `json:"timestampedPath,omitempty"`
}

// WriteReport writes an immutable timestamped artifact first, then latest.json as a separate copy.
// Default output resolves to the module-root .eval-output (not the go test package working directory).
func WriteReport(report EvaluationReport, outputDir string) (ReportWriteResult, error) {
	result := ReportWriteResult{}

	resolved, err := ResolveOutputDir(outputDir)
	if err != nil {
		return result, fmt.Errorf("resolve output dir: %w", err)
	}
	if err := os.MkdirAll(resolved, 0o755); err != nil {
		return result, fmt.Errorf("create output dir: %w", err)
	}

	sanitized := sanitizeReport(report)
	data, err := json.MarshalIndent(sanitized, "", "  ")
	if err != nil {
		return result, fmt.Errorf("marshal report: %w", err)
	}

	prefix := strings.TrimSpace(report.RunPlan.ArtifactPrefix)
	if prefix != "" && report.RunStatus == RunStatusExecuted {
		tsPath, err := nextTimestampedArtifactPath(resolved, prefix)
		if err != nil {
			return result, fmt.Errorf("resolve timestamped path: %w", err)
		}
		if err := writeVerifiedArtifact(tsPath, data, 0o644); err != nil {
			return result, fmt.Errorf("write timestamped report: %w", err)
		}
		result.TimestampedPath = tsPath
	}

	latestPath := filepath.Join(resolved, LatestReportFile)
	if err := writeVerifiedArtifact(latestPath, data, 0o644); err != nil {
		return result, fmt.Errorf("write latest report: %w", err)
	}
	result.LatestPath = latestPath

	return result, nil
}

func writeVerifiedArtifact(path string, data []byte, perm os.FileMode) error {
	if len(data) == 0 {
		return fmt.Errorf("refusing to write empty artifact: %s", path)
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	tmpPath := path + ".tmp"
	if err := os.WriteFile(tmpPath, data, perm); err != nil {
		return err
	}
	if err := os.Rename(tmpPath, path); err != nil {
		_ = os.Remove(tmpPath)
		return err
	}
	info, err := os.Stat(path)
	if err != nil {
		return fmt.Errorf("verify artifact stat: %w", err)
	}
	if info.Size() == 0 {
		return fmt.Errorf("artifact empty after write: %s", path)
	}
	readBack, err := os.ReadFile(path)
	if err != nil {
		return fmt.Errorf("verify artifact read-back: %w", err)
	}
	if len(readBack) != len(data) {
		return fmt.Errorf("artifact size mismatch after write: %s", path)
	}
	return nil
}

func nextTimestampedArtifactPath(outputDir, prefix string) (string, error) {
	stamp := time.Now().UTC().Format("20060102-150405")
	base := fmt.Sprintf("%s-%s", prefix, stamp)
	candidate := filepath.Join(outputDir, base+".json")
	if _, err := os.Stat(candidate); os.IsNotExist(err) {
		return candidate, nil
	} else if err != nil {
		return "", err
	}
	for i := 2; i < 100; i++ {
		alt := filepath.Join(outputDir, fmt.Sprintf("%s-%02d.json", base, i))
		if _, err := os.Stat(alt); os.IsNotExist(err) {
			return alt, nil
		} else if err != nil {
			return "", err
		}
	}
	return "", fmt.Errorf("too many timestamp collisions for %s", base)
}

func sanitizeReport(report EvaluationReport) EvaluationReport {
	report.Summary = redactSecrets(report.Summary)
	report.PreflightSummary = redactSecrets(report.PreflightSummary)
	return report
}

var secretTokenPattern = regexp.MustCompile(`sk-[a-zA-Z0-9_-]+`)

func redactSecrets(text string) string {
	text = secretTokenPattern.ReplaceAllString(text, "[REDACTED]")
	replacements := []struct{ old, new string }{
		{"Bearer ", "Bearer [REDACTED] "},
		{"Authorization:", "Authorization: [REDACTED]"},
	}
	for _, r := range replacements {
		text = strings.ReplaceAll(text, r.old, r.new)
	}
	return text
}

// FormatSummary produces a human-readable text summary.
func FormatSummary(meta RunMetadata, m AggregateMetrics, analysis FullEvalAnalysis, version, mode string) string {
	total := m.TotalRuns
	httpBase := m.HTTPSuccessCount
	var b strings.Builder

	b.WriteString("=== P0-4.5.6 Monthly Summary Evaluation Report (")
	b.WriteString(version)
	b.WriteString(") ===\n")
	b.WriteString(fmt.Sprintf("evaluationMode=%s\n", mode))
	b.WriteString(fmt.Sprintf("startedAt=%s finishedAt=%s\n", meta.StartedAt, meta.FinishedAt))
	if meta.SmokeV2Mode {
		b.WriteString("SMOKE V2 SUBSET: 6 cases × 2 repeats = 12 runs (definition only unless explicitly executed)\n")
	} else if meta.PilotMode {
		b.WriteString(fmt.Sprintf("PILOT MODE: %s\n", meta.PilotNote))
	} else {
		b.WriteString(fmt.Sprintf("FULL EVALUATION: datasetCases=%d totalRuns=%d\n",
			analysis.DatasetSummary.DatasetCases, analysis.DatasetSummary.FullRuns))
	}
	b.WriteString(fmt.Sprintf("configuredModel=%s upstreamModel=%s gatewayModelAlias=%s structuredOutputMode=%s\n",
		meta.ConfiguredModel, meta.UpstreamModel, meta.GatewayModelAlias, meta.StructuredOutputMode))
	b.WriteString(fmt.Sprintf("totalCases=%d totalRuns=%d\n\n", meta.TotalCases, total))

	b.WriteString("--- Transport Metrics ---\n")
	b.WriteString(fmt.Sprintf("requestAttempted=%d/%d httpResponseReceived=%d/%d http2xxSuccess=%d/%d\n",
		m.RequestAttemptedCount, total, m.HTTPResponseReceivedCount, total, m.HTTP2xxSuccessCount, total))
	b.WriteString(fmt.Sprintf("modelMetricsAssessed=%v\n\n", m.ModelMetricsAssessed))

	b.WriteString("--- Contract Metrics ---\n")
	b.WriteString(fmt.Sprintf("httpSuccessRate=%s (%d/%d)\n", FormatRateValue(m.HTTPSuccessCount, total, true), m.HTTPSuccessCount, total))
	b.WriteString(fmt.Sprintf("jsonValidRate=%s (%d/%d)\n", FormatRateValue(m.JSONValidCount, httpBase, m.ModelMetricsAssessed), m.JSONValidCount, httpBase))
	b.WriteString(fmt.Sprintf("modelDTODecodeRate=%s (%d/%d)\n", FormatRateValue(m.ModelDTODecodeCount, httpBase, m.ModelMetricsAssessed), m.ModelDTODecodeCount, httpBase))
	b.WriteString(fmt.Sprintf("modelSchemaSuccessRate=%s (%d/%d)\n", FormatRateValue(m.SchemaSuccessCount, httpBase, m.ModelMetricsAssessed), m.SchemaSuccessCount, httpBase))
	b.WriteString(fmt.Sprintf("explanationAlignmentPassRate=%s (%d/%d)\n", FormatRateValue(m.ExplanationAlignmentPassCount, httpBase, m.ModelMetricsAssessed), m.ExplanationAlignmentPassCount, httpBase))
	b.WriteString(fmt.Sprintf("gatewayMappingSuccessRate=%s (%d/%d)\n", FormatRateValue(m.ModelDTODecodeCount, httpBase, m.ModelMetricsAssessed), m.ModelDTODecodeCount, httpBase))
	b.WriteString(fmt.Sprintf("finalValidatorPassRate=%s (%d/%d)\n", FormatRateValue(m.FinalValidatorPassCount, m.ContractAmongHTTPSuccesses, m.ModelMetricsAssessed), m.FinalValidatorPassCount, m.ContractAmongHTTPSuccesses))
	b.WriteString(fmt.Sprintf("factValidationRate=%s (%d/%d)\n", FormatRateValue(m.FactValidationCount, httpBase, m.ModelMetricsAssessed), m.FactValidationCount, httpBase))
	b.WriteString(fmt.Sprintf("contractSuccessRateAmongHTTPSuccesses=%s (%d/%d)\n", FormatRateValue(m.ContractAmongHTTPSuccesses, httpBase, m.ModelMetricsAssessed), m.ContractAmongHTTPSuccesses, httpBase))
	b.WriteString(fmt.Sprintf("overallEndToEndSuccessRate=%d/%d (%.1f%%) [includes semantic; not contract-only]\n\n",
		m.EndToEndSuccessCount, total, rate(m.EndToEndSuccessCount, total)*100))

	b.WriteString("--- Fact Safety ---\n")
	b.WriteString(fmt.Sprintf("inventedAmountCount=%d\n", m.InventedAmountCount))
	b.WriteString(fmt.Sprintf("invalidCitedFactCount=%d\n", m.InvalidCitedFactCount))
	b.WriteString(fmt.Sprintf("invalidKeyFactSourceCount=%d\n", m.InvalidKeyFactSourceCount))
	b.WriteString(fmt.Sprintf("invalidReferenceCount=%d\n", m.InvalidReferenceCount))
	b.WriteString(fmt.Sprintf("invalidActionCount=%d\n", m.InvalidActionCount))
	b.WriteString(fmt.Sprintf("forbiddenClaimCount=%d\n\n", m.ForbiddenClaimCount))

	if IsV2EvaluationMode(mode) {
		b.WriteString("--- Explanation Metrics (v2 gating) ---\n")
		v2Runs := m.ContractAmongHTTPSuccesses
		if v2Runs == 0 {
			v2Runs = total
		}
		b.WriteString(fmt.Sprintf("riskExplanationCoverageRate=%s (%d/%d)\n", FormatRateValue(m.RiskExplanationCoveragePassCount, v2Runs, m.ModelMetricsAssessed), m.RiskExplanationCoveragePassCount, v2Runs))
		b.WriteString(fmt.Sprintf("unknownExplanationCoverageRate=%s (%d/%d)\n", FormatRateValue(m.UnknownExplanationCoveragePassCount, v2Runs, m.ModelMetricsAssessed), m.UnknownExplanationCoveragePassCount, v2Runs))
		b.WriteString(fmt.Sprintf("citedFactKeyAlignmentRate=%s (%d/%d)\n", FormatRateValue(m.CitationAlignmentPassCount, v2Runs, m.ModelMetricsAssessed), m.CitationAlignmentPassCount, v2Runs))
		b.WriteString(fmt.Sprintf("missingRiskExplanationCount=%d unsupportedRiskExplanationCount=%d\n", m.MissingRiskExplanationCount, m.UnsupportedRiskExplanationCount))
		b.WriteString(fmt.Sprintf("missingRequiredUnknownExplanationCount=%d unsupportedUnknownExplanationCount=%d\n\n", m.MissingRequiredUnknownExplanationCount, m.UnsupportedUnknownExplanationCount))

		b.WriteString("--- Policy Metrics ---\n")
		b.WriteString(fmt.Sprintf("policyStructuralAlignmentRate=%s (%d/%d)\n\n", FormatRateValue(m.PolicyStructuralAlignmentPassCount, v2Runs, m.ModelMetricsAssessed), m.PolicyStructuralAlignmentPassCount, v2Runs))

		b.WriteString("--- Narrative Metrics ---\n")
		b.WriteString(fmt.Sprintf("knownNoDebtContradictionCount=%d\n", m.KnownNoDebtContradictionCount))
		b.WriteString(fmt.Sprintf("missingDebtOverconfidenceCount=%d\n", m.MissingDebtOverconfidenceCount))
		b.WriteString(fmt.Sprintf("safePlusMissingMisstatementCount=%d\n", m.SafePlusMissingMisstatementCount))
		b.WriteString(fmt.Sprintf("narrativeSeverityMismatchCount=%d\n", m.NarrativeSeverityMismatchCount))
		b.WriteString(fmt.Sprintf("unsupportedNarrativeRiskClaimCount=%d\n\n", m.UnsupportedNarrativeRiskClaimCount))
	}

	b.WriteString("--- Legacy Semantic Metrics (")
	b.WriteString(LegacyMetricLabel)
	b.WriteString(") ---\n")
	b.WriteString(fmt.Sprintf("expectedRiskMatchRate=%s (%d/%d) baseline=%.1f%%\n",
		FormatRateValue(m.ExpectedRiskMatchCount, total, m.ModelMetricsAssessed), m.ExpectedRiskMatchCount, total, LegacyBaselineExpectedRiskMatchRate*100))
	b.WriteString(fmt.Sprintf("unknownBehaviorPassRate=%s (%d/%d)\n\n", FormatRateValue(m.UnknownBehaviorPassCount, total, m.ModelMetricsAssessed), m.UnknownBehaviorPassCount, total))

	b.WriteString("--- Latency / Tokens ---\n")
	b.WriteString(fmt.Sprintf("latencyP50Ms=%d latencyP95Ms=%d latencyMaxMs=%d\n", m.LatencyP50Ms, m.LatencyP95Ms, m.LatencyMaxMs))
	b.WriteString(fmt.Sprintf("timeoutRate=%d/%d slowRequestCount(>20s)=%d\n", m.TimeoutCount, total, m.SlowRequestCount))
	b.WriteString(fmt.Sprintf("promptTokensAverage=%.1f completionTokensAverage=%.1f totalTokensAverage=%.1f\n\n",
		m.PromptTokensAverage, m.CompletionTokensAverage, m.TotalTokensAverage))

	if IsV2EvaluationMode(mode) {
		b.WriteString("--- v2 Acceptance Thresholds ---\n")
		ac := analysis.V2Acceptance
		b.WriteString(fmt.Sprintf("contractCompliance >= 99%% pass=%v\n", ac.ContractCompliancePass))
		b.WriteString(fmt.Sprintf("policyStructuralAlignment = 100%% pass=%v\n", ac.PolicyStructuralAlignmentPass))
		b.WriteString(fmt.Sprintf("riskExplanationCoverage >= 99%% pass=%v\n", ac.RiskExplanationCoveragePass))
		b.WriteString(fmt.Sprintf("unknownExplanationCoverage >= 99%% pass=%v\n", ac.UnknownExplanationCoveragePass))
		b.WriteString(fmt.Sprintf("citedFactKeyAlignment >= 99%% pass=%v\n", ac.CitedFactKeyAlignmentPass))
		b.WriteString(fmt.Sprintf("finalValidator >= 99%% pass=%v\n", ac.FinalValidatorPass))
		b.WriteString(fmt.Sprintf("critical narrative counts = 0 pass=%v\n\n", ac.KnownNoDebtContradictionPass && ac.MissingDebtOverconfidencePass && ac.SafePlusMissingMisstatementPass && ac.NarrativeSeverityMismatchPass && ac.UnsupportedNarrativeRiskClaimPass))

		b.WriteString("--- Readiness Verdicts ---\n")
		rv := analysis.ReadinessVerdicts
		b.WriteString(fmt.Sprintf("Integration %s\n", rv.IntegrationReadiness))
		b.WriteString(fmt.Sprintf("Explanation Contract %s\n", rv.ExplanationContractReadiness))
		b.WriteString(fmt.Sprintf("Narrative Semantic %s\n", rv.NarrativeSemanticReadiness))
		b.WriteString(fmt.Sprintf("Production %s\n", rv.ProductionReadiness))
		if meta.SmokeV2Mode || meta.ConnectivityProbeMode {
			srv := DeriveSmokeReadinessVerdicts(m, analysis)
			b.WriteString("\n--- Smoke Readiness ---\n")
			b.WriteString(fmt.Sprintf("SmokeInfrastructure %s\n", srv.SmokeInfrastructureReadiness))
			b.WriteString(fmt.Sprintf("SmokeModelStructural %s\n", srv.SmokeModelStructuralContractReadiness))
			b.WriteString(fmt.Sprintf("SmokeExplanationContract %s\n", srv.SmokeExplanationContractReadiness))
			b.WriteString(fmt.Sprintf("SmokeFinalContract %s\n", srv.SmokeFinalContractReadiness))
			b.WriteString(fmt.Sprintf("SmokeNarrative %s\n", srv.SmokeNarrativeReadiness))
			b.WriteString(fmt.Sprintf("SmokeFullEval %s\n\n", srv.SmokeFullEvalReadiness))
		} else {
			b.WriteString("\n")
		}
	} else {
		b.WriteString("--- Acceptance Thresholds (legacy) ---\n")
		b.WriteString("contractCompliance >= 99%\n")
		b.WriteString("expectedRiskMatch >= 95%\n\n")
	}

	b.WriteString("--- Failure Breakdown ---\n")
	if len(m.FailureBreakdown) == 0 {
		b.WriteString("(none)\n")
	} else {
		for _, class := range sortedFailureBreakdown(m.FailureBreakdown) {
			b.WriteString(fmt.Sprintf("%s=%d\n", class, m.FailureBreakdown[class]))
		}
	}

	b.WriteString(FormatFullAnalysisSummary(analysis, mode))
	return b.String()
}

func sortedFailureBreakdown(breakdown map[string]int) []string {
	keys := make([]string, 0, len(breakdown))
	for k := range breakdown {
		keys = append(keys, k)
	}
	sortStrings(keys)
	return keys
}

// WriteAdjudicationReport writes adjudication output beside the source report.
func WriteAdjudicationReport(adj AdjudicationReport, outputDir string) (string, error) {
	resolved, err := ResolveOutputDir(outputDir)
	if err != nil {
		return "", fmt.Errorf("resolve output dir: %w", err)
	}
	if err := os.MkdirAll(resolved, 0o755); err != nil {
		return "", fmt.Errorf("create output dir: %w", err)
	}
	path := filepath.Join(resolved, "adjudicated.json")
	data, err := json.MarshalIndent(adj, "", "  ")
	if err != nil {
		return "", fmt.Errorf("marshal adjudication: %w", err)
	}
	if err := writeVerifiedArtifact(path, data, 0o644); err != nil {
		return "", fmt.Errorf("write adjudication: %w", err)
	}
	return path, nil
}

func sortStrings(items []string) {
	for i := 0; i < len(items); i++ {
		for j := i + 1; j < len(items); j++ {
			if items[j] < items[i] {
				items[i], items[j] = items[j], items[i]
			}
		}
	}
}

// NewRunMetadata creates metadata from config and filter options.
func NewRunMetadata(cfg config.Config, filter FilterOptions, totalCases, totalRuns int, mode, upstreamModel string) RunMetadata {
	return RunMetadata{
		StartedAt:            time.Now().UTC().Format(time.RFC3339),
		ConfiguredModel:      cfg.BailianModel,
		UpstreamModel:        upstreamModel,
		GatewayModelAlias:    cfg.ModelAlias,
		StructuredOutputMode: cfg.BailianStructuredOutputMode,
		TotalCases:           totalCases,
		TotalRuns:            totalRuns,
		CaseFilter:           filter.CaseID,
		CategoryFilter:       filter.Category,
		RepeatOverride:       filter.RepeatOverride,
		SmokeV2Mode:           filter.SmokeV2Mode,
		E01DiagnosticMode:     filter.E01DiagnosticMode,
		ConnectivityProbeMode: filter.ConnectivityProbeMode,
		C2CTargetedMode:       filter.C2CTargetedMode,
	}
}
