package provider_test

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/youshu/youshu-ai-gateway/internal/config"
	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/provider"
)

func sampleEnvelope() contract.RequestEnvelope {
	return contract.RequestEnvelope{
		SchemaVersion: "v1",
		RequestID:     "req-bailian-1",
		Operation:     contract.OperationMonthlySummary,
		AssistantRequest: contract.AssistantRequestDTO{
			Question: "",
			Intent:   "unknown",
			Context: map[string]any{
				"meta": map[string]any{"currencyCode": "CNY"},
				"balance": map[string]any{
					"availableCash":       map[string]any{"amount": "10000", "currencyCode": "CNY"},
					"estimatedMonthEnd":   map[string]any{"amount": "8000", "currencyCode": "CNY"},
				},
			},
		},
		MonthlySummaryFacts: &contract.MonthlySummaryFactsDTO{
			AvailableCash:            contract.MoneyDTO{Amount: "10000", CurrencyCode: "CNY"},
			MonthlyIncome:            contract.MoneyDTO{Amount: "12000", CurrencyCode: "CNY"},
			MonthlyExpense:           contract.MoneyDTO{Amount: "6000", CurrencyCode: "CNY"},
			MonthlyDebtPayment:       contract.MoneyDTO{Amount: "2000", CurrencyCode: "CNY"},
			PrimaryPressure:          "日常支出",
			EstimatedMonthEndBalance: contract.MoneyDTO{Amount: "8000", CurrencyCode: "CNY"},
			SourceLabels:             []string{"Account", "Transaction"},
		},
		FinancialRiskAssessment: &contract.FinancialRiskAssessmentDTO{
			OverallLevel:  "safe",
			PolicyVersion: "v1",
			DebtDataState: "knownDebt",
			Signals:       []contract.FinancialRiskSignalDTO{},
			DataCompleteness: contract.FinancialDataCompletenessDTO{
				Debt:                       "known",
				CashFlowProjection:         "known",
				Income:                     "known",
				Expense:                    "known",
				RequiredUnknownReasonCodes: []string{},
			},
		},
	}
}

func validDraftJSON() string {
	return `{
		"title": "本月财务摘要",
		"body": "本月可用资金约 ¥10000，预计月底结余约 ¥8000。",
		"answer": "本月可用资金约 ¥10000，预计月底结余约 ¥8000。",
		"citedFactKeys": ["availableCash", "estimatedMonthEndBalance"],
		"confidence": 0.85,
		"keyFacts": [{
			"label": "可用资金",
			"kind": "balance",
			"source": "availableCash"
		}],
		"references": [{"key": "availableCash"}],
		"riskExplanations": [],
		"unknownExplanations": []
	}`
}

func newBailianTestServer(t *testing.T, handler http.HandlerFunc) (*httptest.Server, *provider.BailianProvider) {
	t.Helper()
	server := httptest.NewServer(handler)
	t.Cleanup(server.Close)

	p := provider.NewBailianProvider(provider.BailianConfig{
		APIKey:  "test-api-key-secret",
		BaseURL: server.URL,
		Model:   "qwen-plus-test",
		Timeout: 5 * time.Second,
	}, server.Client())
	return server, p
}

func TestBailianSuccessStructuredDraft(t *testing.T) {
	var capturedAuth string
	var capturedBody chatCapture
	_, p := newBailianTestServer(t, func(w http.ResponseWriter, r *http.Request) {
		capturedAuth = r.Header.Get("Authorization")
		raw, _ := io.ReadAll(r.Body)
		_ = json.Unmarshal(raw, &capturedBody)
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":` + jsonString(validDraftJSON()) + `}}],"usage":{"prompt_tokens":100,"completion_tokens":50,"total_tokens":150}}`))
	})

	draft, err := p.CompleteMonthlySummary(context.Background(), sampleEnvelope())
	if err != nil {
		t.Fatal(err)
	}
	if draft.Title != "本月财务摘要" {
		t.Fatalf("title=%q", draft.Title)
	}
	if capturedAuth != "Bearer test-api-key-secret" {
		t.Fatalf("auth header leaked or wrong: %q", capturedAuth)
	}
	if capturedBody.Model != "qwen-plus-test" {
		t.Fatalf("model=%q", capturedBody.Model)
	}
	if capturedBody.ResponseFormat == nil || capturedBody.ResponseFormat.Type != "json_object" {
		t.Fatal("response_format json_object not sent")
	}
}

func TestBailian401(t *testing.T) {
	_, p := newBailianTestServer(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
		_, _ = w.Write([]byte(`{"error":"invalid_api_key"}`))
	})
	_, err := p.CompleteMonthlySummary(context.Background(), sampleEnvelope())
	assertUpstreamCode(t, err, contract.ErrProviderUnavailable)
	assertNoSecretLeak(t, err)
}

func TestBailian429(t *testing.T) {
	_, p := newBailianTestServer(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusTooManyRequests)
	})
	_, err := p.CompleteMonthlySummary(context.Background(), sampleEnvelope())
	assertUpstreamCode(t, err, contract.ErrProviderRateLimited)
}

