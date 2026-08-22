package provider

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/youshu/youshu-ai-gateway/internal/config"
	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/factpack"
	"github.com/youshu/youshu-ai-gateway/internal/observability"
	"github.com/youshu/youshu-ai-gateway/internal/prompt"
)

// HTTPDoer performs HTTP requests (http.Client in production, httptest in tests).
type HTTPDoer interface {
	Do(req *http.Request) (*http.Response, error)
}

// BailianConfig holds Bailian / Model Studio credentials and endpoints.
type BailianConfig struct {
	APIKey               string
	BaseURL              string
	Model                string
	Timeout              time.Duration
	StructuredOutputMode string
	JSONSchema           json.RawMessage
	RetryPolicy          RetryPolicy
	Concurrency          *ConcurrencyLimiter
}

// BailianProvider calls Alibaba Cloud Model Studio OpenAI-compatible Chat Completions API.
type BailianProvider struct {
	config      BailianConfig
	client      HTTPDoer
	retryPolicy RetryPolicy
	concurrency *ConcurrencyLimiter
}

func NewBailianProvider(cfg BailianConfig, client HTTPDoer) *BailianProvider {
	if client == nil {
		client = &http.Client{Timeout: cfg.Timeout}
	}
	retry := cfg.RetryPolicy
	if retry.MaxRetries == 0 && retry.BaseDelay == 0 && retry.MaxDelay == 0 {
		retry = DefaultRetryPolicy(2, 500, 8000)
	}
	limiter := cfg.Concurrency
	if limiter == nil {
		limiter = NewConcurrencyLimiter(4)
	}
	return &BailianProvider{
		config:      cfg,
		client:      client,
		retryPolicy: retry,
		concurrency: limiter,
	}
}

func (p *BailianProvider) CompleteMonthlySummary(
	ctx context.Context,
	req contract.RequestEnvelope,
) (contract.AssistantAnswerDraftDTO, error) {
	draft, _, err := p.DiagnoseMonthlySummary(ctx, req)
	return draft, err
}

