package eval

import (
	"context"
	"fmt"
	"strings"
	"time"

	"github.com/youshu/youshu-ai-gateway/internal/config"
	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/factpack"
	"github.com/youshu/youshu-ai-gateway/internal/handler"
	"github.com/youshu/youshu-ai-gateway/internal/prompt"
	"github.com/youshu/youshu-ai-gateway/internal/provider"
	"github.com/youshu/youshu-ai-gateway/internal/smoke"
)

// BailianDiagnoser is the upstream interface used by the evaluation runner.
type BailianDiagnoser interface {
	DiagnoseMonthlySummary(ctx context.Context, req contract.RequestEnvelope) (contract.AssistantAnswerDraftDTO, provider.DecodeDiagnostics, error)
}

// RunEvaluation executes all filtered cases against the upstream provider.
func RunEvaluation(ctx context.Context, cfg config.Config, upstream BailianDiagnoser, opts FilterOptions) (EvaluationReport, error) {
	if err := ValidateDataset(AllCases()); err != nil {
		return EvaluationReport{}, fmt.Errorf("dataset: %w", err)
	}

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
	if opts.PilotMode {
		meta.PilotMode = true
		meta.PilotNote = "pilot evaluation with representative subset; not a formal model conclusion"
	}
	if opts.SmokeV2Mode {
		meta.SmokeV2Mode = true
		meta.PilotNote = "v2 smoke subset (6 cases × 2 repeats = 12 runs)"
	}
	if opts.ConnectivityProbeMode {
		meta.ConnectivityProbeMode = true
		meta.PilotNote = "connectivity probe (A01 × 1)"
	}
	if opts.E01DiagnosticMode {
		meta.E01DiagnosticMode = true
		meta.PilotNote = "E01 targeted diagnostic (E01_partial_debt_data × 2)"
	}
	if opts.C2CTargetedMode {
		meta.C2CTargetedMode = true
		meta.PilotNote = "C2C keyFact targeted verification (C01/C04/E01 × 2 = 6 assessed samples)"
		meta.ContractIdentity = LoadFrozenContractIdentity()
	}

	plans := ExpandRuns(cases)
	meta.TotalRuns = len(plans)

	var results []RunResult
	for _, runPlan := range plans {
		result := executeRun(ctx, upstream, runPlan.Case, runPlan.RunIndex, mode)
		results = append(results, result)
		if meta.UpstreamModel == "" && result.UpstreamModel != "" {
			meta.UpstreamModel = result.UpstreamModel
		}
	}
	meta.StartedAt = started.Format(time.RFC3339)
	meta.FinishedAt = time.Now().UTC().Format(time.RFC3339)

	metrics := ComputeMetrics(results, mode)
	report := BuildReport(meta, results, metrics, mode)
	report.RunPlan = plan
	report.RunStatus = RunStatusExecuted
	report.PreflightSummary = FormatRunSummary(cfg, plan, preflight)
	return report, nil
}

func buildBlockedReport(cfg config.Config, opts FilterOptions, plan EvaluationRunPlan, preflight LivePreflightResult) EvaluationReport {
	mode := plan.EvaluationMode
	meta := NewRunMetadata(cfg, opts, plan.ExpectedCaseCount, 0, mode, "")
	meta.TotalRuns = 0
	if opts.SmokeV2Mode {
		meta.SmokeV2Mode = true
	}
	if opts.PilotMode {
		meta.PilotMode = true
	}
	now := time.Now().UTC().Format(time.RFC3339)
	meta.StartedAt = now
	meta.FinishedAt = now

	metrics := ComputeMetrics(nil, mode)
	report := BuildReport(meta, nil, metrics, mode)
	report.RunPlan = plan
	report.RunStatus = preflight.RunStatus
	report.PreflightSummary = FormatRunSummary(cfg, plan, preflight)
	report.Summary = report.PreflightSummary + "\n" + report.Summary
	return report
}

