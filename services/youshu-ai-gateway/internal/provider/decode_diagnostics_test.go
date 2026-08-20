package provider_test

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/youshu/youshu-ai-gateway/internal/handler"
	"github.com/youshu/youshu-ai-gateway/internal/provider"
)

func TestHTTP200DTODecodeFailStillHTTPSuccess(t *testing.T) {
	secret := "SECRET_DRAFT_BODY_SHOULD_NOT_APPEAR"
	_, p := newBailianTestServer(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"{\"title\":123,\"body\":\"` + secret + `\"}"}}],"usage":{"prompt_tokens":11,"completion_tokens":7,"total_tokens":18}}`))
	})
	_, diag, err := p.DiagnoseMonthlySummary(context.Background(), sampleEnvelope())
	if err == nil {
		t.Fatal("expected dto decode error")
	}
	if !diag.HTTPSuccess {
		t.Fatalf("httpSuccess=%v status=%d", diag.HTTPSuccess, diag.HTTPStatus)
	}
	if diag.HTTPStatus != 200 {
		t.Fatalf("status=%d", diag.HTTPStatus)
	}
	if diag.DraftDTODecode != provider.StageFail {
		t.Fatalf("dto stage=%s", diag.DraftDTODecode)
	}
	if diag.EndToEndSuccess() {
		t.Fatal("endToEndSuccess must be independent of httpSuccess")
	}
}

func TestHTTP200InvalidJSON(t *testing.T) {
	_, p := newBailianTestServer(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"not json UNIQUE_INVALID_BODY"}}],"usage":{"prompt_tokens":9,"completion_tokens":3,"total_tokens":12}}`))
	})
	_, diag, _ := p.DiagnoseMonthlySummary(context.Background(), sampleEnvelope())
	if !diag.HTTPSuccess {
		t.Fatal("httpSuccess should be true for HTTP 200")
	}
	if diag.ContentJSONValid {
		t.Fatal("expected contentJSONValid=false")
	}
	if diag.ContentJSONSyntax != provider.StageFail {
		t.Fatalf("syntax stage=%s", diag.ContentJSONSyntax)
	}
	if diag.PromptTokens != 9 || diag.TotalTokens != 12 {
		t.Fatalf("token usage not recorded: prompt=%d total=%d", diag.PromptTokens, diag.TotalTokens)
	}
}

func TestDiagnoseTimeoutLatencyPositive(t *testing.T) {
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
	_, diag, err := p.DiagnoseMonthlySummary(context.Background(), sampleEnvelope())
	if err == nil {
		t.Fatal("expected timeout")
	}
	if diag.TimeoutStage != provider.TimeoutStageUpstreamHTTP {
		t.Fatalf("timeoutStage=%q", diag.TimeoutStage)
	}
	if diag.Latency <= 0 {
		t.Fatal("latency must be > 0 on timeout")
	}
	if diag.HTTPSuccess {
		t.Fatal("timeout must not count as httpSuccess")
	}
}

func TestHTTP200SchemaFailDecodeSuccess(t *testing.T) {
	emptyTitle := `{
		"title": "",
		"body": "正文",
		"answer": "正文",
		"citedFactKeys": [],
		"confidence": 0.5,
		"keyFacts": [],
		"references": [],
		"riskExplanations": [],
		"unknownExplanations": []
	}`
	_, p := newBailianTestServer(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":` + jsonString(emptyTitle) + `}}]}`))
	})
	draft, diag, err := p.DiagnoseMonthlySummary(context.Background(), sampleEnvelope())
	if err != nil {
		t.Fatalf("dto decode should succeed: %v", err)
	}
	if diag.DraftDTODecode != provider.StagePass {
		t.Fatalf("dto stage=%s", diag.DraftDTODecode)
	}
	if strings.TrimSpace(draft.Title) != "" {
		t.Fatal("expected empty title for schema fail fixture")
	}
	schema := handler.DiagnoseSchema(draft)
	if schema.Passed {
		t.Fatal("expected schema fail")
	}
	if schema.TitleValid {
		t.Fatal("titleValid should be false")
	}
	if !schema.BodyValid || !schema.AnswerValid {
		t.Fatal("body/answer should still be valid")
	}
}