// DiagnoseMonthlySummary runs the upstream call and records stage-by-stage diagnostics.
// Production error mapping is unchanged; diagnostics remain available even when later stages fail.
func (p *BailianProvider) DiagnoseMonthlySummary(
	ctx context.Context,
	req contract.RequestEnvelope,
) (draft contract.AssistantAnswerDraftDTO, diag DecodeDiagnostics, err error) {
	started := time.Now()
	defer func() {
		diag.Latency = time.Since(started)
		recordProviderDiagnostics(ctx, p.config, diag)
	}()
	diag.ConfiguredModel = p.config.Model
	diag.SelectedProvider = "bailian"
	diag.GatewaySchemaValidation = StageSkip
	diag.FactValidation = StageSkip

	prompts, buildErr := prompt.BuildMonthlySummary(req)
	if buildErr != nil {
		diag.ErrorCategory = ErrorCategoryRequestConstruction
		diag.UpstreamHTTP = StageSkip
		fillSkippedDecode(&diag)
		err = annotateUpstream(upstreamErr(contract.ErrInternalError, buildErr), observability.StageUnknown, observability.CodeInternalError, "", "")
		return
	}

	endpoint, urlErr := chatCompletionsURL(p.config.BaseURL)
	if urlErr != nil {
		diag.ErrorCategory = ErrorCategoryRequestConstruction
		diag.UpstreamHTTP = StageSkip
		fillSkippedDecode(&diag)
		err = annotateUpstream(upstreamErr(contract.ErrInternalError, urlErr), observability.StageUnknown, observability.CodeInternalError, "", "")
		return
	}
	diag.RequestURLScheme, diag.RequestURLHost, diag.RequestURLPath = ParseRequestURLParts(endpoint)

	responseFormat, formatErr := p.buildResponseFormat(req)
	if formatErr != nil {
		diag.ErrorCategory = ErrorCategoryRequestConstruction
		diag.UpstreamHTTP = StageSkip
		fillSkippedDecode(&diag)
		err = annotateUpstream(upstreamErr(contract.ErrInternalError, formatErr), observability.StageUnknown, observability.CodeInternalError, "", "")
		return
	}

	body, marshalErr := json.Marshal(chatCompletionRequest{
		Model:          p.config.Model,
		Messages:       []chatMessage{{Role: "system", Content: prompts.System}, {Role: "user", Content: prompts.User}},
		ResponseFormat: responseFormat,
		EnableThinking: false,
	})
	if marshalErr != nil {
		diag.ErrorCategory = ErrorCategoryRequestConstruction
		diag.UpstreamHTTP = StageSkip
		fillSkippedDecode(&diag)
		err = annotateUpstream(upstreamErr(contract.ErrInternalError, marshalErr), observability.StageUnknown, observability.CodeInternalError, "", "")
		return
	}

	callCtx, cancel := context.WithTimeout(ctx, p.config.Timeout)
	defer cancel()

	if acquireErr := p.concurrency.Acquire(callCtx); acquireErr != nil {
		diag.ErrorCategory = ErrorCategoryTimeout
		diag.UpstreamHTTP = StageFail
		fillSkippedDecode(&diag)
		err = annotateUpstream(upstreamErr(contract.ErrProviderTimeout, acquireErr), observability.StageProviderTransport, observability.CodeProviderTimeout, "", "")
		return
	}
	defer p.concurrency.Release()

	tracker := &attemptTracker{}
	providerStarted := time.Now()
	respBody, resp, transportErr := p.performUpstreamHTTP(callCtx, endpoint, body, tracker)
	attempts, backoff := tracker.snapshot()
	diag.ProviderAttemptCount = attempts
	diag.ProviderTotalMs = time.Since(providerStarted)
	diag.BackoffMs = backoff

	if transportErr != nil {
		diag.UpstreamHTTP = StageFail
		fillSkippedDecode(&diag)
		if resp != nil {
			diag.TransportPerformStarted = true
			diag.HTTPResponseReceived = true
			diag.HTTPStatus = resp.StatusCode
			diag.HTTP2xxSuccess = false
			diag.HTTPSuccess = false
			diag.ErrorCategory = ClassifyHTTPStatus(resp.StatusCode)
			diag.ProviderErrorCode, diag.ProviderErrorMessage = ExtractProviderError(respBody)
			obsCode, stage := classifyProviderHTTP(resp.StatusCode)
			err = annotateUpstream(transportErr, stage, obsCode, "", strconv.Itoa(resp.StatusCode))
			return
		}
		diag.ErrorCategory = ClassifyDoError(transportErr)
		if errors.Is(transportErr, context.DeadlineExceeded) || callCtx.Err() == context.DeadlineExceeded {
			diag.TimeoutStage = TimeoutStageUpstreamHTTP
			diag.ErrorCategory = ErrorCategoryTimeout
			err = annotateUpstream(transportErr, observability.StageProviderTransport, observability.CodeProviderTimeout, "", "")
			return
		}
		err = annotateUpstream(transportErr, observability.StageProviderTransport, observability.CodeTransportFailure, "", "")
		return
	}

	diag.TransportPerformStarted = true
	diag.HTTPResponseReceived = true
	diag.HTTPStatus = resp.StatusCode
	diag.HTTP2xxSuccess = httpSuccessStatus(resp.StatusCode)
	diag.HTTPSuccess = diag.HTTP2xxSuccess
	if diag.HTTPSuccess {
		diag.UpstreamHTTP = StagePass
	} else {
		diag.UpstreamHTTP = StageFail
		diag.ErrorCategory = ClassifyHTTPStatus(resp.StatusCode)
	}

	if statusErr := mapHTTPStatus(resp.StatusCode, respBody, nil); statusErr != nil {
		diag.ProviderErrorCode, diag.ProviderErrorMessage = ExtractProviderError(respBody)
		if diag.ErrorCategory == "" {
			diag.ErrorCategory = ClassifyHTTPStatus(resp.StatusCode)
		}
		fillSkippedDecode(&diag)
		obsCode, stage := classifyProviderHTTP(resp.StatusCode)
		err = annotateUpstream(statusErr, stage, obsCode, "", strconv.Itoa(resp.StatusCode))
		return
	}

	var completion chatCompletionResponse
	if unmarshalErr := json.Unmarshal(respBody, &completion); unmarshalErr != nil {
		diag.OpenAIEnvelopeDecode = StageFail
		diag.ContentPresent = StageSkip
		diag.ContentJSONSyntax = StageSkip
		diag.GenericJSONObjectDecode = StageSkip
		diag.DraftDTODecode = StageSkip
		err = annotateUpstream(
			upstreamErr(contract.ErrInvalidProviderResponse, unmarshalErr),
			observability.StageProviderStructuredOutput,
			observability.CodeStructuredOutputDecodeFailure,
			observability.SchemaModelDraft,
			strconv.Itoa(resp.StatusCode),
		)
		return
	}
	diag.OpenAIEnvelopeDecode = StagePass
	diag.UpstreamModel = strings.TrimSpace(completion.Model)
	applyUsage(&diag, completion.Usage)

	content := strings.TrimSpace(completion.firstContent())
	maybeDumpRawContent(req.RequestID, content)

	analyzed, contentDiag := AnalyzeContent(content, req.FinancialRiskAssessment, req.MonthlySummaryFacts)
	mergeContentDiagnostics(&diag, contentDiag)

	if diag.FactMaterialization == StageFail {
		err = materializationErrorFromDiag(diag)
		return
	}
	if diag.DraftDTODecode != StagePass {
		err = structuredOutputError(diag)
		return
	}
	if diag.ProvenanceAssembly == StageFail {
		err = annotateUpstream(
			upstreamErr(contract.ErrInvalidProviderResponse, nil),
			observability.StageProviderStructuredOutput,
			observability.CodeInvalidProviderResponse,
			observability.SchemaGatewayDraft,
			strconv.Itoa(resp.StatusCode),
		)
		return
	}
	draft = analyzed
	return
}