func executeRun(ctx context.Context, upstream BailianDiagnoser, c EvaluationCase, runIndex int, mode string) RunResult {
	env := c.Envelope
	env.RequestID = fmt.Sprintf("%s-run-%d", c.ID, runIndex)

	if err := factpack.ValidateRiskSourceFactAvailability(env.FinancialRiskAssessment, env.MonthlySummaryFacts); err != nil {
		return buildRiskSourceFactUnavailableRunResult(c, runIndex, env, err)
	}

	draft, diag, _ := upstream.DiagnoseMonthlySummary(ctx, env)
	transportDetail := BuildTransportFailureDetail(diag)

	if diag.DraftDTODecode != provider.StagePass {
		attachKeyFactValueSchemaMeta(&diag, env)
	}

	var semantic SemanticResult
	var v2Semantic V2SemanticResult
	contractPass := false
	explanationPass := diag.ExplanationAlignment == provider.StagePass ||
		(diag.ExplanationAlignment == provider.StageSkip && diag.DraftDTODecode == provider.StagePass)
	provenancePass := diag.ProvenanceAssembly == provider.StagePass ||
		diag.ProvenanceAssembly == provider.StageSkip
	modelPipelineEligible := diag.HTTP2xxSuccess && diag.DraftDTODecode == provider.StagePass && explanationPass && provenancePass

	if modelPipelineEligible {
		enumValues := handler.ExtractEnumValues(draft)
		diag.KeyFactKinds = enumValues.KeyFactKinds
		diag.KeyFactValueTypes = enumValues.KeyFactValueTypes
		diag.WarningSeverities = enumValues.WarningSeverities
		diag.ActionDestinations = enumValues.ActionDestinations

		schema := handler.DiagnoseSchema(draft)
		if schema.Passed {
			diag.GatewaySchemaValidation = provider.StagePass
			factDiag := smoke.DiagnoseFactsWithKeySets(draft, env.MonthlySummaryFacts, factpack.BuildKeySetsForRequest(env.MonthlySummaryFacts, env.FinancialRiskAssessment))
			if factDiag.Passed {
				diag.FactValidation = provider.StagePass
			} else {
				diag.FactValidation = provider.StageFail
			}
			attachFactDiagnostics(&diag, factDiag)
		} else {
			diag.GatewaySchemaValidation = provider.StageFail
			diag.FactValidation = provider.StageSkip
		}
		diag.TitleValid = schema.TitleValid
		diag.BodyValid = schema.BodyValid
		diag.AnswerValid = schema.AnswerValid
		diag.ArraysValid = schema.ArraysValid
		diag.EnumValid = schema.EnumValid
		diag.KeyFactKindValid = schema.KeyFactKindValid
		diag.KeyFactValueValid = schema.KeyFactValueValid
		diag.WarningSeverityValid = schema.WarningSeverityValid
		diag.ActionDestinationValid = schema.ActionDestinationValid
		diag.InvalidEnumField = schema.InvalidEnumField
		diag.InvalidEnumValue = schema.InvalidEnumValue
		diag.SchemaFailedRule = schema.FailedRule

		contractPass = diag.EndToEndSuccess()
		if contractPass {
			semantic = CheckExpectations(c, draft)
			if IsV2EvaluationMode(mode) {
				v2Semantic = CheckExplanationExpectationsV2(c, draft, explanationPass, provenancePass)
			}
		}
	}

	snap := BuildStructuredSnapshot(c, draft)
	if contractPass {
		snap.StructuredConclusionPass = semantic.StructuredConclusionPass
	}

	explanationStage := provider.StageSkip
	switch {
	case diag.ExplanationAlignment == provider.StagePass:
		explanationStage = provider.StagePass
	case diag.ExplanationAlignment == provider.StageFail:
		explanationStage = provider.StageFail
	case explanationPass && diag.HTTP2xxSuccess:
		explanationStage = provider.StagePass
	case diag.HTTP2xxSuccess && diag.DraftDTODecode == provider.StagePass:
		explanationStage = provider.StageFail
	}

	modelAssessed := ModelResponseAssessed(diag, contractPass)

	stages := ContractStages{
		HTTPSuccess:             diag.HTTPSuccess,
		UpstreamHTTP:            diag.UpstreamHTTP,
		ContentJSONValid:        diag.ContentJSONValid,
		GenericJSONObjectDecode: diag.GenericJSONObjectDecode,
		DraftDTODecode:          diag.DraftDTODecode,
		DTODecodeErrorKind:      diag.DTODecodeErrorKind,
		AlignmentFailureCode:    diag.AlignmentFailureCode,
		GatewaySchemaValidation: diag.GatewaySchemaValidation,
		FactValidation:          diag.FactValidation,
		ExplanationAlignment:    explanationStage,
		ProvenanceAssembly:      provenanceStage(diag),
		ProvenanceAssemblyFailureCode: diag.ProvenanceAssemblyFailureCode,
		TimeoutStage:            diag.TimeoutStage,

		RequestAttempted:      transportDetail.RequestAttempted,
		HTTPResponseReceived:  transportDetail.HTTPResponseReceived,
		HTTP2xxSuccess:        transportDetail.HTTP2xxSuccess,
		ErrorCategory:           transportDetail.ErrorCategory,
		HTTPStatus:              transportDetail.HTTPStatus,
		ProviderErrorCode:       transportDetail.ProviderErrorCode,
		ProviderErrorMessage:    transportDetail.ProviderErrorMessage,
		SelectedProvider:        transportDetail.SelectedProvider,
		ModelResponseAssessed:   modelAssessed,
	}

	semanticPass := false
	endToEndPass := false
	if modelAssessed {
		semanticPass = semantic.Passed
		endToEndPass = contractPass && semanticPass
		if IsV2EvaluationMode(mode) && contractPass {
			semanticPass = v2Semantic.Passed
			endToEndPass = contractPass && v2Semantic.Passed
		}
	}

	result := RunResult{
		CaseID:    c.ID,
		Category:  c.Category,
		RunIndex:  runIndex,
		RequestID: env.RequestID,

		UpstreamModel: diag.UpstreamModel,
		ContractPass:  contractPass,
		SemanticPass:  semanticPass,
		EndToEndPass:  endToEndPass,

		LatencyMs:        diag.Latency.Milliseconds(),
		PromptTokens:     diag.PromptTokens,
		CompletionTokens: diag.CompletionTokens,
		TotalTokens:      diag.TotalTokens,
		Timeout:          diag.TimeoutStage == provider.TimeoutStageUpstreamHTTP,

		InventedFacts:          diag.InventedFacts,
		InvalidCitedFactCount:  diag.InvalidCitedKeyCount,
		InvalidKeyFactSource:   diag.InvalidKeyFactCount,
		InvalidReferenceCount:  diag.InvalidReferences,
		InvalidActionCount:     diag.InvalidActions,
		ForbiddenClaimCount:    len(semantic.ForbiddenClaimHits),
		MissingConclusionCount: len(semantic.MissingStructuredConclusions),
		RiskMatch:              semantic.RiskMatch,
		UnknownBehaviorPass:    semantic.UnknownBehaviorPass,

		ExplanationAlignmentPass: explanationPass,
		ProvenanceAssemblyPass:   provenancePass,
		PolicyStructuralPass:     v2Semantic.PolicyStructuralPass,
		FinalValidatorPass:       v2Semantic.FinalValidatorPass,
		V2Semantic:               v2Semantic,

		Transport:             transportDetail,
		ModelResponseAssessed: modelAssessed,

		ContractStages:     stages,
		Semantic:           semantic,
		StructuredSnapshot: snap,
		DiagnosticSnapshot: BuildEvaluationDiagnosticSnapshot(c, env, diag, draft, explanationStage),
	}
	EnrichKeyFactDiagnosticSnapshot(&result, env, draft, diag)

	if !result.EndToEndPass {
		result.FailureClass, result.FailureDetail = classifyFailure(stages, semantic, v2Semantic, contractPass, mode, diag.InvalidKeyFactCount, diag.InventedFacts)
		result.FailureSeverity = ClassifyFailureSeverity(result.FailureClass, c, snap)
		if modelAssessed {
			result.AuditVerdict = AuditSemanticFailure(c, result, snap)
		} else if stages.HTTP2xxSuccess && stages.ExplanationAlignment == provider.StageFail {
			alignCode := stages.AlignmentFailureCode
			if alignCode == "" {
				alignCode = InferAlignmentFailureCodeFromCase(c.ID)
				stages.AlignmentFailureCode = alignCode
			}
			result.AuditVerdict = SemanticAuditVerdict{
				CaseID:       c.ID,
				RunIndex:     runIndex,
				FailureClass: ClassifyAlignmentFailure(alignCode),
				Verdict:      adjudicateAlignmentFailure(alignCode),
				Notes:        []string{"explanation alignment failure on HTTP 2xx"},
			}
		} else if note := contractStageAuditNote(stages); note != "" {
			result.AuditVerdict = SemanticAuditVerdict{
				CaseID:       c.ID,
				RunIndex:     runIndex,
				FailureClass: result.FailureClass,
				Verdict:      VerdictAmbiguous,
				Notes:        []string{note},
			}
		} else {
			result.AuditVerdict = SemanticAuditVerdict{
				CaseID:       c.ID,
				RunIndex:     runIndex,
				FailureClass: result.FailureClass,
				Verdict:      VerdictAmbiguous,
				Notes:        []string{"transport/provider failure; semantic stages not assessed"},
			}
		}
	}
	result.EvaluationVerdict = ResolveEvaluationVerdict(result)

	return result
}