func TestGenericJSONTopLevelKeys(t *testing.T) {
	content := `{"title":"t","body":"b","answer":"a","citedFactKeys":[],"confidence":0.1,"keyFacts":[],"references":[],"riskExplanations":[],"unknownExplanations":[],"extra":true}`
	_, diag := provider.AnalyzeContent(content, nil, nil)
	if diag.GenericJSONObjectDecode != provider.StagePass {
		t.Fatalf("generic=%s", diag.GenericJSONObjectDecode)
	}
	joined := strings.Join(diag.TopLevelKeys, ",")
	if joined != "answer,body,citedFactKeys,confidence,extra,keyFacts,references,riskExplanations,title,unknownExplanations" {
		t.Fatalf("keys=%s", joined)
	}
}

func TestTypeMismatchSafePath(t *testing.T) {
	content := `{
		"title": "t",
		"body": "b",
		"answer": "a",
		"citedFactKeys": [],
		"confidence": 0.1,
		"keyFacts": [{"label":"x","kind":"balance","source":"availableCash","value":{"type":"money","amount":"not-a-number","currencyCode":"CNY","textValue":null,"percentValue":null,"dateValue":null}}],
		"references": [],
		"riskExplanations": [],
		"unknownExplanations": []
	}`
	_, diag := provider.AnalyzeContent(content, nil, nil)
	if diag.DraftDTODecode != provider.StageFail {
		t.Fatalf("expected dto fail, kind=%s path=%s", diag.DTODecodeErrorKind, diag.DTODecodeErrorPath)
	}
	if diag.DTODecodeErrorKind != "modelValidation" {
		t.Fatalf("kind=%s", diag.DTODecodeErrorKind)
	}
	if diag.DTODecodeErrorPath != "keyFacts.value" {
		t.Fatalf("path=%s", diag.DTODecodeErrorPath)
	}
}

func TestMissingKeySafeDiagnostic(t *testing.T) {
	content := `{"foo":1,"bar":2}`
	_, diag := provider.AnalyzeContent(content, nil, nil)
	if diag.GenericJSONObjectDecode != provider.StagePass {
		t.Fatal("generic object should decode")
	}
	if diag.MissingKey == "" {
		t.Fatal("expected missingKey")
	}
	if !strings.Contains(diag.MissingKey, "title") {
		t.Fatalf("missingKey=%s", diag.MissingKey)
	}
}

func TestDecodeDiagnosticOmitsModelBody(t *testing.T) {
	secret := "UNIQUE_MODEL_BODY_LEAK_TOKEN_918273"
	content := `not json ` + secret
	_, diag := provider.AnalyzeContent(content, nil, nil)
	encoded, err := json.Marshal(diag)
	if err != nil {
		t.Fatal(err)
	}
	dump := string(encoded) + fmt.Sprintf("%+v", diag)
	if strings.Contains(dump, secret) {
		t.Fatal("diagnostics leaked model body")
	}
}

func TestTokenUsageRecordedWhenDecodeFails(t *testing.T) {
	_, p := newBailianTestServer(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"not-json"}}],"usage":{"prompt_tokens":40,"completion_tokens":5,"total_tokens":45}}`))
	})
	_, diag, _ := p.DiagnoseMonthlySummary(context.Background(), sampleEnvelope())
	if diag.PromptTokens != 40 || diag.CompletionTokens != 5 || diag.TotalTokens != 45 {
		t.Fatalf("usage prompt=%d completion=%d total=%d", diag.PromptTokens, diag.CompletionTokens, diag.TotalTokens)
	}
	if diag.DraftDTODecode == provider.StagePass {
		t.Fatal("decode should fail")
	}
}

func TestEndToEndIndependentFromHTTPSuccess(t *testing.T) {
	_, p := newBailianTestServer(t, func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":"{}"}}],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}`))
	})
	_, diag, _ := p.DiagnoseMonthlySummary(context.Background(), sampleEnvelope())
	if !diag.HTTPSuccess {
		t.Fatal("httpSuccess true")
	}
	if diag.EndToEndSuccess() {
		t.Fatal("endToEndSuccess must be false")
	}
}

