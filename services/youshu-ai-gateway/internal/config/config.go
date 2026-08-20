package config

import (
	"fmt"
	"net"
	"net/url"
	"os"
	"strconv"
	"strings"
)

const (
	UpstreamMock    = "mock"
	UpstreamBailian = "bailian"

	StructuredOutputJSONObject       = "json_object"
	StructuredOutputJSONSchemaStrict = "json_schema_strict"

	defaultRateLimitRequests      = 60
	defaultRateLimitWindowSeconds = 60
	defaultUpstreamMaxRetries     = 2
	defaultRetryBaseDelayMS       = 500
	defaultRetryMaxDelayMS        = 8000
	defaultUpstreamMaxConcurrency = 4
	defaultReadHeaderTimeoutSec   = 5
	defaultReadTimeoutSec         = 30
	defaultWriteTimeoutSec        = 60
	defaultIdleTimeoutSec         = 120
	defaultShutdownTimeoutSec     = 30
)

type Config struct {
	EnvMode              string
	BindAddr             string
	Port                 string
	SchemaVersion        string
	ModelAlias           string
	BuildVersion         string
	GatewayClientToken   string
	RateLimitRequests    int
	RateLimitWindowSec   int
	UpstreamAIProvider   string
	BailianAPIKey        string
	BailianBaseURL       string
	BailianModel         string
	BailianTimeoutSecond int
	BailianStructuredOutputMode string
	UpstreamMaxRetries   int
	RetryBaseDelayMS     int
	RetryMaxDelayMS      int
	UpstreamMaxConcurrency int
	ReadHeaderTimeoutSec int
	ReadTimeoutSec       int
	WriteTimeoutSec      int
	IdleTimeoutSec       int
	ShutdownTimeoutSec   int
	TrustedProxyCIDRs    []string
	SmokeDumpRaw         bool
}

