package config_test

import (
	"os"
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/config"
)

func TestValidateForStartupProductionRejectsMock(t *testing.T) {
	cfg := config.Config{
		EnvMode:              config.EnvProduction,
		UpstreamAIProvider:   config.UpstreamMock,
		GatewayClientToken:   "token",
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
	}
	if err := cfg.ValidateForStartup(); err == nil {
		t.Fatal("expected production mock rejection")
	}
}

func TestValidateForStartupProductionMissingBailian(t *testing.T) {
	cfg := config.Config{
		EnvMode:              config.EnvProduction,
		UpstreamAIProvider:   config.UpstreamBailian,
		GatewayClientToken:   "token",
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
	}
	if err := cfg.ValidateForStartup(); err == nil {
		t.Fatal("expected missing bailian credentials error")
	}
}

func TestValidateForStartupProductionValid(t *testing.T) {
	cfg := config.Config{
		EnvMode:                     config.EnvProduction,
		UpstreamAIProvider:          config.UpstreamBailian,
		GatewayClientToken:          "token",
		BailianAPIKey:               "key",
		BailianBaseURL:              "https://dashscope.aliyuncs.com/compatible-mode/v1",
		BailianModel:                "qwen-plus",
		BailianStructuredOutputMode: config.StructuredOutputJSONObject,
		BailianTimeoutSecond:        25,
		BuildVersion:                "abc1234",
		RateLimitRequests:           60,
		RateLimitWindowSec:          60,
		UpstreamMaxRetries:          2,
		RetryBaseDelayMS:            500,
		RetryMaxDelayMS:             8000,
		UpstreamMaxConcurrency:      4,
		ReadHeaderTimeoutSec:        5,
		ReadTimeoutSec:              30,
		WriteTimeoutSec:             60,
		IdleTimeoutSec:              120,
		ShutdownTimeoutSec:          30,
	}
	if err := cfg.ValidateForStartup(); err != nil {
		t.Fatal(err)
	}
}

func TestProductionRejectsPlaceholderBuildVersion(t *testing.T) {
	cfg := config.Config{
		EnvMode:                     config.EnvProduction,
		UpstreamAIProvider:          config.UpstreamBailian,
		GatewayClientToken:          "token",
		BailianAPIKey:               "key",
		BailianBaseURL:              "https://dashscope.aliyuncs.com/compatible-mode/v1",
		BailianModel:                "qwen-plus",
		BailianStructuredOutputMode: config.StructuredOutputJSONObject,
		BailianTimeoutSecond:        25,
		BuildVersion:                config.BuildVersionPlaceholder,
		RateLimitRequests:           60,
		RateLimitWindowSec:          60,
		UpstreamMaxRetries:          2,
		RetryBaseDelayMS:            500,
		RetryMaxDelayMS:             8000,
		UpstreamMaxConcurrency:      4,
		ReadHeaderTimeoutSec:        5,
		ReadTimeoutSec:              30,
		WriteTimeoutSec:             60,
		IdleTimeoutSec:              120,
		ShutdownTimeoutSec:          30,
	}
	if err := cfg.ValidateForStartup(); err == nil {
		t.Fatal("expected placeholder BUILD_VERSION rejection in production")
	}
}

func TestProductionRejectsSmokeDump(t *testing.T) {
	cfg := config.Config{
		EnvMode:                     config.EnvProduction,
		UpstreamAIProvider:          config.UpstreamBailian,
		GatewayClientToken:          "token",
		BailianAPIKey:               "key",
		BailianBaseURL:              "https://dashscope.aliyuncs.com/compatible-mode/v1",
		BailianModel:                "qwen-plus",
		BailianStructuredOutputMode: config.StructuredOutputJSONObject,
		BailianTimeoutSecond:        25,
		BuildVersion:                "abc1234",
		RateLimitRequests:           60,
		RateLimitWindowSec:          60,
		UpstreamMaxRetries:          2,
		RetryBaseDelayMS:            500,
		RetryMaxDelayMS:             8000,
		UpstreamMaxConcurrency:      4,
		ReadHeaderTimeoutSec:        5,
		ReadTimeoutSec:              30,
		WriteTimeoutSec:             60,
		IdleTimeoutSec:              120,
		ShutdownTimeoutSec:          30,
		SmokeDumpRaw:                true,
	}
	if err := cfg.ValidateForStartup(); err == nil {
		t.Fatal("expected smoke dump rejection in production")
	}
}

