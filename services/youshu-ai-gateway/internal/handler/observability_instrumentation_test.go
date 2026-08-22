package handler_test

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"log"
	"math"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/factpack"
	"github.com/youshu/youshu-ai-gateway/internal/handler"
	"github.com/youshu/youshu-ai-gateway/internal/middleware"
	"github.com/youshu/youshu-ai-gateway/internal/observability"
	"github.com/youshu/youshu-ai-gateway/internal/provider"
)

const (
	canaryFinancial = "FINANCIAL_CONTEXT_SECRET_CANARY"
	canaryPrompt    = "QUESTION_SECRET_CANARY"
	canaryAuth      = "AUTH_SECRET_CANARY"
	canaryProvider  = "RAW_PROVIDER_RESPONSE_CANARY"
	canaryMerchant  = "MERCHANT_SECRET_CANARY"
	canaryNote      = "NOTE_SECRET_CANARY"
	canaryToken     = "CLIENT_TOKEN_SECRET_CANARY"
	canaryAmount    = "MATERIALIZED_AMOUNT_CANARY"
	canaryValidator = "VALIDATOR_AMOUNT_CANARY"
	canarySource    = "SOURCE_ID_CANARY"
)

type stubUpstream struct {
	draft contract.AssistantAnswerDraftDTO
	err   error
}

func (s stubUpstream) CompleteMonthlySummary(_ context.Context, _ contract.RequestEnvelope) (contract.AssistantAnswerDraftDTO, error) {
	return s.draft, s.err
}

type timeoutDoer struct{}

func (timeoutDoer) Do(*http.Request) (*http.Response, error) {
	return nil, context.DeadlineExceeded
}

type transportDoer struct{}

func (transportDoer) Do(*http.Request) (*http.Response, error) {
	return nil, &net.OpError{Op: "dial", Net: "tcp", Err: errors.New("connection refused")}
}

func captureAIRequests(t *testing.T) (*[]observability.Entry, *bytes.Buffer, func()) {
	t.Helper()
	var events []observability.Entry
	restoreSink := observability.SetSinkForTest(func(entry observability.Entry) {
		if entry.Event == observability.EventAIRequest {
			events = append(events, entry)
		}
	})
	var buf bytes.Buffer
	log.SetOutput(&buf)
	restore := func() {
		restoreSink()
		log.SetOutput(os.Stderr)
	}
	t.Cleanup(restore)
	return &events, &buf, restore
}

func productionStack(t *testing.T, upstream provider.UpstreamAIProvider, token string, limit int) http.Handler {
	t.Helper()
	h := &handler.FinancialAssistantHandler{
		SchemaVersion: "v1",
		ModelAlias:    "test-model",
		Upstream:      upstream,
	}
	limiter := middleware.NewFixedWindowRateLimiter(middleware.RateLimitOptions{
		Limit:  limit,
		Window: time.Minute,
	})
	return middleware.WrapFinancialAssistant("test-gateway", token, limiter, h)
}

func lastEvent(t *testing.T, events *[]observability.Entry) observability.Entry {
	t.Helper()
	if events == nil || len(*events) == 0 {
		t.Fatal("expected ai_request event")
	}
	return (*events)[len(*events)-1]
}

