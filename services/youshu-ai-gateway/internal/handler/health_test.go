package handler_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/config"
	"github.com/youshu/youshu-ai-gateway/internal/handler"
)

func TestHealthOK(t *testing.T) {
	h := &handler.HealthHandler{BuildVersion: "test-version"}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/health", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("status=%d", rec.Code)
	}

	var payload map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if payload["service"] != config.GatewayServiceName {
		t.Fatalf("service=%q want %q", payload["service"], config.GatewayServiceName)
	}
	if payload["version"] != "test-version" {
		t.Fatalf("version=%q", payload["version"])
	}
	if payload["status"] != "ok" {
		t.Fatalf("status=%q", payload["status"])
	}
}

func TestReadyConfigured(t *testing.T) {
	cfg := config.Config{
		EnvMode:              config.EnvDevelopment,
		UpstreamAIProvider:   config.UpstreamMock,
		BailianTimeoutSecond: 25,
		RateLimitRequests:    60,
		RateLimitWindowSec:   60,
		UpstreamMaxRetries:   2,
		RetryBaseDelayMS:     500,
		RetryMaxDelayMS:      8000,
		UpstreamMaxConcurrency: 4,
		ReadHeaderTimeoutSec: 5,
		ReadTimeoutSec:       30,
		WriteTimeoutSec:      60,
		IdleTimeoutSec:       120,
		ShutdownTimeoutSec:   30,
		BuildVersion:         "test-version",
	}
	h := &handler.ReadinessHandler{Config: cfg}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/ready", nil))
	if rec.Code != http.StatusOK {
		t.Fatalf("status=%d body=%s", rec.Code, rec.Body.String())
	}

	var payload map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if payload["service"] != config.GatewayServiceName {
		t.Fatalf("service=%q want %q", payload["service"], config.GatewayServiceName)
	}
	if payload["version"] != "test-version" {
		t.Fatalf("version=%q", payload["version"])
	}
	if payload["provider"] != config.UpstreamMock {
		t.Fatalf("provider=%q", payload["provider"])
	}
}

func TestReadyMissingProductionConfig(t *testing.T) {
	cfg := config.Config{
		EnvMode:            config.EnvProduction,
		UpstreamAIProvider: "",
		BuildVersion:       "test-version",
	}
	h := &handler.ReadinessHandler{Config: cfg}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/ready", nil))
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("status=%d", rec.Code)
	}
	if !strings.Contains(rec.Body.String(), "reason") {
		t.Fatalf("expected reason field in body=%s", rec.Body.String())
	}
}