func Load() Config {
	envMode := normalizeEnvMode(os.Getenv("YOUSHU_ENV"))

	rateLimitRequests := intFromEnv("RATE_LIMIT_REQUESTS", 0)
	if rateLimitRequests <= 0 {
		rateLimitRequests = intFromEnv("RATE_LIMIT_PER_MINUTE", defaultRateLimitRequests)
	}
	rateLimitWindow := intFromEnv("RATE_LIMIT_WINDOW_SECONDS", defaultRateLimitWindowSeconds)

	timeout := intFromEnv("BAILIAN_TIMEOUT_SECONDS", 25)
	port := strings.TrimSpace(os.Getenv("PORT"))
	if port == "" {
		port = "8080"
	}
	bindAddr := strings.TrimSpace(os.Getenv("BIND_ADDR"))
	schema := strings.TrimSpace(os.Getenv("SCHEMA_VERSION"))
	if schema == "" {
		schema = "v1"
	}
	modelAlias := strings.TrimSpace(os.Getenv("MODEL_ALIAS"))
	if modelAlias == "" {
		modelAlias = "mock-qwen"
	}

	upstream := strings.TrimSpace(os.Getenv("UPSTREAM_AI_PROVIDER"))
	if upstream == "" {
		if envMode == EnvProduction {
			upstream = ""
		} else {
			upstream = UpstreamMock
		}
	}

	structuredMode := strings.TrimSpace(os.Getenv("BAILIAN_STRUCTURED_OUTPUT_MODE"))
	if structuredMode == "" {
		structuredMode = StructuredOutputJSONObject
	}

	buildVersion := strings.TrimSpace(os.Getenv("BUILD_VERSION"))
	if buildVersion == "" {
		buildVersion = strings.TrimSpace(os.Getenv("VERSION"))
	}
	if buildVersion == "" && envMode != EnvProduction {
		buildVersion = "dev"
	}

	var trusted []string
	if raw := strings.TrimSpace(os.Getenv("TRUSTED_PROXY_CIDRS")); raw != "" {
		for _, part := range strings.Split(raw, ",") {
			if trimmed := strings.TrimSpace(part); trimmed != "" {
				trusted = append(trusted, trimmed)
			}
		}
	}

	return Config{
		EnvMode:                     envMode,
		BindAddr:                    bindAddr,
		Port:                        port,
		SchemaVersion:               schema,
		ModelAlias:                  modelAlias,
		BuildVersion:                buildVersion,
		GatewayClientToken:          strings.TrimSpace(os.Getenv("GATEWAY_CLIENT_TOKEN")),
		RateLimitRequests:           rateLimitRequests,
		RateLimitWindowSec:          rateLimitWindow,
		UpstreamAIProvider:          upstream,
		BailianAPIKey:               strings.TrimSpace(os.Getenv("BAILIAN_API_KEY")),
		BailianBaseURL:              strings.TrimSpace(os.Getenv("BAILIAN_BASE_URL")),
		BailianModel:                strings.TrimSpace(os.Getenv("BAILIAN_MODEL")),
		BailianTimeoutSecond:        timeout,
		BailianStructuredOutputMode: structuredMode,
		UpstreamMaxRetries:          intFromEnv("UPSTREAM_MAX_RETRIES", defaultUpstreamMaxRetries),
		RetryBaseDelayMS:            intFromEnv("UPSTREAM_RETRY_BASE_DELAY_MS", defaultRetryBaseDelayMS),
		RetryMaxDelayMS:             intFromEnv("UPSTREAM_RETRY_MAX_DELAY_MS", defaultRetryMaxDelayMS),
		UpstreamMaxConcurrency:      intFromEnv("UPSTREAM_MAX_CONCURRENCY", defaultUpstreamMaxConcurrency),
		ReadHeaderTimeoutSec:        intFromEnv("HTTP_READ_HEADER_TIMEOUT_SECONDS", defaultReadHeaderTimeoutSec),
		ReadTimeoutSec:              intFromEnv("HTTP_READ_TIMEOUT_SECONDS", defaultReadTimeoutSec),
		WriteTimeoutSec:             intFromEnv("HTTP_WRITE_TIMEOUT_SECONDS", defaultWriteTimeoutSec),
		IdleTimeoutSec:              intFromEnv("HTTP_IDLE_TIMEOUT_SECONDS", defaultIdleTimeoutSec),
		ShutdownTimeoutSec:          intFromEnv("SHUTDOWN_TIMEOUT_SECONDS", defaultShutdownTimeoutSec),
		TrustedProxyCIDRs:           trusted,
		SmokeDumpRaw:                os.Getenv("YOUSHU_SMOKE_DUMP_RAW") == "1",
	}
}

func intFromEnv(key string, fallback int) int {
	raw := strings.TrimSpace(os.Getenv(key))
	if raw == "" {
		return fallback
	}
	n, err := strconv.Atoi(raw)
	if err != nil || n <= 0 {
		return fallback
	}
	return n
}

func (c Config) ValidateUpstream() error {
	switch c.UpstreamAIProvider {
	case UpstreamMock:
		return nil
	case UpstreamBailian:
		if c.BailianAPIKey == "" {
			return fmt.Errorf("UPSTREAM_AI_PROVIDER=bailian requires BAILIAN_API_KEY")
		}
		if c.BailianBaseURL == "" {
			return fmt.Errorf("UPSTREAM_AI_PROVIDER=bailian requires BAILIAN_BASE_URL")
		}
		if _, err := url.ParseRequestURI(c.BailianBaseURL); err != nil {
			return fmt.Errorf("BAILIAN_BASE_URL invalid: %w", err)
		}
		if c.BailianModel == "" {
			return fmt.Errorf("UPSTREAM_AI_PROVIDER=bailian requires BAILIAN_MODEL")
		}
		switch c.BailianStructuredOutputMode {
		case "", StructuredOutputJSONObject, StructuredOutputJSONSchemaStrict:
		default:
			return fmt.Errorf("unsupported BAILIAN_STRUCTURED_OUTPUT_MODE: %q", c.BailianStructuredOutputMode)
		}
		return nil
	case "":
		return fmt.Errorf("UPSTREAM_AI_PROVIDER is required")
	default:
		return fmt.Errorf("unsupported UPSTREAM_AI_PROVIDER: %q (allowed: mock, bailian)", c.UpstreamAIProvider)
	}
}

