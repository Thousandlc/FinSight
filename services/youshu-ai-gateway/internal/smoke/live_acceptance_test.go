package smoke_test

import (
	"context"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/youshu/youshu-ai-gateway/internal/config"
	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/eval"
	"github.com/youshu/youshu-ai-gateway/internal/factpack"
	"github.com/youshu/youshu-ai-gateway/internal/handler"
	"github.com/youshu/youshu-ai-gateway/internal/prompt"
	"github.com/youshu/youshu-ai-gateway/internal/provider"
	"github.com/youshu/youshu-ai-gateway/internal/smoke"
)

type runOutcome struct {
	CaseName  string
	RunIndex  int
	RequestID string
	Diag      provider.DecodeDiagnostics
}

// TestBailianLiveAcceptance runs P0-4.3A/B synthetic live smoke against real Bailian.
func TestBailianLiveAcceptance(t *testing.T) {
	if reason := eval.RequireLiveEvalOptIn(); reason != "" {
		t.Skip(reason)
	}
	cfg := config.Load()
	cfg.UpstreamAIProvider = config.UpstreamBailian
	if cfg.BailianAPIKey == "" || cfg.BailianBaseURL == "" || cfg.BailianModel == "" {
		t.Skip("Live Smoke 未执行：BAILIAN_API_KEY / BAILIAN_BASE_URL / BAILIAN_MODEL 未配置")
	}
	if err := cfg.ValidateUpstream(); err != nil {
		t.Fatalf("config: %v", err)
	}

	upstream, err := provider.NewUpstream(cfg)
	if err != nil {
		t.Fatalf("upstream: %v", err)
	}
	bailian, ok := upstream.(*provider.BailianProvider)
	if !ok {
		t.Fatalf("expected *BailianProvider, got %T", upstream)
	}

	var outcomes []runOutcome
	for _, c := range smoke.AllCases() {
		for i := 0; i < c.Repeats; i++ {
			out := runCase(t, bailian, c, i+1)
			outcomes = append(outcomes, out)
			logSafeOutcome(t, out, cfg.ModelAlias)
			if !out.Diag.EndToEndSuccess() {
				t.Errorf("%s run %d FAIL timeoutStage=%s dtoKind=%s dtoPath=%s missingKey=%s",
					c.Name, i+1, out.Diag.TimeoutStage, out.Diag.DTODecodeErrorKind, out.Diag.DTODecodeErrorPath, out.Diag.MissingKey)
			}
		}
	}

	printSummary(t, cfg, outcomes)
}

