package eval_test

import (
	"context"
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/config"
	"github.com/youshu/youshu-ai-gateway/internal/eval"
	"github.com/youshu/youshu-ai-gateway/internal/provider"
)

// TestLiveConnectivityProbe runs a single A01 live connectivity probe against Bailian.
// Requires YOUSHU_EVAL_LIVE=1 and YOUSHU_EVAL_CONNECTIVITY_PROBE=1.
func TestLiveConnectivityProbe(t *testing.T) {
	if reason := eval.RequireLiveEvalOptIn(); reason != "" {
		t.Skip(reason)
	}
	t.Setenv("YOUSHU_EVAL_CONNECTIVITY_PROBE", "1")
	t.Setenv("YOUSHU_EVAL_SMOKE_V2", "")

	cfg := config.Load()
	cfg.UpstreamAIProvider = config.UpstreamBailian

	opts := eval.ConnectivityProbeFilterOptions()
	plan, _, err := eval.BuildRunPlan(opts)
	if err != nil {
		t.Fatalf("BuildRunPlan: %v", err)
	}

	cred := eval.CheckLiveCredentials(cfg)
	if !cred.Configured {
		t.Skipf("Connectivity probe blocked: runStatus=%s missing=%v", eval.RunStatusConfigurationBlocked, cred.Missing)
	}
	if err := cfg.ValidateUpstream(); err != nil {
		t.Fatalf("config: %v", err)
	}

	upstream, err := provider.NewUpstream(cfg)
	if err != nil {
		t.Fatalf("upstream: %v", err)
	}
	bailian, ok := upstream.(*provider.BailianProvider)
	if !ok {
		t.Fatalf("expected BailianProvider, got %T", upstream)
	}

	preflight, err := eval.RunLivePreflight(cfg, plan)
	if err != nil {
		t.Fatalf("RunLivePreflight: %v", err)
	}
	t.Log(eval.FormatRunSummary(cfg, plan, preflight))
	if !preflight.Passed {
		t.Fatalf("preflight failed: %s", preflight.BlockReason)
	}

	report, err := eval.RunEvaluation(context.Background(), cfg, bailian, opts)
	if err != nil {
		t.Fatalf("RunEvaluation: %v", err)
	}
	if err := eval.ValidateRunPlanCompletion(plan, report); err != nil {
		t.Fatalf("run plan: %v", err)
	}
	if len(report.Results) != 1 {
		t.Fatalf("expected 1 result, got %d", len(report.Results))
	}

	r := report.Results[0]
	t.Logf("transport: attempted=%v response=%v http2xx=%v status=%d category=%s host=%s path=%s provider=%s",
		r.Transport.RequestAttempted, r.Transport.HTTPResponseReceived, r.Transport.HTTP2xxSuccess,
		r.Transport.HTTPStatus, r.Transport.ErrorCategory, r.Transport.RequestURLHost, r.Transport.RequestURLPath,
		r.Transport.SelectedProvider)
	if r.Transport.ProviderErrorCode != "" {
		t.Logf("providerError code=%s message=%s", r.Transport.ProviderErrorCode, r.Transport.ProviderErrorMessage)
	}

	writeResult, err := eval.WriteReport(report, eval.DefaultOutputDir)
	if err != nil {
		t.Fatalf("WriteReport: %v", err)
	}
	t.Log(report.Summary)
	t.Logf("report written to %s", writeResult.LatestPath)

	if !r.Transport.HTTP2xxSuccess {
		t.Fatalf("connectivity probe failed at transport layer: class=%s detail=%s", r.FailureClass, r.FailureDetail)
	}
	if !r.ContractPass {
		t.Fatalf("connectivity probe contract failed: class=%s", r.FailureClass)
	}
}