func TestKeyFactValueStringTypeMismatchDiagnostics(t *testing.T) {
	content := `{
		"title": "t",
		"body": "b",
		"answer": "a",
		"citedFactKeys": [],
		"confidence": 0.8,
		"keyFacts": [{
			"label": "占比",
			"kind": "debt",
			"source": "debtPaymentToIncomePercent",
			"value": "40"
		}],
		"references": [],
		"riskExplanations": [],
		"unknownExplanations": []
	}`
	_, diag := provider.AnalyzeContent(content, nil, nil)
	if diag.DraftDTODecode != provider.StageFail {
		t.Fatalf("dto stage=%s", diag.DraftDTODecode)
	}
	if diag.DTODecodeErrorKind != "modelValidation" {
		t.Fatalf("kind=%s", diag.DTODecodeErrorKind)
	}
	if diag.FailingKeyFactIndex != 0 {
		t.Fatalf("index=%d", diag.FailingKeyFactIndex)
	}
	if diag.FailingKeyFactKind != "debt" {
		t.Fatalf("kind=%s", diag.FailingKeyFactKind)
	}
	if diag.KeyFactValueJSONType != "string" {
		t.Fatalf("valueType=%s", diag.KeyFactValueJSONType)
	}
}

func TestKeyFactValueObjectFieldTypeDiagnostics(t *testing.T) {
	content := `{
		"title": "t",
		"body": "b",
		"answer": "a",
		"citedFactKeys": [],
		"confidence": 0.8,
		"keyFacts": [{
			"label": "占比",
			"kind": "debt",
			"source": "debtPaymentToIncomePercent",
			"value": {"type":"percent","amount":null,"currencyCode":null,"textValue":null,"percentValue":"40","dateValue":null}
		}],
		"references": [],
		"riskExplanations": [],
		"unknownExplanations": []
	}`
	_, diag := provider.AnalyzeContent(content, nil, nil)
	if diag.DraftDTODecode != provider.StageFail {
		t.Fatal("expected dto decode fail for string percent value")
	}
	if diag.FailingKeyFactIndex != 0 || diag.FailingKeyFactKind != "debt" {
		t.Fatalf("index=%d kind=%s", diag.FailingKeyFactIndex, diag.FailingKeyFactKind)
	}
	if diag.KeyFactValueJSONType != "object" {
		t.Fatalf("valueType=%s", diag.KeyFactValueJSONType)
	}
	if len(diag.KeyFactValueKeys) == 0 || len(diag.KeyFactValueFieldTypes) == 0 {
		t.Fatalf("keys=%v fieldTypes=%v", diag.KeyFactValueKeys, diag.KeyFactValueFieldTypes)
	}
	foundValueString := false
	for _, item := range diag.KeyFactValueFieldTypes {
		if item == "percentValue:string" {
			foundValueString = true
		}
		if strings.Contains(item, "98765") {
			t.Fatal("field types must not include raw value content")
		}
	}
	if !foundValueString {
		t.Fatalf("fieldTypes=%v", diag.KeyFactValueFieldTypes)
	}
}

func TestKeyFactValueDiagnosticsDoNotLeakValueContent(t *testing.T) {
	secretAmount := "98765.43"
	content := fmt.Sprintf(`{
		"title": "t",
		"body": "b",
		"answer": "a",
		"citedFactKeys": [],
		"confidence": 0.8,
		"keyFacts": [{
			"label": "可用",
			"kind": "balance",
			"source": "availableCash",
			"value": {"type":"money","amount":"%s","currencyCode":"CNY","textValue":null,"percentValue":null,"dateValue":null}
		}],
		"references": [],
		"riskExplanations": [],
		"unknownExplanations": []
	}`, secretAmount)
	_, diag := provider.AnalyzeContent(content, nil, nil)
	encoded, err := json.Marshal(diag)
	if err != nil {
		t.Fatal(err)
	}
	dump := string(encoded) + fmt.Sprintf("%+v", diag)
	if strings.Contains(dump, secretAmount) {
		t.Fatal("diagnostics leaked keyFact value content")
	}
}
