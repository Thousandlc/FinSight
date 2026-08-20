package provider_test

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/youshu/youshu-ai-gateway/internal/config"
	"github.com/youshu/youshu-ai-gateway/internal/prompt"
	"github.com/youshu/youshu-ai-gateway/internal/provider"
)

type jsonSchemaCapture struct {
	Model          string `json:"model"`
	ResponseFormat *struct {
		Type       string `json:"type"`
		JSONSchema *struct {
			Name   string          `json:"name"`
			Strict bool            `json:"strict"`
			Schema json.RawMessage `json:"schema"`
		} `json:"json_schema"`
	} `json:"response_format"`
}

func TestJSONSchemaStrictRequestFormat(t *testing.T) {
	schema, err := prompt.LoadAssistantAnswerModelDraftSchema()
	if err != nil {
		t.Fatal(err)
	}
	var captured jsonSchemaCapture
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		raw, _ := io.ReadAll(r.Body)
		if err := json.Unmarshal(raw, &captured); err != nil {
			t.Errorf("request json: %v", err)
		}
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":` + jsonString(validDraftJSON()) + `}}]}`))
	}))
	t.Cleanup(server.Close)
	p := provider.NewBailianProvider(provider.BailianConfig{
		APIKey:               "k",
		BaseURL:              server.URL,
		Model:                "qwen3.7-plus",
		Timeout:              5 * time.Second,
		StructuredOutputMode: config.StructuredOutputJSONSchemaStrict,
		JSONSchema:           schema,
	}, server.Client())

	if _, err := p.CompleteMonthlySummary(context.Background(), sampleEnvelope()); err != nil {
		t.Fatal(err)
	}
	if captured.Model != "qwen3.7-plus" {
		t.Fatalf("model=%q", captured.Model)
	}
	if captured.ResponseFormat == nil || captured.ResponseFormat.Type != "json_schema" {
		t.Fatalf("type=%v", captured.ResponseFormat)
	}
	if captured.ResponseFormat.JSONSchema == nil {
		t.Fatal("json_schema missing")
	}
	if captured.ResponseFormat.JSONSchema.Name != prompt.AssistantAnswerModelDraftSchemaName {
		t.Fatalf("name=%q", captured.ResponseFormat.JSONSchema.Name)
	}
	if !captured.ResponseFormat.JSONSchema.Strict {
		t.Fatal("strict must be true")
	}
	if len(captured.ResponseFormat.JSONSchema.Schema) == 0 {
		t.Fatal("schema payload missing")
	}
	var sent map[string]any
	if err := json.Unmarshal(captured.ResponseFormat.JSONSchema.Schema, &sent); err != nil {
		t.Fatal(err)
	}
	if _, ok := sent["properties"]; !ok {
		t.Fatal("sent schema missing properties")
	}
	sourceEnum := sent["$defs"].(map[string]any)["keyFact"].(map[string]any)["properties"].(map[string]any)["source"].(map[string]any)["enum"].([]any)
	if len(sourceEnum) == 0 {
		t.Fatal("request schema must bind keyFact.source enum")
	}
	foundAvailableCash := false
	for _, item := range sourceEnum {
		if item.(string) == "availableCash" {
			foundAvailableCash = true
		}
		if item.(string) == "Account" {
			t.Fatal("request schema must not allow Account source")
		}
	}
	if !foundAvailableCash {
		t.Fatal("request schema must include availableCash in source enum")
	}
	keyFactProps := sent["$defs"].(map[string]any)["keyFact"].(map[string]any)["properties"].(map[string]any)
	if _, ok := keyFactProps["value"]; ok {
		t.Fatal("sent model schema must not include keyFact.value")
	}
}

func TestJSONObjectModeUnchanged(t *testing.T) {
	var captured jsonSchemaCapture
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		raw, _ := io.ReadAll(r.Body)
		_ = json.Unmarshal(raw, &captured)
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
	if captured.ResponseFormat == nil || captured.ResponseFormat.Type != "json_object" {
		t.Fatal("default experiment must not change json_object baseline")
	}
	if captured.ResponseFormat.JSONSchema != nil {
		t.Fatal("json_object mode must not send json_schema")
	}
}