func postAssistant(h http.Handler, body []byte, requestID, token string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(http.MethodPost, "/v1/ai/financial-assistant", bytes.NewReader(body))
	if requestID != "" {
		req.Header.Set("X-Youshu-Request-Id", requestID)
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func canaryRequest() contract.RequestEnvelope {
	req := sampleRequest()
	req.RequestID = "11111111-1111-4111-8111-111111111111"
	req.AssistantRequest.Question = canaryPrompt + " " + canaryMerchant + " " + canaryNote
	req.MonthlySummaryFacts.AvailableCash.Amount = "1000"
	req.MonthlySummaryFacts.PrimaryPressure = canaryFinancial
	return req
}

func assertNoCanaries(t *testing.T, texts ...string) {
	t.Helper()
	for _, text := range texts {
		for _, canary := range []string{
			canaryFinancial, canaryPrompt, canaryAuth, canaryProvider,
			canaryMerchant, canaryNote, canaryToken, canaryAmount, canaryValidator, canarySource,
		} {
			if strings.Contains(text, canary) {
				t.Fatalf("canary %s leaked: %s", canary, text)
			}
		}
	}
}

func TestObservabilitySuccess(t *testing.T) {
	events, logs, _ := captureAIRequests(t)
	h := productionStack(t, provider.NewMockUpstreamAIProvider(), "", 100)
	body, _ := json.Marshal(canaryRequest())
	rec := postAssistant(h, body, "11111111-1111-4111-8111-111111111111", "")
	if rec.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", rec.Code, rec.Body.String())
	}
	got := lastEvent(t, events)
	if got.Outcome != observability.OutcomeSuccess {
		t.Fatalf("outcome=%s", got.Outcome)
	}
	if got.RequestID != "11111111-1111-4111-8111-111111111111" {
		t.Fatalf("requestId=%s", got.RequestID)
	}
	if got.DurationMs < 0 {
		t.Fatalf("duration=%d", got.DurationMs)
	}
	if got.RetryCount == nil || *got.RetryCount != 0 {
		t.Fatalf("retryCount=%v", got.RetryCount)
	}
	if got.FailureStage != "" || got.ErrorCode != "" {
		t.Fatalf("failure fields present: %+v", got)
	}
	if got.CostSource != "" {
		t.Fatal("cost must stay absent")
	}
	payload, _ := json.Marshal(got)
	assertNoCanaries(t, string(payload), logs.String())
}

func TestObservabilityAuthFailure(t *testing.T) {
	events, logs, _ := captureAIRequests(t)
	h := productionStack(t, provider.NewMockUpstreamAIProvider(), "expected-token", 100)
	body, _ := json.Marshal(canaryRequest())
	rec := postAssistant(h, body, "req-auth-1", canaryAuth)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status=%d", rec.Code)
	}
	got := lastEvent(t, events)
	if got.FailureStage != observability.StageGatewayAuth || got.ErrorCode != observability.CodeUnauthorized {
		t.Fatalf("event=%+v", got)
	}
	if got.FailureClass != observability.ClassSecurity || got.Retryability != observability.NotRetryable {
		t.Fatalf("class=%s retry=%s", got.FailureClass, got.Retryability)
	}
	payload, _ := json.Marshal(got)
	assertNoCanaries(t, string(payload), logs.String(), rec.Body.String())
}

func TestObservabilityRequestValidation(t *testing.T) {
	events, logs, _ := captureAIRequests(t)
	h := productionStack(t, provider.NewMockUpstreamAIProvider(), "", 100)
	raw := []byte(`{"schemaVersion":"v1","requestId":"req-bad","operation":"monthlySummary","PROMPT_SECRET_CANARY":true`)
	rec := postAssistant(h, raw, "req-bad", "")
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status=%d", rec.Code)
	}
	got := lastEvent(t, events)
	if got.FailureStage != observability.StageGatewayRequestValidation {
		t.Fatalf("stage=%s", got.FailureStage)
	}
	if got.ErrorCode != observability.CodeInvalidRequest {
		t.Fatalf("code=%s", got.ErrorCode)
	}
	payload, _ := json.Marshal(got)
	assertNoCanaries(t, string(payload), logs.String())
}

