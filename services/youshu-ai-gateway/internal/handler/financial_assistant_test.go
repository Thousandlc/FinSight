package handler_test

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/handler"
	"github.com/youshu/youshu-ai-gateway/internal/provider"
)

func sampleRequest() contract.RequestEnvelope {
	pct := "25"
	risk := "预计8月15日账户余额可能下降至¥800，已低于安全余额¥2000。"
	safe := contract.MoneyDTO{Amount: "2000", CurrencyCode: "CNY"}
	min := contract.MoneyDTO{Amount: "800", CurrencyCode: "CNY"}
	assessment := contract.FinancialRiskAssessmentDTO{
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
	}
	return contract.RequestEnvelope{
		SchemaVersion: "v1",
		RequestID:     "req-123",
		Operation:     contract.OperationMonthlySummary,
		AssistantRequest: contract.AssistantRequestDTO{
			Question: "",
			Intent:   "unknown",
			Context:  map[string]any{"meta": map[string]any{"currencyCode": "CNY"}},
		},
		MonthlySummaryFacts: &contract.MonthlySummaryFactsDTO{
			AvailableCash:            contract.MoneyDTO{Amount: "1000", CurrencyCode: "CNY"},
			MonthlyIncome:            contract.MoneyDTO{Amount: "5000", CurrencyCode: "CNY"},
			MonthlyExpense:           contract.MoneyDTO{Amount: "3000", CurrencyCode: "CNY"},
			MonthlyDebtPayment:       contract.MoneyDTO{Amount: "500", CurrencyCode: "CNY"},
			DebtPaymentToIncomePercent: &pct,
			PrimaryPressure:          "债务还款",
			EstimatedMonthEndBalance: contract.MoneyDTO{Amount: "1500", CurrencyCode: "CNY"},
			CashFlowRiskExplanation:  &risk,
			SafeBalance:              &safe,
			MinimumBalance:           &min,
			SourceLabels:             []string{"Account", "Transaction"},
		},
		FinancialRiskAssessment: &assessment,
	}
}

func newTestHandler() *handler.FinancialAssistantHandler {
	return &handler.FinancialAssistantHandler{
		SchemaVersion: "v1",
		ModelAlias:    "mock-qwen",
		Upstream:      provider.NewMockUpstreamAIProvider(),
	}
}

func TestMonthlySummarySuccess(t *testing.T) {
	h := newTestHandler()
	body, _ := json.Marshal(sampleRequest())
	req := httptest.NewRequest(http.MethodPost, "/v1/ai/financial-assistant", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", rec.Code, rec.Body.String())
	}
	var resp contract.SuccessEnvelope
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}
	if resp.RequestID != "req-123" {
		t.Fatalf("requestId=%q", resp.RequestID)
	}
	if resp.ModelAlias != "mock-qwen" {
		t.Fatalf("modelAlias=%q", resp.ModelAlias)
	}
	if !strings.Contains(resp.Draft.Body, "债务还款") {
		t.Fatalf("draft should reflect primary pressure: %s", resp.Draft.Body)
	}
	if strings.Contains(rec.Body.String(), "GATEWAY_CLIENT_TOKEN") {
		t.Fatal("response must not contain secrets")
	}
}

func TestUnsupportedOperation(t *testing.T) {
	h := newTestHandler()
	reqBody := sampleRequest()
	reqBody.Operation = contract.OperationAsk
	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest(http.MethodPost, "/v1/ai/financial-assistant", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status=%d", rec.Code)
	}
	var resp contract.ErrorEnvelope
	_ = json.Unmarshal(rec.Body.Bytes(), &resp)
	if resp.Error.Code != contract.ErrUnsupportedOperation {
		t.Fatalf("code=%q", resp.Error.Code)
	}
}

func TestUnsupportedSchemaVersion(t *testing.T) {
	h := newTestHandler()
	reqBody := sampleRequest()
	reqBody.SchemaVersion = "v99"
	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest(http.MethodPost, "/v1/ai/financial-assistant", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status=%d", rec.Code)
	}
}

func TestInvalidRequestMissingFacts(t *testing.T) {
	h := newTestHandler()
	reqBody := sampleRequest()
	reqBody.MonthlySummaryFacts = nil
	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest(http.MethodPost, "/v1/ai/financial-assistant", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status=%d", rec.Code)
	}
}

func TestInvalidRequestMissingRiskAssessment(t *testing.T) {
	h := newTestHandler()
	reqBody := sampleRequest()
	reqBody.FinancialRiskAssessment = nil
	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest(http.MethodPost, "/v1/ai/financial-assistant", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status=%d", rec.Code)
	}
}

func TestInvalidUpstreamResponse(t *testing.T) {
	h := &handler.FinancialAssistantHandler{
		SchemaVersion: "v1",
		ModelAlias:    "mock-qwen",
		Upstream:      badUpstream{},
	}
	body, _ := json.Marshal(sampleRequest())
	req := httptest.NewRequest(http.MethodPost, "/v1/ai/financial-assistant", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusBadGateway {
		t.Fatalf("status=%d", rec.Code)
	}
}

type badUpstream struct{}

func (badUpstream) CompleteMonthlySummary(_ context.Context, _ contract.RequestEnvelope) (contract.AssistantAnswerDraftDTO, error) {
	return contract.AssistantAnswerDraftDTO{Title: "", Body: "", Answer: ""}, nil
}

func TestRequestIDEcho(t *testing.T) {
	h := newTestHandler()
	reqBody := sampleRequest()
	reqBody.RequestID = "echo-id-456"
	body, _ := json.Marshal(reqBody)
	req := httptest.NewRequest(http.MethodPost, "/v1/ai/financial-assistant", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	var resp contract.SuccessEnvelope
	_ = json.Unmarshal(rec.Body.Bytes(), &resp)
	if resp.RequestID != "echo-id-456" {
		t.Fatalf("requestId=%q", resp.RequestID)
	}
}

func TestResponseDoesNotContainContext(t *testing.T) {
	h := newTestHandler()
	body, _ := json.Marshal(sampleRequest())
	req := httptest.NewRequest(http.MethodPost, "/v1/ai/financial-assistant", bytes.NewReader(body))
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	text := rec.Body.String()
	if strings.Contains(text, "assistantRequest") {
		t.Fatal("response must not echo request context")
	}
}