func provenanceStage(diag provider.DecodeDiagnostics) string {
	switch diag.ProvenanceAssembly {
	case provider.StagePass:
		return provider.StagePass
	case provider.StageFail:
		return provider.StageFail
	default:
		return provider.StageSkip
	}
}

func classifyFailure(
	stages ContractStages,
	semantic SemanticResult,
	v2Semantic V2SemanticResult,
	contractPass bool,
	mode string,
	invalidKeyFactCount int,
	inventedFacts int,
) (string, string) {
	if contractFailure := ClassifyContractFailureWithFactContext(stages, invalidKeyFactCount, inventedFacts); contractFailure != "" {
		return contractFailure, "contract stage failure"
	}
	if !contractPass {
		return FailureProvider, "end-to-end contract failure"
	}
	if IsV2EvaluationMode(mode) {
		if len(v2Semantic.FailureClasses) > 0 {
			return v2Semantic.FailureClasses[0], strings.Join(v2Semantic.Details, "; ")
		}
		return FailureProvider, "unknown v2 semantic failure"
	}
	if len(semantic.FailureClasses) > 0 {
		return semantic.FailureClasses[0], strings.Join(semantic.Details, "; ")
	}
	return FailureProvider, "unknown failure"
}

func buildRiskSourceFactUnavailableRunResult(
	c EvaluationCase,
	runIndex int,
	env contract.RequestEnvelope,
	err error,
) RunResult {
	failureCode := factpack.ParseRiskSourceFactAvailabilityFailureCode(err)
	stages := ContractStages{
		RiskSourceFactAvailability:            provider.StageFail,
		RiskSourceFactAvailabilityFailureCode: failureCode,
		DraftDTODecode:                        provider.StageSkip,
		ExplanationAlignment:                  provider.StageSkip,
		ProvenanceAssembly:                    provider.StageSkip,
		GatewaySchemaValidation:               provider.StageSkip,
		FactValidation:                        provider.StageSkip,
		ModelResponseAssessed:                 false,
	}
	snap := BuildDiagnosticSnapshotFromAssessment(c, env.MonthlySummaryFacts)
	snap.ProvenanceAssemblyFailureCode = failureCode
	snap.RiskSourceFactAvailabilityFailureCode = failureCode
	result := RunResult{
		CaseID:                 c.ID,
		Category:               c.Category,
		RunIndex:               runIndex,
		RequestID:              env.RequestID,
		ContractPass:           false,
		SemanticPass:           false,
		EndToEndPass:           false,
		FailureClass:           FailureRiskSourceFactUnavailable,
		FailureDetail:          err.Error(),
		ExplanationAlignmentPass: false,
		ProvenanceAssemblyPass:   false,
		ContractStages:         stages,
		DiagnosticSnapshot:     snap,
		StructuredSnapshot:     BuildStructuredSnapshot(c, contract.AssistantAnswerDraftDTO{}),
		AuditVerdict: SemanticAuditVerdict{
			CaseID:       c.ID,
			RunIndex:     runIndex,
			FailureClass: FailureRiskSourceFactUnavailable,
			Verdict:      VerdictAmbiguous,
			Notes:        []string{"pre-provider risk source fact availability failure; HTTP not attempted"},
		},
		FailureSeverity:   ClassifyFailureSeverity(FailureRiskSourceFactUnavailable, c, BuildStructuredSnapshot(c, contract.AssistantAnswerDraftDTO{})),
		EvaluationVerdict: EvaluationVerdictAmbiguous,
	}
	return result
}