func TestObservabilityProviderTimeoutAndTransport(t *testing.T) {
	events, _, _ := captureAIRequests(t)
	timeoutProvider := provider.NewBailianProvider(provider.BailianConfig{
		APIKey:  "k",
		BaseURL: "http://127.0.0.1",
		Model:   "qwen-plus",
		Timeout: time.Second,
	}, timeoutDoer{})
	h := productionStack(t, timeoutProvider, "", 100)
	body, _ := json.Marshal(sampleRequest())
	rec := postAssistant(h, body, "req-timeout", "")
	if rec.Code != http.StatusGatewayTimeout {
		t.Fatalf("timeout status=%d", rec.Code)
	}
	got := lastEvent(t, events)
	if got.FailureStage != observability.StageProviderTransport || got.ErrorCode != observability.CodeProviderTimeout {
		t.Fatalf("timeout event=%+v", got)
	}
	if got.Retryability != observability.Retryable {
		t.Fatalf("timeout retryability=%s", got.Retryability)
	}

	transportProvider := provider.NewBailianProvider(provider.BailianConfig{
		APIKey:  "k",
		BaseURL: "http://127.0.0.1",
		Model:   "qwen-plus",
		Timeout: time.Second,
	}, transportDoer{})
	h = productionStack(t, transportProvider, "", 100)
	rec = postAssistant(h, body, "req-transport", "")
	got = lastEvent(t, events)
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("transport status=%d", rec.Code)
	}
	if got.FailureStage != observability.StageProviderTransport || got.ErrorCode != observability.CodeTransportFailure {
		t.Fatalf("transport event=%+v", got)
	}
	if got.Retryability != observability.NotRetryable {
		t.Fatalf("transportFailure retryability=%s", got.Retryability)
	}
}

func TestObservabilityProviderHTTPFailures(t *testing.T) {
	events, logs, _ := captureAIRequests(t)
	cases := []struct {
		status   int
		wantCode string
		retry    string
	}{
		{http.StatusTooManyRequests, observability.CodeProviderRateLimited, observability.NotRetryable},
		{http.StatusServiceUnavailable, observability.CodeProviderUnavailable, observability.Retryable},
		{http.StatusBadRequest, observability.CodeProviderRejectedRequest, observability.NotRetryable},
	}
	body, _ := json.Marshal(sampleRequest())
	for _, tc := range cases {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			w.WriteHeader(tc.status)
			_, _ = w.Write([]byte(`{"error":{"message":"` + canaryProvider + `"}}`))
		}))
		p := provider.NewBailianProvider(provider.BailianConfig{
			APIKey:  "k",
			BaseURL: server.URL,
			Model:   "qwen-plus",
			Timeout: time.Second,
			RetryPolicy: provider.RetryPolicy{
				MaxRetries: 0,
				BaseDelay:  time.Millisecond,
				MaxDelay:   time.Millisecond,
				Sleep:      func(context.Context, time.Duration) error { return nil },
			},
		}, server.Client())
		h := productionStack(t, p, "", 100)
		rec := postAssistant(h, body, "req-http", "")
		got := lastEvent(t, events)
		if got.FailureStage != observability.StageProviderHTTP {
			t.Fatalf("status %d stage=%s", tc.status, got.FailureStage)
		}
		if got.ErrorCode != tc.wantCode {
			t.Fatalf("status %d code=%s want=%s http=%d", tc.status, got.ErrorCode, tc.wantCode, rec.Code)
		}
		if got.Retryability != tc.retry {
			t.Fatalf("status %d retryability=%s", tc.status, got.Retryability)
		}
		if got.ProviderStatus != "" && got.ProviderStatus != "429" && got.ProviderStatus != "503" && got.ProviderStatus != "400" {
			t.Fatalf("providerStatus=%s", got.ProviderStatus)
		}
		payload, _ := json.Marshal(got)
		assertNoCanaries(t, string(payload), logs.String(), rec.Body.String())
		server.Close()
	}
}