func TestBailian500(t *testing.T) {
	_, p := newBailianTestServer(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusInternalServerError)
	})
	_, err := p.CompleteMonthlySummary(context.Background(), sampleEnvelope())
	assertUpstreamCode(t, err, contract.ErrProviderUnavailable)
}

func TestBailianTimeout(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		time.Sleep(200 * time.Millisecond)
		w.WriteHeader(http.StatusOK)
	}))
	t.Cleanup(server.Close)

	p := provider.NewBailianProvider(provider.BailianConfig{
		APIKey:  "k",
		BaseURL: server.URL,
		Model:   "m",
		Timeout: 50 * time.Millisecond,
	}, server.Client())

	_, err := p.CompleteMonthlySummary(context.Background(), sampleEnvelope())
	assertUpstreamCode(t, err, contract.ErrProviderTimeout)
}

func TestBailianNonJSONContent(t *testing.T) {
	_, p := newBailianTestServer(t, func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"not json at all"}}]}`))
	})
	_, err := p.CompleteMonthlySummary(context.Background(), sampleEnvelope())
	assertUpstreamCode(t, err, contract.ErrInvalidProviderResponse)
}

func TestBailianMissingRequiredFields(t *testing.T) {
	_, p := newBailianTestServer(t, func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"{\"title\":\"\"}"}}]}`))
	})
	draft, err := p.CompleteMonthlySummary(context.Background(), sampleEnvelope())
	if err != nil {
		t.Fatal(err)
	}
	if draft.Title != "" {
		t.Fatal("expected empty title draft for handler validation")
	}
}

func TestBailianUsageParsed(t *testing.T) {
	_, p := newBailianTestServer(t, func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":` + jsonString(validDraftJSON()) + `}}],"usage":{"prompt_tokens":10,"completion_tokens":20,"total_tokens":30}}`))
	})
	if _, err := p.CompleteMonthlySummary(context.Background(), sampleEnvelope()); err != nil {
		t.Fatal(err)
	}
}

func TestBailianURLJoinCompatibleMode(t *testing.T) {
	var path string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		path = r.URL.Path
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":` + jsonString(validDraftJSON()) + `}}]}`))
	}))
	t.Cleanup(server.Close)

	p := provider.NewBailianProvider(provider.BailianConfig{
		APIKey:  "k",
		BaseURL: server.URL + "/compatible-mode/v1",
		Model:   "m",
		Timeout: 5 * time.Second,
	}, server.Client())
	if _, err := p.CompleteMonthlySummary(context.Background(), sampleEnvelope()); err != nil {
		t.Fatal(err)
	}
	if path != "/compatible-mode/v1/chat/completions" {
		t.Fatalf("path=%q", path)
	}
}

func TestBailianURLAlreadyIncludesChatCompletions(t *testing.T) {
	var path string
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		path = r.URL.Path
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":` + jsonString(validDraftJSON()) + `}}]}`))
	}))
	t.Cleanup(server.Close)

	p := provider.NewBailianProvider(provider.BailianConfig{
		APIKey:  "k",
		BaseURL: server.URL + "/compatible-mode/v1/chat/completions",
		Model:   "m",
		Timeout: 5 * time.Second,
	}, server.Client())
	if _, err := p.CompleteMonthlySummary(context.Background(), sampleEnvelope()); err != nil {
		t.Fatal(err)
	}
	if path != "/compatible-mode/v1/chat/completions" {
		t.Fatalf("path=%q", path)
	}
}

func TestNewUpstreamMockDefault(t *testing.T) {
	up, err := provider.NewUpstream(config.Config{UpstreamAIProvider: config.UpstreamMock})
	if err != nil {
		t.Fatal(err)
	}
	if up == nil {
		t.Fatal("expected mock upstream")
	}
}

func TestNewUpstreamBailianRequiresConfig(t *testing.T) {
	_, err := provider.NewUpstream(config.Config{UpstreamAIProvider: config.UpstreamBailian})
	if err == nil {
		t.Fatal("expected configuration error")
	}
}

func TestNewUpstreamBailianSuccess(t *testing.T) {
	up, err := provider.NewUpstream(config.Config{
		UpstreamAIProvider: config.UpstreamBailian,
		BailianAPIKey:      "key",
		BailianBaseURL:     "https://example.com/v1",
		BailianModel:       "qwen-plus",
	})
	if err != nil {
		t.Fatal(err)
	}
	if up == nil {
		t.Fatal("expected bailian upstream")
	}
}

type chatCapture struct {
	Model          string `json:"model"`
	ResponseFormat *struct {
		Type string `json:"type"`
	} `json:"response_format"`
}

func jsonString(s string) string {
	b, _ := json.Marshal(s)
	return string(b)
}

func assertUpstreamCode(t *testing.T, err error, code string) {
	t.Helper()
	if err == nil {
		t.Fatalf("expected error code %s", code)
	}
	if !strings.Contains(err.Error(), code) {
		t.Fatalf("err=%v want code %s", err, code)
	}
}

func assertNoSecretLeak(t *testing.T, err error) {
	t.Helper()
	if strings.Contains(err.Error(), "test-api-key-secret") {
		t.Fatal("upstream error leaked api key")
	}
}