func runCase(
	t *testing.T,
	bailian *provider.BailianProvider,
	c smoke.SyntheticCase,
	runIndex int,
) runOutcome {
	t.Helper()
	env := c.Envelope
	env.RequestID = fmt.Sprintf("%s-run-%d", c.Name, runIndex)

	out := runOutcome{
		CaseName:  c.Name,
		RunIndex:  runIndex,
		RequestID: env.RequestID,
	}

	draft, diag, _ := bailian.DiagnoseMonthlySummary(context.Background(), env)
	if diag.DraftDTODecode != provider.StagePass {
		attachKeyFactValueSchemaMeta(&diag, env)
	}
	if diag.DraftDTODecode == provider.StagePass {
		enumValues := handler.ExtractEnumValues(draft)
		diag.KeyFactKinds = enumValues.KeyFactKinds
		diag.KeyFactValueTypes = enumValues.KeyFactValueTypes
		diag.WarningSeverities = enumValues.WarningSeverities
		diag.ActionDestinations = enumValues.ActionDestinations

		schema := handler.DiagnoseSchema(draft)
		if schema.Passed {
			diag.GatewaySchemaValidation = provider.StagePass
			factDiag := smoke.DiagnoseFacts(draft, env.MonthlySummaryFacts)
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
	}

	out.Diag = diag
	return out
}

func attachKeyFactValueSchemaMeta(diag *provider.DecodeDiagnostics, env contract.RequestEnvelope) {
	if env.MonthlySummaryFacts == nil {
		return
	}
	base, err := prompt.LoadAssistantAnswerModelDraftSchema()
	if err != nil {
		return
	}
	bound, err := prompt.BuildAssistantAnswerSchema(base, factpack.BuildKeySets(env.MonthlySummaryFacts), prompt.BuildExplanationSchemaKeys(env.FinancialRiskAssessment))
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

func logSafeOutcome(t *testing.T, out runOutcome, gatewayModelAlias string) {
	t.Helper()
	d := out.Diag
	t.Logf(
		"case=%s run=%d requestId=%s configuredModel=%s upstreamModel=%s gatewayModelAlias=%s httpStatus=%d httpSuccess=%t latencyMs=%d timeoutStage=%s upstreamHTTP=%s envelope=%s contentPresent=%s contentJSONValid=%t contentLength=%d genericJSON=%s topLevelKeys=%s unexpectedKeys=%s dtoDecode=%s dtoKind=%s dtoPath=%s missingKey=%s failingKeyFactIndex=%d failingKeyFactKind=%s keyFactValueJSONType=%s keyFactValueKeys=%s keyFactValueFieldTypes=%s keyFactValueSchemaMeta=%s schema=%s titleValid=%t bodyValid=%t answerValid=%t arraysValid=%t enumValid=%t keyFactKindValid=%t keyFactValueValid=%t warningSeverityValid=%t actionDestinationValid=%t invalidEnumField=%s invalidEnumValue=%s keyFactKinds=%s keyFactValueTypes=%s warningSeverities=%s actionDestinations=%s fact=%s amountFactsValid=%t citedFactKeysValid=%t keyFactSourcesValid=%t keyFactValuesValid=%t referencesValid=%t actionsValid=%t warningSourcesValid=%t percentFactsValid=%t dateFactsValid=%t factFailureRules=%s invalidFactRule=%s invalidFactKey=%s invalidFactSource=%s invented=%d invalidCited=%d invalidKeyFact=%d invalidRef=%d invalidAction=%d invalidWarningSource=%d promptTokens=%d completionTokens=%d totalTokens=%d",
		out.CaseName,
		out.RunIndex,
		out.RequestID,
		d.ConfiguredModel,
		d.UpstreamModel,
		gatewayModelAlias,
		d.HTTPStatus,
		d.HTTPSuccess,
		d.Latency.Milliseconds(),
		d.TimeoutStage,
		d.UpstreamHTTP,
		d.OpenAIEnvelopeDecode,
		d.ContentPresent,
		d.ContentJSONValid,
		d.ContentLength,
		d.GenericJSONObjectDecode,
		strings.Join(d.TopLevelKeys, ","),
		strings.Join(d.UnexpectedTopLevelKeys, ","),
		d.DraftDTODecode,
		d.DTODecodeErrorKind,
		d.DTODecodeErrorPath,
		d.MissingKey,
		d.FailingKeyFactIndex,
		d.FailingKeyFactKind,
		d.KeyFactValueJSONType,
		strings.Join(d.KeyFactValueKeys, ","),
		strings.Join(d.KeyFactValueFieldTypes, ","),
		d.KeyFactValueSchemaMeta,
		d.GatewaySchemaValidation,
		d.TitleValid,
		d.BodyValid,
		d.AnswerValid,
		d.ArraysValid,
		d.EnumValid,
		d.KeyFactKindValid,
		d.KeyFactValueValid,
		d.WarningSeverityValid,
		d.ActionDestinationValid,
		d.InvalidEnumField,
		d.InvalidEnumValue,
		strings.Join(d.KeyFactKinds, ","),
		strings.Join(d.KeyFactValueTypes, ","),
		strings.Join(d.WarningSeverities, ","),
		strings.Join(d.ActionDestinations, ","),
		d.FactValidation,
		d.AmountFactsValid,
		d.CitedFactKeysValid,
		d.KeyFactSourcesValid,
		d.KeyFactValuesValid,
		d.ReferencesValid,
		d.ActionsValid,
		d.WarningSourcesValid,
		d.PercentFactsValid,
		d.DateFactsValid,
		strings.Join(d.FactFailureRules, ","),
		d.InvalidFactRule,
		d.InvalidFactKey,
		d.InvalidFactSource,
		d.InventedFacts,
		d.InvalidCitedKeyCount,
		d.InvalidKeyFactCount,
		d.InvalidReferences,
		d.InvalidActions,
		d.InvalidWarningSources,
		d.PromptTokens,
		d.CompletionTokens,
		d.TotalTokens,
	)
}

func printSummary(t *testing.T, cfg config.Config, outcomes []runOutcome) {
	t.Helper()
	total := len(outcomes)
	httpOK, jsonOK, genericOK, dtoOK, schemaOK, factOK, e2eOK := 0, 0, 0, 0, 0, 0, 0
	timeoutCount, contractAmongHTTP, httpSuccessCount := 0, 0, 0
	var latencySum, minLat, maxLat time.Duration
	var promptSum, completionSum, tokenSum int
	inventedTotal, invalidRefTotal, invalidActionTotal, extraKeys := 0, 0, 0, 0

	casePass := map[string]bool{}
	for _, c := range smoke.AllCases() {
		casePass[c.Name] = true
	}

	for i, o := range outcomes {
		d := o.Diag
		if d.HTTPSuccess {
			httpOK++
			httpSuccessCount++
			if d.EndToEndSuccess() {
				contractAmongHTTP++
			}
		}
		if d.TimeoutStage == provider.TimeoutStageUpstreamHTTP {
			timeoutCount++
		}
		if d.ContentJSONValid {
			jsonOK++
		}
		if d.GenericJSONObjectDecode == provider.StagePass {
			genericOK++
		}
		if d.DraftDTODecode == provider.StagePass {
			dtoOK++
		}
		if d.GatewaySchemaValidation == provider.StagePass {
			schemaOK++
		}
		if d.FactValidation == provider.StagePass {
			factOK++
		}
		if d.EndToEndSuccess() {
			e2eOK++
		} else {
			casePass[o.CaseName] = false
		}
		latencySum += d.Latency
		if i == 0 || d.Latency < minLat {
			minLat = d.Latency
		}
		if d.Latency > maxLat {
			maxLat = d.Latency
		}
		promptSum += d.PromptTokens
		completionSum += d.CompletionTokens
		tokenSum += d.TotalTokens
		inventedTotal += d.InventedFacts
		invalidRefTotal += d.InvalidReferences
		invalidActionTotal += d.InvalidActions
		extraKeys += len(d.UnexpectedTopLevelKeys)
	}

	avgLatency := time.Duration(0)
	if total > 0 {
		avgLatency = latencySum / time.Duration(total)
	}

	t.Logf("=== P0-4.3I Live Smoke Summary configuredModel=%s upstreamModel=%s gatewayModelAlias=%s structuredOutputMode=%s ===",
		cfg.BailianModel,
		summaryUpstreamModel(outcomes),
		cfg.ModelAlias,
		cfg.BailianStructuredOutputMode,
	)
	for _, c := range smoke.AllCases() {
		status := "PASS"
		if !casePass[c.Name] {
			status = "FAIL"
		}
		t.Logf("%s: %s", c.Name, status)
	}
	t.Logf("httpSuccessRate=%d/%d contentJSONValidRate=%d/%d genericJSONDecodeRate=%d/%d draftDTODecodeRate=%d/%d schemaSuccessRate=%d/%d factSuccessRate=%d/%d endToEndSuccessRate=%d/%d contractSuccessRateAmongHTTPSuccesses=%d/%d overallEndToEndSuccessRate=%d/%d timeoutCount=%d minLatencyMs=%d maxLatencyMs=%d avgLatencyMs=%d inventedFacts=%d invalidReferences=%d invalidActions=%d extraTopLevelKeys=%d promptTokens=%d completionTokens=%d totalTokens=%d",
		httpOK, total, jsonOK, httpSuccessCount, genericOK, httpSuccessCount, dtoOK, httpSuccessCount, schemaOK, httpSuccessCount, factOK, httpSuccessCount, e2eOK, total, contractAmongHTTP, httpSuccessCount, e2eOK, total, timeoutCount,
		minLat.Milliseconds(), maxLat.Milliseconds(), avgLatency.Milliseconds(),
		inventedTotal, invalidRefTotal, invalidActionTotal, extraKeys,
		promptSum, completionSum, tokenSum,
	)
}

func summaryUpstreamModel(outcomes []runOutcome) string {
	for _, outcome := range outcomes {
		if model := strings.TrimSpace(outcome.Diag.UpstreamModel); model != "" {
			return model
		}
	}
	return ""
}
