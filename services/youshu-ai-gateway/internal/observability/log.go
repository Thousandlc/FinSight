package observability

import (
	"encoding/json"
	"log"
	"strings"
	"time"

	"github.com/youshu/youshu-ai-gateway/internal/config"
)

const ServiceName = config.GatewayServiceName

// Entry is a safe structured production log record. Never include request bodies or financial data.
type Entry struct {
	Timestamp            string `json:"timestamp"`
	Service              string `json:"service"`
	RequestID            string `json:"requestId,omitempty"`
	Route                string `json:"route,omitempty"`
	HTTPStatus           int    `json:"httpStatus,omitempty"`
	DurationMs           int64  `json:"durationMs,omitempty"`
	Provider             string `json:"provider,omitempty"`
	Model                string `json:"model,omitempty"`
	ProviderAttemptCount int    `json:"providerAttemptCount,omitempty"`
	ProviderStatusClass  string `json:"providerStatusClass,omitempty"`
	FailureStage         string `json:"failureStage,omitempty"`
	RateLimitSource      string `json:"rateLimitSource,omitempty"`
	PromptTokens         int    `json:"promptTokens,omitempty"`
	CompletionTokens     int    `json:"completionTokens,omitempty"`
	TotalTokens          int    `json:"totalTokens,omitempty"`
	GatewayTotalMs       int64  `json:"gatewayTotalMs,omitempty"`
	ProviderTotalMs      int64  `json:"providerTotalMs,omitempty"`
	BackoffMs            int64  `json:"backoffMs,omitempty"`
	ErrorCode            string `json:"errorCode,omitempty"`
	Event                string `json:"event,omitempty"`
}

func Log(entry Entry) {
	if entry.Timestamp == "" {
		entry.Timestamp = time.Now().UTC().Format(time.RFC3339Nano)
	}
	if entry.Service == "" {
		entry.Service = ServiceName
	}
	payload, err := json.Marshal(entry)
	if err != nil {
		log.Printf(`{"service":"%s","event":"log_marshal_failed"}`, ServiceName)
		return
	}
	safe := RedactSecrets(string(payload))
	log.Print(safe)
}

func RedactSecrets(text string) string {
	replacements := []struct{ old, new string }{
		{"Bearer ", "Bearer [REDACTED]"},
		{"Authorization", "[REDACTED]"},
		{"sk-", "[REDACTED]-"},
	}
	out := text
	for _, r := range replacements {
		if strings.Contains(out, r.old) {
			out = strings.ReplaceAll(out, r.old, r.new)
		}
	}
	return out
}