func TestObservabilityStructuredOutputFailure(t *testing.T) {
	events, logs, _ := captureAIRequests(t)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"` + canaryProvider + `"}}],"usage":{"prompt_tokens":9,"completion_tokens":3,"total_tokens":12}}`))
	}))
	t.Cleanup(server.Close)
	p := provider.NewBailianProvider(provider.BailianConfig{
		APIKey:  "k",
		BaseURL: server.URL,
		Model:   "qwen-plus",
		Timeout: time.Second,
		RetryPolicy: provider.RetryPolicy{
			MaxRetries: 0,
			Sleep:      func(context.Context, time.Duration) error { return nil },
		},
	}, server.Client())
	h := productionStack(t, p, "", 100)
	body, _ := json.Marshal(sampleRequest())
	rec := postAssistant(h, body, "req-struct", "")
	got := lastEvent(t, events)
	if rec.Code != http.StatusBadGateway {
		t.Fatalf("status=%d", rec.Code)
	}
	if got.FailureStage != observability.StageProviderStructuredOutput {
		t.Fatalf("stage=%s", got.FailureStage)
	}
	if got.ErrorCode != observability.CodeStructuredOutputDecodeFailure {
		t.Fatalf("code=%s", got.ErrorCode)
	}
	if got.SchemaStage != observability.SchemaModelDraft {
		t.Fatalf("schemaStage=%s", got.SchemaStage)
	}
	if got.PromptTokens == nil || *got.PromptTokens != 9 {
		t.Fatalf("tokens=%v", got.PromptTokens)
	}
	payload, _ := json.Marshal(got)
	assertNoCanaries(t, string(payload), logs.String())
}

func TestObservabilityFactMaterialization(t *testing.T) {
	events, logs, _ := captureAIRequests(t)
	h := productionStack(t, stubUpstream{err: &factpack.MaterializationError{Code: factpack.CodeUnknownFactSource}}, "", 100)
	req := canaryRequest()
	req.MonthlySummaryFacts.AvailableCash.Amount = canaryFinancial
	body, _ := json.Marshal(req)
	rec := postAssistant(h, body, req.RequestID, "")
	got := lastEvent(t, events)
	if rec.Code != http.StatusBadGateway {
		t.Fatalf("status=%d", rec.Code)
	}
	if got.FailureStage != observability.StageFactMaterialization {
		t.Fatalf("stage=%s", got.FailureStage)
	}
	if got.ErrorCode != observability.CodeUnknownFactSource {
		t.Fatalf("code=%s", got.ErrorCode)
	}
	payload, _ := json.Marshal(got)
	assertNoCanaries(t, string(payload), logs.String(), rec.Body.String())

	h = productionStack(t, provider.NewMockUpstreamAIProvider(), "", 100)
	req = canaryRequest()
	req.MonthlySummaryFacts.AvailableCash.Amount = canaryFinancial
	body, _ = json.Marshal(req)
	rec = postAssistant(h, body, req.RequestID, "")
	got = lastEvent(t, events)
	if got.FailureStage != observability.StageFactMaterialization {
		t.Fatalf("mock materialization stage=%s code=%s body=%s", got.FailureStage, got.ErrorCode, rec.Body.String())
	}
	if got.ErrorCode != observability.CodeMaterializationFailure {
		t.Fatalf("code=%s", got.ErrorCode)
	}
	payload, _ = json.Marshal(got)
	assertNoCanaries(t, string(payload), logs.String())
}

func TestObservabilityResponseEncoding(t *testing.T) {
	events, _, _ := captureAIRequests(t)
	base, err := provider.NewMockUpstreamAIProvider().CompleteMonthlySummary(context.Background(), sampleRequest())
	if err != nil {
		t.Fatal(err)
	}
	base.Confidence = math.NaN()
	h := productionStack(t, stubUpstream{draft: base}, "", 100)
	body, _ := json.Marshal(sampleRequest())
	rec := postAssistant(h, body, "req-encode", "")
	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("status=%d body=%s", rec.Code, rec.Body.String())
	}
	got := lastEvent(t, events)
	if got.FailureStage != observability.StageGatewayResponseEncoding {
		t.Fatalf("stage=%s", got.FailureStage)
	}
	if got.ErrorCode != observability.CodeSerializationFailure {
		t.Fatalf("code=%s", got.ErrorCode)
	}
}

func TestObservabilityTokenUsageVariants(t *testing.T) {
	events, _, _ := captureAIRequests(t)
	usages := []string{
		`{"prompt_tokens":11,"completion_tokens":7,"total_tokens":18}`,
		`{"prompt_tokens":4}`,
		`{}`,
	}
	draft := `{
		"title": "本月财务摘要",
		"body": "摘要",
		"answer": "摘要",
		"citedFactKeys": ["availableCash"],
		"confidence": 0.8,
		"keyFacts": [{"label": "可用资金", "kind": "balance", "source": "availableCash"}],
		"references": [{"key": "availableCash"}],
		"riskExplanations": [],
		"unknownExplanations": []
	}`
	body, _ := json.Marshal(sampleRequest())
	for i, usage := range usages {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			payload := `{"choices":[{"message":{"content":` + jsonQuote(draft) + `}}],"model":"qwen-plus"`
			if i < 2 || usage != "" {
				payload += `,"usage":` + usage
			}
			payload += `}`
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write([]byte(payload))
		}))
		p := provider.NewBailianProvider(provider.BailianConfig{
			APIKey:      "k",
			BaseURL:     server.URL,
			Model:       "qwen-plus",
			Timeout:     time.Second,
			RetryPolicy: provider.RetryPolicy{MaxRetries: 0, Sleep: func(context.Context, time.Duration) error { return nil }},
		}, server.Client())
		h := productionStack(t, p, "", 100)
		rec := postAssistant(h, body, "req-tokens", "")
		if rec.Code != http.StatusOK {
			t.Fatalf("usage %q status=%d body=%s", usage, rec.Code, rec.Body.String())
		}
		got := lastEvent(t, events)
		if got.CostSource != "" {
			t.Fatal("cost must stay absent")
		}
		if i == 0 {
			if got.PromptTokens == nil || *got.PromptTokens != 11 || got.CompletionTokens == nil || *got.CompletionTokens != 7 || got.TotalTokens == nil || *got.TotalTokens != 18 {
				t.Fatalf("full usage=%+v", got)
			}
		}
		if i == 1 {
			if got.PromptTokens == nil || *got.PromptTokens != 4 {
				t.Fatalf("partial usage prompt=%v", got.PromptTokens)
			}
			if got.CompletionTokens != nil || got.TotalTokens != nil {
				t.Fatalf("partial should omit unset tokens: %+v", got)
			}
		}
		if i == 2 {
			if got.PromptTokens != nil || got.CompletionTokens != nil || got.TotalTokens != nil {
				t.Fatalf("empty usage object should not synthesize tokens: %+v", got)
			}
		}
		server.Close()
	}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":` + jsonQuote(draft) + `}}]}`))
	}))
	t.Cleanup(server.Close)
	p := provider.NewBailianProvider(provider.BailianConfig{
		APIKey:      "k",
		BaseURL:     server.URL,
		Model:       "qwen-plus",
		Timeout:     time.Second,
		RetryPolicy: provider.RetryPolicy{MaxRetries: 0, Sleep: func(context.Context, time.Duration) error { return nil }},
	}, server.Client())
	h := productionStack(t, p, "", 100)
	if rec := postAssistant(h, body, "req-missing-usage", ""); rec.Code != http.StatusOK {
		t.Fatalf("missing usage status=%d", rec.Code)
	}
	got := lastEvent(t, events)
	if got.PromptTokens != nil || got.TotalTokens != nil {
		t.Fatalf("missing usage leaked tokens=%+v", got)
	}
	if got.CostSource != "" {
		t.Fatal("cost must stay absent")
	}
}

