package provider

import (
	"context"
	"strconv"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/factpack"
	"github.com/youshu/youshu-ai-gateway/internal/observability"
)

func recordProviderDiagnostics(ctx context.Context, cfg BailianConfig, diag DecodeDiagnostics) {
	rec := observability.FromContext(ctx)
	if rec == nil {
		return
	}
	model := diag.UpstreamModel
	if model == "" {
		model = cfg.Model
	}
	rec.SetProvider(observability.ProviderBailian, model)
	rec.SetRetryCount(observability.RetryCountFromAttempts(diag.ProviderAttemptCount))
	if diag.HTTPStatus > 0 {
		rec.SetProviderStatus(strconv.Itoa(diag.HTTPStatus))
	}
	if diag.UsagePresent {
		rec.SetTokens(diag.PromptTokensPtr, diag.CompletionTokensPtr, diag.TotalTokensPtr)
	}
}

func classifyProviderHTTP(status int) (obsCode, stage string) {
	stage = observability.StageProviderHTTP
	switch status {
	case 429:
		return observability.CodeProviderRateLimited, stage
	case 408, 504:
		return observability.CodeProviderTimeout, stage
	default:
		if status >= 500 {
			return observability.CodeProviderUnavailable, stage
		}
		if status == 401 || status == 403 {
			// HTTP contract stays providerUnavailable (retryable on iOS).
			return observability.CodeProviderUnavailable, stage
		}
		if status >= 400 {
			return observability.CodeProviderRejectedRequest, stage
		}
		return observability.CodeInvalidProviderResponse, stage
	}
}

func structuredOutputError(diag DecodeDiagnostics) error {
	schemaStage := observability.SchemaModelDraft
	if diag.OpenAIEnvelopeDecode == StageFail {
		schemaStage = observability.SchemaModelDraft
	}
	return annotateUpstream(
		upstreamErr(contract.ErrInvalidProviderResponse, nil),
		observability.StageProviderStructuredOutput,
		observability.CodeStructuredOutputDecodeFailure,
		schemaStage,
		statusOrEmpty(diag.HTTPStatus),
	)
}

func materializationErrorFromDiag(diag DecodeDiagnostics) error {
	code := diag.MaterializationCode
	if code == "" {
		code = factpack.CodeMaterializationFailure
	}
	return annotateUpstream(
		upstreamErr(contract.ErrInvalidProviderResponse, nil),
		observability.StageFactMaterialization,
		code,
		"",
		statusOrEmpty(diag.HTTPStatus),
	)
}

func statusOrEmpty(status int) string {
	if status <= 0 {
		return ""
	}
	return strconv.Itoa(status)
}