func fillSkippedDecode(diag *DecodeDiagnostics) {
	if diag.OpenAIEnvelopeDecode == "" {
		diag.OpenAIEnvelopeDecode = StageSkip
	}
	if diag.ContentPresent == "" {
		diag.ContentPresent = StageSkip
	}
	if diag.ContentJSONSyntax == "" {
		diag.ContentJSONSyntax = StageSkip
	}
	if diag.GenericJSONObjectDecode == "" {
		diag.GenericJSONObjectDecode = StageSkip
	}
	if diag.DraftDTODecode == "" {
		diag.DraftDTODecode = StageSkip
	}
	if diag.ExplanationAlignment == "" {
		diag.ExplanationAlignment = StageSkip
	}
	if diag.ProvenanceAssembly == "" {
		diag.ProvenanceAssembly = StageSkip
	}
	if diag.FactMaterialization == "" {
		diag.FactMaterialization = StageSkip
	}
}

func isTimeoutErr(err error) bool {
	if err == nil {
		return false
	}
	var netErr interface{ Timeout() bool }
	if errors.As(err, &netErr) && netErr.Timeout() {
		return true
	}
	return strings.Contains(strings.ToLower(err.Error()), "timeout")
}

func mapHTTPStatus(status int, body []byte, header http.Header) error {
	switch status {
	case http.StatusOK:
		return nil
	case http.StatusUnauthorized, http.StatusForbidden:
		return upstreamErr(contract.ErrProviderUnavailable, fmt.Errorf("upstream auth failed"))
	case http.StatusTooManyRequests:
		retry := mergeRetryAfter(parseRetryAfterHeader(header), body)
		if retry != nil {
			return upstreamErrRetry(contract.ErrProviderRateLimited, retry.Seconds, fmt.Errorf("upstream rate limited"))
		}
		return upstreamErr(contract.ErrProviderRateLimited, fmt.Errorf("upstream rate limited"))
	case http.StatusGatewayTimeout:
		return upstreamErr(contract.ErrProviderTimeout, fmt.Errorf("upstream timeout"))
	default:
		if status >= 500 {
			return upstreamErr(contract.ErrProviderUnavailable, fmt.Errorf("upstream status %d", status))
		}
		return upstreamErr(contract.ErrInvalidProviderResponse, fmt.Errorf("upstream status %d", status))
	}
}

