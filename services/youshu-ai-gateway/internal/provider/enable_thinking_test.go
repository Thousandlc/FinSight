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
	"github.com/youshu/youshu-ai-gateway/internal/prompt"
	"github.com/youshu/youshu-ai-gateway/internal/provider"
)

func TestMonthlySummaryRequestDisablesThinkingForQwen37Plus(t *testing.T) {
	schema, err := prompt.LoadAssistantAnswerModelDraftSchema()
	if err != nil {
		t.Fatal(err)
	}

	var rawBody []byte
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		rawBody, _ = io.ReadAll(r.Body)
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":` + jsonString(validDraftJSON()) + `}}]}`))
	}))
	t.Cleanup(server.Close)

	const apiKey = "sk-test-enable-thinking-secret"
	const model = "qwen3.7-plus"
	p := provider.NewBailianProvider(provider.BailianConfig{
		APIKey:               apiKey,
		BaseURL:              server.URL,
		Model:                model,
		Timeout:              5 * time.Second,
		StructuredOutputMode: config.StructuredOutputJSONSchemaStrict,
		JSONSchema:           schema,
	}, server.Client())

	if _, err := p.CompleteMonthlySummary(context.Background(), sampleEnvelope()); err != nil {
		t.Fatal(err)
	}

	var top map[string]json.RawMessage
	if err := json.Unmarshal(rawBody, &top); err != nil {
		t.Fatalf("request json: %v", err)
	}

	enableThinkingRaw, ok := top["enable_thinking"]
	if !ok {
		t.Fatal("enable_thinking missing from request top level")
	}
	if string(enableThinkingRaw) != "false" {
		t.Fatalf("enable_thinking=%s want false", enableThinkingRaw)
	}

	for _, key := range []string{"model", "messages", "response_format", "enable_thinking"} {
		if _, ok := top[key]; !ok {
			t.Fatalf("top-level key missing: %q", key)
		}
	}

	modelRaw, ok := top["model"]
	if !ok {
		t.Fatal("model missing")
	}
	var modelValue string
	if err := json.Unmarshal(modelRaw, &modelValue); err != nil {
		t.Fatal(err)
	}
	if modelValue != model {
		t.Fatalf("model=%q want %q", modelValue, model)
	}

	var responseFormat map[string]json.RawMessage
	if err := json.Unmarshal(top["response_format"], &responseFormat); err != nil {
		t.Fatal(err)
	}
	if string(responseFormat["type"]) != `"json_schema"` {
		t.Fatalf("response_format.type=%s", responseFormat["type"])
	}
	if _, ok := responseFormat["json_schema"]; !ok {
		t.Fatal("response_format.json_schema missing")
	}

	if strings.Contains(string(rawBody), apiKey) {
		t.Fatal("request body leaked api key")
	}
}

func TestJSONObjectModeStillSendsEnableThinkingFalse(t *testing.T) {
	var rawBody []byte
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		rawBody, _ = io.ReadAll(r.Body)
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":` + jsonString(validDraftJSON()) + `}}]}`))
	}))
	t.Cleanup(server.Close)

	p := provider.NewBailianProvider(provider.BailianConfig{
		APIKey:               "k",
		BaseURL:              server.URL,
		Model:                "qwen-plus",
		Timeout:              5 * time.Second,
		StructuredOutputMode: config.StructuredOutputJSONObject,
	}, server.Client())
	if _, err := p.CompleteMonthlySummary(context.Background(), sampleEnvelope()); err != nil {
		t.Fatal(err)
	}

	var top map[string]any
	if err := json.Unmarshal(rawBody, &top); err != nil {
		t.Fatal(err)
	}
	if val, ok := top["enable_thinking"]; !ok || val != false {
		t.Fatalf("enable_thinking=%v want false at top level", top["enable_thinking"])
	}

	responseFormat, ok := top["response_format"].(map[string]any)
	if !ok {
		t.Fatal("response_format missing")
	}
	if responseFormat["type"] != "json_object" {
		t.Fatalf("response_format.type=%v", responseFormat["type"])
	}
	if _, ok := responseFormat["json_schema"]; ok {
		t.Fatal("json_object mode must not send json_schema")
	}
}
