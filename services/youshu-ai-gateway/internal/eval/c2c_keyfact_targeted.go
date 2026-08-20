package eval

import (
	"context"
	"fmt"
	"math"
	"sort"
	"strings"
	"time"

	"github.com/youshu/youshu-ai-gateway/internal/config"
	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/factpack"
	"github.com/youshu/youshu-ai-gateway/internal/prompt"
	"github.com/youshu/youshu-ai-gateway/internal/provider"
)

const (
	C2CCaseC01 = "C01_no_debt"
	C2CCaseC04 = "C04_multiple_debts"
	C2CCaseE01 = "E01_partial_debt_data"

	C2CTargetedRepeatCount = 2
	C2CMaxAttemptsPerCase  = 4
)

// C2CTargetedCaseIDs returns the fixed C2C verification case order.
func C2CTargetedCaseIDs() []string {
	return []string{C2CCaseC01, C2CCaseC04, C2CCaseE01}
}

// C2CTargetedFilterOptions returns C01/C04/E01 × 2 targeted verification options.
func C2CTargetedFilterOptions() FilterOptions {
	return FilterOptions{
		C2CTargetedMode:    true,
		C2CTargetedCaseIDs: C2CTargetedCaseIDs(),
		RepeatOverride:     C2CTargetedRepeatCount,
	}
}

// BuildC2CTargetedRunPlan returns the canonical C2C run plan (3 cases × 2 = 6 runs).
func BuildC2CTargetedRunPlan() (EvaluationRunPlan, error) {
	cases, err := FilterCases(AllCases(), C2CTargetedFilterOptions())
	if err != nil {
		return EvaluationRunPlan{}, err
	}
	plan := runPlanFromCases(cases, C2CTargetedFilterOptions())
	if plan.ExpectedCaseCount != 3 || plan.ExpectedRunCount != 6 {
		return EvaluationRunPlan{}, fmt.Errorf("C2C plan must be 3 cases / 6 runs, got %d/%d", plan.ExpectedCaseCount, plan.ExpectedRunCount)
	}
	return plan, nil
}

// MaterializedKeyFactSnapshot captures canonical keyFact materialization for C2C diagnostics.
type MaterializedKeyFactSnapshot struct {
	Source         string `json:"source"`
	CanonicalType  string `json:"canonicalType"`
	CanonicalValue string `json:"canonicalValue,omitempty"`
}

// FrozenContractIdentity records prompt and model schema identity for live verification artifacts.
type FrozenContractIdentity struct {
	PromptVersion             string `json:"promptVersion"`
	PromptFingerprint         string `json:"promptFingerprint"`
	ModelSchemaContractMarker string `json:"modelSchemaContractMarker"`
	ModelSchemaFingerprint    string `json:"modelSchemaFingerprint"`
}

// C2CTargetedReadiness summarizes the 6-run C2C keyFact verification batch.
type C2CTargetedReadiness struct {
	Verdict                         string `json:"verdict"`
	PlannedRuns                     int    `json:"plannedRuns"`
	ActualAttempts                  int    `json:"actualAttempts"`
	AssessedSamples                 int    `json:"assessedSamples"`
	TransportFailureCount           int    `json:"transportFailureCount"`
	ModelStructuralPassCount        int    `json:"modelStructuralPassCount"`
	KeyFactSelectionPassCount       int    `json:"keyFactSelectionPassCount"`
	KeyFactMaterializationPassCount int    `json:"keyFactMaterializationPassCount"`
	KeyFactCanonicalParityPassCount int    `json:"keyFactCanonicalParityPassCount"`
	FactValidationPassCount         int    `json:"factValidationPassCount"`
	EndToEndPassCount               int    `json:"endToEndPassCount"`
	InvalidKeyFactSourceCount       int    `json:"invalidKeyFactSourceCount"`
	ConfirmedModelFailures          int    `json:"confirmedModelFailures"`
	ApplicationFailures             int    `json:"applicationFailures"`
	EvaluatorFalsePositives         int    `json:"evaluatorFalsePositives"`
	C01EndToEndPassCount            int    `json:"c01EndToEndPassCount"`
	C04EndToEndPassCount            int    `json:"c04EndToEndPassCount"`
	E01EndToEndPassCount            int    `json:"e01EndToEndPassCount"`
	NextStep                        string `json:"nextStep,omitempty"`
}