func TestObservabilityZeroTokensAreEmitted(t *testing.T) {
	events, _, _ := captureAIRequests(t)
	draft := `{
		"title": "本月财务摘要",
		"body": "摘要",
		"answer": "摘要",
		"citedFactKeys": ["availableCash"],
		"confidence": 0.8,
		"keyFacts": [{"label": "可用资金", "kind": "balance", "source": "availableCash"}],
		"references": [{"key": "availableCash"}],
		"riskExplanations": [],
		"unknownExplanations": []
	}`
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":` + jsonQuote(draft) + `}}],"usage":{"prompt_tokens":0,"completion_tokens":0,"total_tokens":0}}`))
	}))
	t.Cleanup(server.Close)
	p := provider.NewBailianProvider(provider.BailianConfig{
		APIKey:      "k",
		BaseURL:     server.URL,
		Model:       "qwen-plus",
		Timeout:     time.Second,
		RetryPolicy: provider.RetryPolicy{MaxRetries: 0, Sleep: func(context.Context, time.Duration) error { return nil }},
	}, server.Client())
	h := productionStack(t, p, "", 100)
	body, _ := json.Marshal(sampleRequest())
	if rec := postAssistant(h, body, "req-zero", ""); rec.Code != http.StatusOK {
		t.Fatalf("status=%d", rec.Code)
	}
	got := lastEvent(t, events)
	if got.PromptTokens == nil || *got.PromptTokens != 0 {
		t.Fatalf("zero tokens omitted: %+v", got.PromptTokens)
	}
}