func parseRetryAfter(body []byte) *int {
	var generic map[string]any
	if err := json.Unmarshal(body, &generic); err != nil {
		return nil
	}
	if v, ok := generic["retry_after"].(float64); ok {
		n := int(v)
		return &n
	}
	return nil
}

func chatCompletionsURL(baseURL string) (string, error) {
	trimmed := strings.TrimSpace(baseURL)
	if trimmed == "" {
		return "", fmt.Errorf("empty base URL")
	}
	u, err := url.Parse(trimmed)
	if err != nil {
		return "", err
	}
	path := strings.TrimSuffix(u.Path, "/")
	if strings.HasSuffix(path, "/chat/completions") {
		return u.String(), nil
	}
	if path == "" || path == "/" {
		u.Path = "/chat/completions"
	} else {
		u.Path = path + "/chat/completions"
	}
	return u.String(), nil
}

func applyUsage(diag *DecodeDiagnostics, usage *tokenUsage) {
	if diag == nil || usage == nil {
		return
	}
	diag.UsagePresent = true
	diag.PromptTokensPtr = usage.PromptTokens
	diag.CompletionTokensPtr = usage.CompletionTokens
	diag.TotalTokensPtr = usage.TotalTokens
	if usage.PromptTokens != nil {
		diag.PromptTokens = *usage.PromptTokens
	}
	if usage.CompletionTokens != nil {
		diag.CompletionTokens = *usage.CompletionTokens
	}
	if usage.TotalTokens != nil {
		diag.TotalTokens = *usage.TotalTokens
	}
}

type chatCompletionRequest struct {
	Model          string          `json:"model"`
	Messages       []chatMessage   `json:"messages"`
	ResponseFormat *responseFormat `json:"response_format,omitempty"`
	EnableThinking bool            `json:"enable_thinking"`
}

type chatMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type responseFormat struct {
	Type       string          `json:"type"`
	JSONSchema *jsonSchemaSpec `json:"json_schema,omitempty"`
}

type jsonSchemaSpec struct {
	Name   string          `json:"name"`
	Strict bool            `json:"strict"`
	Schema json.RawMessage `json:"schema"`
}

func (p *BailianProvider) buildResponseFormat(req contract.RequestEnvelope) (*responseFormat, error) {
	mode := p.config.StructuredOutputMode
	if mode == "" || mode == config.StructuredOutputJSONObject {
		return &responseFormat{Type: "json_object"}, nil
	}
	if mode == config.StructuredOutputJSONSchemaStrict {
		if req.MonthlySummaryFacts == nil {
			return nil, fmt.Errorf("missing monthlySummaryFacts for json_schema_strict")
		}
		keySets := factpack.BuildKeySetsForRequest(req.MonthlySummaryFacts, req.FinancialRiskAssessment)
		explanation := prompt.BuildExplanationSchemaKeys(req.FinancialRiskAssessment)
		schema, err := prompt.BuildAssistantAnswerSchema(p.config.JSONSchema, keySets, explanation)
		if err != nil {
			return nil, err
		}
		return &responseFormat{
			Type: "json_schema",
			JSONSchema: &jsonSchemaSpec{
				Name:   prompt.AssistantAnswerModelDraftSchemaName,
				Strict: true,
				Schema: schema,
			},
		}, nil
	}
	return &responseFormat{Type: "json_object"}, nil
}

type chatCompletionResponse struct {
	Model   string `json:"model"`
	Choices []struct {
		Message struct {
			Content string `json:"content"`
		} `json:"message"`
	} `json:"choices"`
	Usage *tokenUsage `json:"usage"`
}

type tokenUsage struct {
	PromptTokens     *int `json:"prompt_tokens"`
	CompletionTokens *int `json:"completion_tokens"`
	TotalTokens      *int `json:"total_tokens"`
}

func (r chatCompletionResponse) firstContent() string {
	if len(r.Choices) == 0 {
		return ""
	}
	return r.Choices[0].Message.Content
}
