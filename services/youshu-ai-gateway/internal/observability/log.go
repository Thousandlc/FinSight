package observability

import (
	"encoding/json"
	"log"
	"strings"
	"sync"
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
	ProviderStatus       string `json:"providerStatus,omitempty"`
	FailureStage         string `json:"failureStage,omitempty"`
	RateLimitSource      string `json:"rateLimitSource,omitempty"`
	PromptTokens         *int   `json:"promptTokens,omitempty"`
	CompletionTokens     *int   `json:"completionTokens,omitempty"`
	TotalTokens          *int   `json:"totalTokens,omitempty"`
	RetryCount           *int   `json:"retryCount,omitempty"`
	GatewayTotalMs       int64  `json:"gatewayTotalMs,omitempty"`
	ProviderTotalMs      int64  `json:"providerTotalMs,omitempty"`
	BackoffMs            int64  `json:"backoffMs,omitempty"`
	ErrorCode            string `json:"errorCode,omitempty"`
	Event                string `json:"event,omitempty"`
	Operation            string `json:"operation,omitempty"`
	Outcome              string `json:"outcome,omitempty"`
	FailureClass         string `json:"failureClass,omitempty"`
	Retryability         string `json:"retryability,omitempty"`
	ValidatorFailureType string `json:"validatorFailureType,omitempty"`
	SchemaStage          string `json:"schemaStage,omitempty"`
	GatewayVersion       string `json:"gatewayVersion,omitempty"`
	CostSource           string `json:"costSource,omitempty"`
}

type Sink func(Entry)

var (
	sinkMu sync.Mutex
	sink   Sink
)

// SetSinkForTest replaces the production log sink. Restore with the returned func.
// Production request handling must not depend on sink success.
func SetSinkForTest(next Sink) func() {
	sinkMu.Lock()
	prev := sink
	sink = next
	sinkMu.Unlock()
	return func() {
		sinkMu.Lock()
		sink = prev
		sinkMu.Unlock()
	}
}

func Log(entry Entry) {
	SafeLog(entry)
}

// SafeLog emits a production entry and never panics. Sink/marshal failure is swallowed.
func SafeLog(entry Entry) {
	defer func() { _ = recover() }()
	if entry.Timestamp == "" {
		entry.Timestamp = time.Now().UTC().Format(time.RFC3339Nano)
	}
	if entry.Service == "" {
		entry.Service = ServiceName
	}
	entry.SchemaStage = SanitizeSchemaStage(entry.SchemaStage)
	entry.Provider = SanitizeProvider(entry.Provider)
	entry.Model = SanitizeModel(entry.Model)
	payload, err := json.Marshal(entry)
	if err != nil {
		log.Printf(`{"service":"%s","event":"log_marshal_failed"}`, ServiceName)
		return
	}
	safe := RedactSecrets(string(payload))
	sinkMu.Lock()
	current := sink
	sinkMu.Unlock()
	if current != nil {
		current(entry)
	}
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

func Int(v int) *int { return &v }