// ValidateForStartup enforces production safety and infrastructure tunables.
func (c Config) ValidateForStartup() error {
	if c.BailianTimeoutSecond <= 0 {
		return fmt.Errorf("BAILIAN_TIMEOUT_SECONDS must be > 0")
	}
	if c.RateLimitRequests <= 0 {
		return fmt.Errorf("RATE_LIMIT_REQUESTS must be > 0")
	}
	if c.RateLimitWindowSec <= 0 {
		return fmt.Errorf("RATE_LIMIT_WINDOW_SECONDS must be > 0")
	}
	if c.UpstreamMaxRetries < 0 {
		return fmt.Errorf("UPSTREAM_MAX_RETRIES must be >= 0")
	}
	if c.RetryBaseDelayMS <= 0 || c.RetryMaxDelayMS <= 0 {
		return fmt.Errorf("retry delay configuration must be > 0")
	}
	if c.RetryMaxDelayMS < c.RetryBaseDelayMS {
		return fmt.Errorf("UPSTREAM_RETRY_MAX_DELAY_MS must be >= UPSTREAM_RETRY_BASE_DELAY_MS")
	}
	if c.UpstreamMaxConcurrency <= 0 {
		return fmt.Errorf("UPSTREAM_MAX_CONCURRENCY must be > 0")
	}
	if c.ReadHeaderTimeoutSec <= 0 || c.ReadTimeoutSec <= 0 || c.WriteTimeoutSec <= 0 || c.IdleTimeoutSec <= 0 {
		return fmt.Errorf("HTTP server timeouts must be > 0")
	}
	if c.ShutdownTimeoutSec <= 0 {
		return fmt.Errorf("SHUTDOWN_TIMEOUT_SECONDS must be > 0")
	}

	if c.IsProduction() {
		if c.SmokeDumpRaw {
			return fmt.Errorf("YOUSHU_SMOKE_DUMP_RAW=1 is forbidden in production")
		}
		if c.UpstreamAIProvider == "" {
			return fmt.Errorf("production requires UPSTREAM_AI_PROVIDER=bailian")
		}
		if c.UpstreamAIProvider == UpstreamMock {
			return fmt.Errorf("production cannot use UPSTREAM_AI_PROVIDER=mock")
		}
		if c.GatewayClientToken == "" {
			return fmt.Errorf("production requires GATEWAY_CLIENT_TOKEN")
		}
		if strings.TrimSpace(c.BuildVersion) == "" {
			return fmt.Errorf("production requires BUILD_VERSION")
		}
		if isPlaceholderBuildVersion(c.BuildVersion) {
			return fmt.Errorf("production BUILD_VERSION cannot be placeholder %q", BuildVersionPlaceholder)
		}
	}

	if err := c.ValidateUpstream(); err != nil {
		return err
	}
	if c.UpstreamAIProvider == UpstreamMock && !c.AllowsMockUpstream() {
		return fmt.Errorf("UPSTREAM_AI_PROVIDER=mock is only allowed in development/test")
	}
	return nil
}

// Ready reports whether the process can accept AI traffic (no upstream probe).
func (c Config) Ready() (bool, string) {
	if err := c.ValidateForStartup(); err != nil {
		return false, err.Error()
	}
	if c.UpstreamAIProvider == UpstreamBailian {
		if c.BailianAPIKey == "" || c.BailianBaseURL == "" || c.BailianModel == "" {
			return false, "bailian credentials incomplete"
		}
	}
	return true, ""
}

// ListenAddr returns the HTTP listen address for the gateway process.
// When BIND_ADDR is empty, the server listens on all interfaces (":port").
func (c Config) ListenAddr() string {
	host := strings.TrimSpace(c.BindAddr)
	if host == "" {
		return ":" + c.Port
	}
	return net.JoinHostPort(host, c.Port)
}
