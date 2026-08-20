package provider_test

import (
	"context"
	"os"
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/config"
	"github.com/youshu/youshu-ai-gateway/internal/handler"
	"github.com/youshu/youshu-ai-gateway/internal/provider"
)

// Synthetic live smoke test — requires YOUSHU_EVAL_LIVE=1 in addition to Bailian credentials.
func TestBailianSyntheticSmoke(t *testing.T) {
	if os.Getenv("YOUSHU_EVAL_LIVE") != "1" {
		t.Skip("YOUSHU_EVAL_LIVE=1 required (credentials alone are insufficient)")
	}
	apiKey := os.Getenv("BAILIAN_API_KEY")
	baseURL := os.Getenv("BAILIAN_BASE_URL")
	model := os.Getenv("BAILIAN_MODEL")
	if apiKey == "" || baseURL == "" || model == "" {
		t.Skip("BAILIAN_API_KEY, BAILIAN_BASE_URL, BAILIAN_MODEL not configured")
	}

	cfg := config.Config{
		UpstreamAIProvider:   config.UpstreamBailian,
		BailianAPIKey:        apiKey,
		BailianBaseURL:       baseURL,
		BailianModel:         model,
		BailianTimeoutSecond: 25,
		SchemaVersion:        "v1",
		ModelAlias:           model,
	}
	if err := cfg.ValidateUpstream(); err != nil {
		t.Fatal(err)
	}

	upstream, err := provider.NewUpstream(cfg)
	if err != nil {
		t.Fatal(err)
	}

	env := sampleEnvelope()
	draft, err := upstream.CompleteMonthlySummary(context.Background(), env)
	if err != nil {
		t.Fatalf("bailian smoke failed: %v", err)
	}

	if err := handler.ValidateDraft(draft); err != nil {
		t.Fatalf("schema validation failed: %v", err)
	}

	t.Logf("smoke ok requestId=%s modelAlias=%s title=%q confidence=%v",
		env.RequestID, cfg.ModelAlias, draft.Title, draft.Confidence)
}