func TestObservabilitySinkPanicDoesNotFailRequest(t *testing.T) {
	restore := observability.SetSinkForTest(func(observability.Entry) { panic("sink down") })
	t.Cleanup(restore)
	log.SetOutput(io.Discard)
	h := productionStack(t, provider.NewMockUpstreamAIProvider(), "", 100)
	body, _ := json.Marshal(sampleRequest())
	rec := postAssistant(h, body, "req-sink", "")
	if rec.Code != http.StatusOK {
		t.Fatalf("status=%d", rec.Code)
	}
}

func TestObservabilityGatewayRateLimit(t *testing.T) {
	events, _, _ := captureAIRequests(t)
	h := productionStack(t, provider.NewMockUpstreamAIProvider(), "", 1)
	body, _ := json.Marshal(sampleRequest())
	if rec := postAssistant(h, body, "req-rl-1", ""); rec.Code != http.StatusOK {
		t.Fatalf("first=%d", rec.Code)
	}
	rec := postAssistant(h, body, "req-rl-2", "")
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("second=%d", rec.Code)
	}
	got := lastEvent(t, events)
	if got.FailureStage != observability.StageGatewayRequestValidation || got.ErrorCode != observability.CodeGatewayRateLimited {
		t.Fatalf("event=%+v", got)
	}
	if got.Retryability != observability.NotRetryable {
		t.Fatalf("retryability=%s", got.Retryability)
	}
}

func TestObservabilityGatewayRetryCount(t *testing.T) {
	events, _, _ := captureAIRequests(t)
	var calls int
	draft := `{
		"title": "本月财务摘要",
		"body": "摘要",
		"answer": "摘要",
		"citedFactKeys": ["availableCash"],
		"confidence": 0.8,
		"keyFacts": [{"label": "可用资金", "kind": "balance", "source": "availableCash"}],
		"references": [{"key": "availableCash"}],
		"riskExplanations": [],
		"unknownExplanations": []
	}`
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		calls++
		if calls == 1 {
			w.WriteHeader(http.StatusTooManyRequests)
			return
		}
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":` + jsonQuote(draft) + `}}]}`))
	}))
	t.Cleanup(server.Close)
	p := provider.NewBailianProvider(provider.BailianConfig{
		APIKey:  "k",
		BaseURL: server.URL,
		Model:   "qwen-plus",
		Timeout: time.Second,
		RetryPolicy: provider.RetryPolicy{
			MaxRetries: 1,
			BaseDelay:  time.Millisecond,
			MaxDelay:   time.Millisecond,
			Sleep:      func(context.Context, time.Duration) error { return nil },
		},
	}, server.Client())
	h := productionStack(t, p, "", 100)
	body, _ := json.Marshal(sampleRequest())
	if rec := postAssistant(h, body, "req-retry-count", ""); rec.Code != http.StatusOK {
		t.Fatalf("status=%d", rec.Code)
	}
	got := lastEvent(t, events)
	if got.RetryCount == nil || *got.RetryCount != 1 {
		t.Fatalf("retryCount=%v calls=%d", got.RetryCount, calls)
	}
	if got.Outcome != observability.OutcomeSuccess {
		t.Fatalf("outcome=%s", got.Outcome)
	}
}