// LoadFrozenContractIdentity loads prompt and model schema identity for artifact metadata.
func LoadFrozenContractIdentity() FrozenContractIdentity {
	identity := FrozenContractIdentity{
		PromptVersion:             prompt.MonthlySummaryPromptContractVersion,
		ModelSchemaContractMarker: prompt.ModelSchemaContractMarker,
	}
	if fp, err := prompt.MonthlySummaryPromptContractFingerprint(); err == nil {
		identity.PromptFingerprint = fp
	}
	if fp, err := prompt.ModelDraftSchemaFingerprint(); err == nil {
		identity.ModelSchemaFingerprint = fp
	}
	return identity
}

// RunC2CTargetedEvaluation executes C2C with transport retry (max 4 attempts per case for 2 assessed samples).
func RunC2CTargetedEvaluation(ctx context.Context, cfg config.Config, upstream BailianDiagnoser) (EvaluationReport, error) {
	opts := C2CTargetedFilterOptions()
	plan, cases, err := BuildRunPlan(opts)
	if err != nil {
		return EvaluationReport{}, err
	}

	preflight, err := RunLivePreflight(cfg, plan)
	if err != nil {
		return EvaluationReport{}, err
	}
	if !preflight.Passed {
		return buildBlockedReport(cfg, opts, plan, preflight), nil
	}

	started := time.Now().UTC()
	mode := plan.EvaluationMode
	meta := NewRunMetadata(cfg, opts, len(cases), 0, mode, "")
	meta.C2CTargetedMode = true
	meta.PilotNote = "C2C keyFact targeted verification (C01/C04/E01 × 2 = 6 assessed samples)"
	meta.ContractIdentity = LoadFrozenContractIdentity()

	var results []RunResult
	actualAttempts := 0
	assessedSamples := 0

	for _, c := range cases {
		caseAssessed := 0
		caseAttempts := 0
		runIndex := 1
		for caseAssessed < C2CTargetedRepeatCount && caseAttempts < C2CMaxAttemptsPerCase {
			caseAttempts++
			actualAttempts++
			result := executeRun(ctx, upstream, c, runIndex, mode)
			results = append(results, result)
			if result.UpstreamModel != "" && meta.UpstreamModel == "" {
				meta.UpstreamModel = result.UpstreamModel
			}
			if result.ModelResponseAssessed {
				caseAssessed++
				assessedSamples++
			}
			runIndex++
		}
	}

	meta.TotalRuns = len(results)
	meta.StartedAt = started.Format(time.RFC3339)
	meta.FinishedAt = time.Now().UTC().Format(time.RFC3339)
	meta.C2CPlannedRuns = plan.ExpectedRunCount
	meta.C2CActualAttempts = actualAttempts
	meta.C2CAssessedSamples = assessedSamples

	metrics := ComputeMetrics(results, mode)
	report := BuildReport(meta, results, metrics, mode)
	report.RunPlan = plan
	report.RunStatus = RunStatusExecuted
	report.PreflightSummary = FormatRunSummary(cfg, plan, preflight)
	report.C2CTargetedReadiness = DeriveC2CTargetedReadiness(plan, results)
	return report, nil
}

// EnrichKeyFactDiagnosticSnapshot attaches keyFact ownership diagnostics to a run result.
func EnrichKeyFactDiagnosticSnapshot(
	result *RunResult,
	env contract.RequestEnvelope,
	draft contract.AssistantAnswerDraftDTO,
	diag provider.DecodeDiagnostics,
) {
	keySets := factpack.BuildKeySetsForRequest(env.MonthlySummaryFacts, env.FinancialRiskAssessment)
	identity := LoadFrozenContractIdentity()

	selected := make([]string, 0, len(draft.KeyFacts))
	for _, kf := range draft.KeyFacts {
		selected = append(selected, kf.Source)
	}

	result.DiagnosticSnapshot.AllowedFactKeys = append([]string(nil), keySets.AllowedFactKeys...)
	result.DiagnosticSnapshot.AllowedKeyFactKeys = append([]string(nil), keySets.AllowedKeyFactKeys...)
	result.DiagnosticSnapshot.ForbiddenKeyFactKeys = append([]string(nil), keySets.ForbiddenKeyFactKeys...)
	result.DiagnosticSnapshot.ModelSelectedKeyFactSources = append([]string(nil), selected...)
	result.DiagnosticSnapshot.MaterializedKeyFacts = materializedSnapshotsFromDraft(draft)
	result.DiagnosticSnapshot.ModelSchemaContractMarker = identity.ModelSchemaContractMarker
	result.DiagnosticSnapshot.ModelSchemaFingerprint = identity.ModelSchemaFingerprint

	if !result.ModelResponseAssessed {
		return
	}

	result.DiagnosticSnapshot.KeyFactSelectionPass = diag.DraftDTODecode == provider.StagePass &&
		diag.AlignmentFailureCode != provider.KeyFactSelectionFailureCode &&
		keyFactSelectionAllowed(selected, keySets)
	result.DiagnosticSnapshot.KeyFactMaterializationPass = diag.DraftDTODecode == provider.StagePass &&
		diag.GatewaySchemaValidation == provider.StagePass
	result.DiagnosticSnapshot.KeyFactCanonicalParityPass = diag.FactValidation == provider.StagePass &&
		result.InvalidKeyFactSource == 0 &&
		keyFactCanonicalParityPass(draft, env.MonthlySummaryFacts)
}

