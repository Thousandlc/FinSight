package eval

import (
	"context"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/provider"
)

// FixtureTransportUpstream simulates provider transport outcomes for offline eval tests.
type FixtureTransportUpstream struct {
	Handler func(req contract.RequestEnvelope) (contract.AssistantAnswerDraftDTO, provider.DecodeDiagnostics, error)
}

func (f *FixtureTransportUpstream) DiagnoseMonthlySummary(
	ctx context.Context,
	req contract.RequestEnvelope,
) (contract.AssistantAnswerDraftDTO, provider.DecodeDiagnostics, error) {
	if f.Handler != nil {
		return f.Handler(req)
	}
	return contract.AssistantAnswerDraftDTO{}, provider.DecodeDiagnostics{}, nil
}

func transportFailureDiag(category string, status int, code, message, host, path string) provider.DecodeDiagnostics {
	diag := provider.DecodeDiagnostics{
		SelectedProvider:        "fixture-transport",
		RequestBuilt:            true,
		TransportPerformStarted: true,
		HTTPResponseReceived:    status > 0,
		HTTPStatus:              status,
		HTTP2xxSuccess:          status >= 200 && status <= 299,
		HTTPSuccess:             status >= 200 && status <= 299,
		ErrorCategory:           category,
		ProviderErrorCode:       code,
		ProviderErrorMessage:    message,
		RequestURLScheme:        "https",
		RequestURLHost:          host,
		RequestURLPath:          path,
		UpstreamHTTP:            provider.StageFail,
	}
	if diag.HTTP2xxSuccess {
		diag.UpstreamHTTP = provider.StagePass
	}
	diag.OpenAIEnvelopeDecode = provider.StageSkip
	diag.ContentPresent = provider.StageSkip
	diag.ContentJSONSyntax = provider.StageSkip
	diag.GenericJSONObjectDecode = provider.StageSkip
	diag.DraftDTODecode = provider.StageSkip
	diag.ExplanationAlignment = provider.StageSkip
	diag.GatewaySchemaValidation = provider.StageSkip
	diag.FactValidation = provider.StageSkip
	return diag
}

func connectionFailureDiag() provider.DecodeDiagnostics {
	diag := transportFailureDiag(provider.ErrorCategoryConnection, 0, "", "", "api.example.test", "/chat/completions")
	diag.HTTPResponseReceived = false
	return diag
}

func httpStatusFailureDiag(status int, category, code, message string) provider.DecodeDiagnostics {
	return transportFailureDiag(category, status, code, message, "dashscope.aliyuncs.com", "/compatible-mode/v1/chat/completions")
}

func timeoutFailureDiag() provider.DecodeDiagnostics {
	diag := connectionFailureDiag()
	diag.ErrorCategory = provider.ErrorCategoryTimeout
	diag.TimeoutStage = provider.TimeoutStageUpstreamHTTP
	return diag
}

func buildAllTransportFailureResults(caseIDs []string, repeats int, diag provider.DecodeDiagnostics) []RunResult {
	var results []RunResult
	mode := EvaluationModeExplanationAlignmentV2
	for _, caseID := range caseIDs {
		c, err := findCaseByID(caseID)
		if err != nil {
			continue
		}
		for run := 1; run <= repeats; run++ {
			env := c.Envelope
			env.RequestID = c.ID + "-transport-test"
			upstream := &FixtureTransportUpstream{
				Handler: func(contract.RequestEnvelope) (contract.AssistantAnswerDraftDTO, provider.DecodeDiagnostics, error) {
					return contract.AssistantAnswerDraftDTO{}, diag, providerUpstreamErr()
				},
			}
			results = append(results, executeRun(context.Background(), upstream, c, run, mode))
		}
	}
	return results
}

func providerUpstreamErr() error {
	return &provider.UpstreamError{Code: contract.ErrProviderUnavailable}
}
