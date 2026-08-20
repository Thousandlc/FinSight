package config_test

import (
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/config"
)

func TestValidateUpstreamMock(t *testing.T) {
	cfg := config.Config{UpstreamAIProvider: config.UpstreamMock}
	if err := cfg.ValidateUpstream(); err != nil {
		t.Fatal(err)
	}
}

func TestValidateUpstreamBailianMissingKey(t *testing.T) {
	cfg := config.Config{
		UpstreamAIProvider: config.UpstreamBailian,
		BailianBaseURL:     "https://example.com",
		BailianModel:       "qwen-plus",
	}
	if err := cfg.ValidateUpstream(); err == nil {
		t.Fatal("expected error for missing API key")
	}
}

func TestValidateUpstreamUnknown(t *testing.T) {
	cfg := config.Config{UpstreamAIProvider: "openai"}
	if err := cfg.ValidateUpstream(); err == nil {
		t.Fatal("expected error for unknown provider")
	}
}

func TestValidateStructuredOutputMode(t *testing.T) {
	cfg := config.Config{
		UpstreamAIProvider:          config.UpstreamBailian,
		BailianAPIKey:               "k",
		BailianBaseURL:              "https://example.com",
		BailianModel:                "qwen3.7-plus",
		BailianStructuredOutputMode: "xml",
	}
	if err := cfg.ValidateUpstream(); err == nil {
		t.Fatal("expected invalid structured output mode")
	}
}
