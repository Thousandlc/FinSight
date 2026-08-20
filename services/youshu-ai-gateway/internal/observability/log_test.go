package observability_test

import (
	"strings"
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/observability"
)

func TestRedactSecrets(t *testing.T) {
	raw := `{"Authorization":"Bearer sk-secret","note":"ok"}`
	redacted := observability.RedactSecrets(raw)
	if strings.Contains(redacted, "sk-secret") {
		t.Fatalf("secret leaked: %s", redacted)
	}
}

func TestLogEntryUsesGatewayServiceName(t *testing.T) {
	if observability.ServiceName != "finsight-ai-gateway" {
		t.Fatalf("ServiceName=%q", observability.ServiceName)
	}
}

func TestLogEntryNoFinancialFields(t *testing.T) {
	entry := observability.Entry{
		Event:            "provider_token_usage",
		RequestID:        "req-1",
		PromptTokens:     10,
		CompletionTokens: 5,
		TotalTokens:      15,
	}
	if entry.RequestID == "" {
		t.Fatal("expected request id")
	}
}