func keyFactSelectionAllowed(selected []string, keySets factpack.KeySets) bool {
	allowed := map[string]struct{}{}
	for _, key := range keySets.AllowedKeyFactKeys {
		allowed[key] = struct{}{}
	}
	for _, source := range selected {
		if strings.TrimSpace(source) == "" {
			return false
		}
		if _, ok := allowed[source]; !ok {
			return false
		}
	}
	return true
}

func keyFactCanonicalParityPass(draft contract.AssistantAnswerDraftDTO, facts *contract.MonthlySummaryFactsDTO) bool {
	for _, kf := range draft.KeyFacts {
		expected, err := factpack.MaterializeKeyFact(kf.Source, kf.Label, kf.Kind, facts)
		if err != nil {
			return false
		}
		if expected.Value.Type != kf.Value.Type {
			return false
		}
		switch expected.Value.Type {
		case "money":
			if expected.Value.Amount == nil || kf.Value.Amount == nil ||
				expected.Value.CurrencyCode == nil || kf.Value.CurrencyCode == nil {
				return false
			}
			if !floatEqual(*expected.Value.Amount, *kf.Value.Amount) ||
				*expected.Value.CurrencyCode != *kf.Value.CurrencyCode {
				return false
			}
		case "percent":
			if expected.Value.PercentValue == nil || kf.Value.PercentValue == nil ||
				!floatEqual(*expected.Value.PercentValue, *kf.Value.PercentValue) {
				return false
			}
		case "text":
			if expected.Value.TextValue == nil || kf.Value.TextValue == nil ||
				*expected.Value.TextValue != *kf.Value.TextValue {
				return false
			}
		case "date":
			if expected.Value.Date == nil || kf.Value.Date == nil ||
				*expected.Value.Date != *kf.Value.Date {
				return false
			}
		}
	}
	return true
}

// DeriveC2CTargetedReadiness computes C2C acceptance verdict from assessed samples.
func DeriveC2CTargetedReadiness(plan EvaluationRunPlan, results []RunResult) C2CTargetedReadiness {
	readiness := C2CTargetedReadiness{
		PlannedRuns: plan.ExpectedRunCount,
	}

	assessedByCase := map[string]int{}
	e2eByCase := map[string]int{}

	for _, r := range results {
		readiness.ActualAttempts++
		if !r.ModelResponseAssessed {
			if !r.Transport.HTTP2xxSuccess && !r.ContractStages.HTTP2xxSuccess {
				readiness.TransportFailureCount++
			}
			continue
		}
		readiness.AssessedSamples++

		structuralPass := r.ContractStages.ContentJSONValid &&
			r.ContractStages.DraftDTODecode == provider.StagePass &&
			r.ContractStages.GatewaySchemaValidation == provider.StagePass
		if structuralPass {
			readiness.ModelStructuralPassCount++
		}
		if r.DiagnosticSnapshot.KeyFactSelectionPass {
			readiness.KeyFactSelectionPassCount++
		}
		if r.DiagnosticSnapshot.KeyFactMaterializationPass {
			readiness.KeyFactMaterializationPassCount++
		}
		if r.DiagnosticSnapshot.KeyFactCanonicalParityPass {
			readiness.KeyFactCanonicalParityPassCount++
		}
		if r.ContractStages.FactValidation == provider.StagePass {
			readiness.FactValidationPassCount++
		}
		readiness.InvalidKeyFactSourceCount += r.InvalidKeyFactSource

		assessedByCase[r.CaseID]++
		if r.EndToEndPass {
			readiness.EndToEndPassCount++
			e2eByCase[r.CaseID]++
		}

		owner := classifyC2CFailureOwner(r)
		switch owner {
		case "confirmedModelFailure":
			readiness.ConfirmedModelFailures++
		case "confirmedApplicationFailure":
			readiness.ApplicationFailures++
		case "evaluatorFalsePositive":
			readiness.EvaluatorFalsePositives++
		}
	}

	readiness.C01EndToEndPassCount = e2eByCase[C2CCaseC01]
	readiness.C04EndToEndPassCount = e2eByCase[C2CCaseC04]
	readiness.E01EndToEndPassCount = e2eByCase[C2CCaseE01]

	targetAssessed := plan.ExpectedRunCount
	allCasesAssessed := assessedByCase[C2CCaseC01] >= C2CTargetedRepeatCount &&
		assessedByCase[C2CCaseC04] >= C2CTargetedRepeatCount &&
		assessedByCase[C2CCaseE01] >= C2CTargetedRepeatCount

	allMetricsPass := readiness.AssessedSamples == targetAssessed &&
		readiness.ModelStructuralPassCount == targetAssessed &&
		readiness.KeyFactSelectionPassCount == targetAssessed &&
		readiness.KeyFactMaterializationPassCount == targetAssessed &&
		readiness.KeyFactCanonicalParityPassCount == targetAssessed &&
		readiness.FactValidationPassCount == targetAssessed &&
		readiness.EndToEndPassCount == targetAssessed &&
		readiness.InvalidKeyFactSourceCount == 0 &&
		readiness.ConfirmedModelFailures == 0 &&
		readiness.ApplicationFailures == 0 &&
		readiness.EvaluatorFalsePositives == 0

	if allCasesAssessed && allMetricsPass {
		readiness.Verdict = ReadinessPass
		readiness.NextStep = "P0-4.5.6C2D Full 29-case / 37-run Post-KeyFact Regression"
		return readiness
	}

	readiness.Verdict = ReadinessFail
	if !allCasesAssessed {
		readiness.NextStep = "C2C incomplete assessed samples; retry transport or investigate blockers"
	} else if readiness.ApplicationFailures > 0 {
		readiness.NextStep = "C2C application/keyFact architecture failure; do not patch Prompt"
	} else if readiness.ConfirmedModelFailures > 0 {
		readiness.NextStep = "C2C model structural/selection failure; review before Prompt iteration"
	} else {
		readiness.NextStep = "C2C semantic/evaluator failure; adjudicate before C2D"
	}
	return readiness
}