func attachKeyFactValueSchemaMeta(diag *provider.DecodeDiagnostics, env contract.RequestEnvelope) {
	if env.MonthlySummaryFacts == nil {
		return
	}
	base, err := prompt.LoadAssistantAnswerModelDraftSchema()
	if err != nil {
		return
	}
	bound, err := prompt.BuildAssistantAnswerSchema(base, factpack.BuildKeySetsForRequest(env.MonthlySummaryFacts, env.FinancialRiskAssessment), prompt.BuildExplanationSchemaKeys(env.FinancialRiskAssessment))
	if err != nil {
		return
	}
	meta, err := prompt.DescribeKeyFactValueSchema(bound)
	if err != nil {
		return
	}
	diag.KeyFactValueSchemaMeta = meta.Summary()
}

func attachFactDiagnostics(diag *provider.DecodeDiagnostics, result smoke.FactDiagnostics) {
	diag.InventedFacts = result.InventedFactCount
	diag.InvalidReferences = result.InvalidReferenceCount
	diag.InvalidActions = result.InvalidActionCount
	diag.InvalidCitedKeyCount = result.InvalidCitedKeyCount
	diag.InvalidKeyFactCount = result.InvalidKeyFactCount
	diag.InvalidWarningSources = result.InvalidWarningSourceCount
	diag.AmountFactsValid = result.AmountFactsValid
	diag.CitedFactKeysValid = result.CitedFactKeysValid
	diag.KeyFactSourcesValid = result.KeyFactSourcesValid
	diag.KeyFactValuesValid = result.KeyFactValuesValid
	diag.ReferencesValid = result.ReferencesValid
	diag.ActionsValid = result.ActionsValid
	diag.WarningSourcesValid = result.WarningSourcesValid
	diag.PercentFactsValid = result.PercentFactsValid
	diag.DateFactsValid = result.DateFactsValid
	diag.FactFailureRules = append([]string(nil), result.FailureRules...)
	diag.InvalidFactRule = result.InvalidFactRule
	diag.InvalidFactKey = result.InvalidFactKey
	diag.InvalidFactSource = result.InvalidFactSource
	diag.ExpectedFactKey = result.ExpectedFactKey
	diag.ActualFactKey = result.ActualFactKey
}

// SetUpstreamModel updates report metadata with the upstream model name.
func SetUpstreamModel(report *EvaluationReport, model string) {
	report.Metadata.UpstreamModel = model
	report.Summary = FormatSummary(report.Metadata, report.Metrics, report.Analysis, report.EvaluationVersion, report.EvaluationMode)
}