func TestProductionRejectsEmptyBuildVersion(t *testing.T) {
	cfg := config.Config{
		EnvMode:                     config.EnvProduction,
		UpstreamAIProvider:          config.UpstreamBailian,
		GatewayClientToken:          "token",
		BailianAPIKey:               "key",
		BailianBaseURL:              "https://dashscope.aliyuncs.com/compatible-mode/v1",
		BailianModel:                "qwen-plus",
		BailianStructuredOutputMode: config.StructuredOutputJSONObject,
		BailianTimeoutSecond:        25,
		RateLimitRequests:           60,
		RateLimitWindowSec:          60,
		UpstreamMaxRetries:          2,
		RetryBaseDelayMS:            500,
		RetryMaxDelayMS:             8000,
		UpstreamMaxConcurrency:      4,
		ReadHeaderTimeoutSec:        5,
		ReadTimeoutSec:              30,
		WriteTimeoutSec:             60,
		IdleTimeoutSec:              120,
		ShutdownTimeoutSec:          30,
	}
	if err := cfg.ValidateForStartup(); err == nil {
		t.Fatal("expected empty BUILD_VERSION rejection in production")
	}
}

func TestGatewayServiceIdentityConstant(t *testing.T) {
	if config.GatewayServiceName != "finsight-ai-gateway" {
		t.Fatalf("GatewayServiceName=%q", config.GatewayServiceName)
	}
}

func TestValidateForStartupDevelopmentMockAllowed(t *testing.T) {
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
	}
	if err := cfg.ValidateForStartup(); err != nil {
		t.Fatal(err)
	}
}

func TestLoadProductionRequiresExplicitProvider(t *testing.T) {
	t.Setenv("YOUSHU_ENV", config.EnvProduction)
	t.Setenv("UPSTREAM_AI_PROVIDER", "")
	t.Setenv("GATEWAY_CLIENT_TOKEN", "token")
	cfg := config.Load()
	if cfg.UpstreamAIProvider != "" {
		t.Fatalf("expected empty provider in production when unset, got %q", cfg.UpstreamAIProvider)
	}
	if err := cfg.ValidateForStartup(); err == nil {
		t.Fatal("expected startup failure")
	}
}

func TestLoadDevelopmentDefaultsMock(t *testing.T) {
	t.Setenv("YOUSHU_ENV", config.EnvDevelopment)
	t.Setenv("UPSTREAM_AI_PROVIDER", "")
	cfg := config.Load()
	if cfg.UpstreamAIProvider != config.UpstreamMock {
		t.Fatalf("provider=%q want mock", cfg.UpstreamAIProvider)
	}
}

func TestListenAddrDefaultsAllInterfaces(t *testing.T) {
	cfg := config.Config{Port: "8080"}
	if got, want := cfg.ListenAddr(), ":8080"; got != want {
		t.Fatalf("ListenAddr()=%q want %q", got, want)
	}
}

func TestListenAddrLocalhostBind(t *testing.T) {
	cfg := config.Config{BindAddr: "127.0.0.1", Port: "8080"}
	if got, want := cfg.ListenAddr(), "127.0.0.1:8080"; got != want {
		t.Fatalf("ListenAddr()=%q want %q", got, want)
	}
}

func TestLoadBindAddrFromEnv(t *testing.T) {
	t.Setenv("BIND_ADDR", "127.0.0.1")
	t.Setenv("PORT", "9090")
	cfg := config.Load()
	if cfg.BindAddr != "127.0.0.1" {
		t.Fatalf("BindAddr=%q", cfg.BindAddr)
	}
	if got, want := cfg.ListenAddr(), "127.0.0.1:9090"; got != want {
		t.Fatalf("ListenAddr()=%q want %q", got, want)
	}
}

func unsetYOUSHUEnv(t *testing.T) {
	t.Helper()
	_ = os.Unsetenv("YOUSHU_ENV")
}