func classifyC2CFailureOwner(r RunResult) string {
	if r.EndToEndPass || !r.ModelResponseAssessed {
		return ""
	}
	switch r.FailureClass {
	case FailureJSON, FailureDTO, FailureSchema:
		return "confirmedModelFailure"
	case FailureFact:
		if r.InvalidKeyFactSource > 0 || r.ContractStages.AlignmentFailureCode == provider.KeyFactSelectionFailureCode {
			if r.DiagnosticSnapshot.KeyFactMaterializationPass && !r.DiagnosticSnapshot.KeyFactSelectionPass {
				return "confirmedModelFailure"
			}
			return "confirmedApplicationFailure"
		}
		return "confirmedModelFailure"
	case FailureExplanationRiskCoverage, FailureExplanationUnknownCoverage, FailureExplanationCitation,
		FailureExplanationUnsupportedRisk, FailureExplanationUnsupportedUnknown,
		FailureProvenanceAssembly, FailurePolicyProjection, FailureFinalValidator,
		FailureNarrativeKnownNoDebt, FailureNarrativeMissingData, FailureNarrativeSafeMissing,
		FailureNarrativeSeverity, FailureNarrativeUnsupportedRisk:
		return "confirmedModelFailure"
	default:
		if r.AuditVerdict.Verdict == VerdictEvaluatorFalsePositive {
			return "evaluatorFalsePositive"
		}
	}
	return ""
}

func formatCanonicalValue(v contract.KeyFactValue) string {
	switch v.Type {
	case "money":
		if v.Amount != nil && v.CurrencyCode != nil {
			return fmt.Sprintf("%g %s", *v.Amount, *v.CurrencyCode)
		}
	case "percent":
		if v.PercentValue != nil {
			return fmt.Sprintf("%g%%", *v.PercentValue)
		}
	case "text":
		if v.TextValue != nil {
			return *v.TextValue
		}
	case "date":
		if v.Date != nil {
			return *v.Date
		}
	}
	return v.Type
}

func materializedSnapshotsFromDraft(draft contract.AssistantAnswerDraftDTO) []MaterializedKeyFactSnapshot {
	out := make([]MaterializedKeyFactSnapshot, 0, len(draft.KeyFacts))
	for _, kf := range draft.KeyFacts {
		out = append(out, MaterializedKeyFactSnapshot{
			Source:         kf.Source,
			CanonicalType:  kf.Value.Type,
			CanonicalValue: formatCanonicalValue(kf.Value),
		})
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Source < out[j].Source })
	return out
}

func floatEqual(a, b float64) bool {
	return math.Abs(a-b) < 0.0001
}