func TestObservabilityHealthNotAIRequest(t *testing.T) {
	events, _, _ := captureAIRequests(t)
	mux := http.NewServeMux()
	mux.Handle("/health", &handler.HealthHandler{BuildVersion: "test"})
	mux.Handle("/v1/ai/financial-assistant", productionStack(t, provider.NewMockUpstreamAIProvider(), "", 100))
	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("health=%d", rec.Code)
	}
	if len(*events) != 0 {
		t.Fatalf("health must not emit ai_request: %+v", *events)
	}
}

func jsonQuote(s string) string {
	b, _ := json.Marshal(s)
	return string(b)
}

func TestRequestIDCorrelationLocalIntegration(t *testing.T) {
	events, logs, _ := captureAIRequests(t)
	const requestID = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
	h := productionStack(t, provider.NewMockUpstreamAIProvider(), canaryToken, 100)
	req := canaryRequest()
	req.RequestID = requestID
	body, _ := json.Marshal(req)
	rec := postAssistant(h, body, requestID, canaryToken)
	if rec.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", rec.Code, rec.Body.String())
	}
	if rec.Header().Get("X-Youshu-Request-Id") != requestID {
		t.Fatalf("response header=%s", rec.Header().Get("X-Youshu-Request-Id"))
	}
	var envelope contract.SuccessEnvelope
	if err := json.Unmarshal(rec.Body.Bytes(), &envelope); err != nil {
		t.Fatal(err)
	}
	if envelope.RequestID != requestID {
		t.Fatalf("body requestId=%s", envelope.RequestID)
	}
	got := lastEvent(t, events)
	if got.Event != observability.EventAIRequest {
		t.Fatalf("event=%s", got.Event)
	}
	if got.RequestID != requestID {
		t.Fatalf("telemetry requestId=%s", got.RequestID)
	}
	if got.Outcome != observability.OutcomeSuccess {
		t.Fatalf("outcome=%s", got.Outcome)
	}
	payload, _ := json.Marshal(got)
	assertNoCanaries(t, string(payload), logs.String(), rec.Header().Get("Authorization"))
}

func TestRequestIDReuseAcrossSimulatedIOSRetry(t *testing.T) {
	events, _, _ := captureAIRequests(t)
	const requestID = "bbbbbbbb-cccc-4ddd-8eee-ffffffffffff"
	upstream := &failOnceUpstream{ok: provider.NewMockUpstreamAIProvider()}
	h := productionStack(t, upstream, "", 100)
	body, _ := json.Marshal(sampleRequest())
	first := postAssistant(h, body, requestID, "")
	if first.Code != http.StatusServiceUnavailable {
		t.Fatalf("first status=%d", first.Code)
	}
	second := postAssistant(h, body, requestID, "")
	if second.Code != http.StatusOK {
		t.Fatalf("second status=%d body=%s", second.Code, second.Body.String())
	}
	if len(*events) != 2 {
		t.Fatalf("expected 2 gateway events, got %d", len(*events))
	}
	if (*events)[0].RequestID != requestID || (*events)[1].RequestID != requestID {
		t.Fatalf("requestIds=%s,%s", (*events)[0].RequestID, (*events)[1].RequestID)
	}
	if (*events)[0].Outcome != observability.OutcomeFailed {
		t.Fatalf("first outcome=%s", (*events)[0].Outcome)
	}
	if (*events)[1].Outcome != observability.OutcomeSuccess {
		t.Fatalf("second outcome=%s", (*events)[1].Outcome)
	}
}

type failOnceUpstream struct {
	ok    provider.UpstreamAIProvider
	calls int
}

func (f *failOnceUpstream) CompleteMonthlySummary(ctx context.Context, env contract.RequestEnvelope) (contract.AssistantAnswerDraftDTO, error) {
	f.calls++
	if f.calls == 1 {
		return contract.AssistantAnswerDraftDTO{}, &provider.UpstreamError{Code: contract.ErrProviderUnavailable}
	}
	return f.ok.CompleteMonthlySummary(ctx, env)
}
