package provider_test

import (
	"context"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/provider"
)

type fixedJitter struct{ v float64 }

func (f fixedJitter) Float64() float64 { return f.v }

func TestUpstream429RetriesWithRetryAfter(t *testing.T) {
	var calls atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		n := calls.Add(1)
		if n == 1 {
			w.Header().Set("Retry-After", "1")
			w.WriteHeader(http.StatusTooManyRequests)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":` + jsonString(validDraftJSON()) + `}}]}`))
	}))
	t.Cleanup(server.Close)

	p := provider.NewBailianProvider(provider.BailianConfig{
		APIKey:  "test-key",
		BaseURL: server.URL,
		Model:   "qwen-plus",
		Timeout: 5 * time.Second,
		RetryPolicy: provider.RetryPolicy{
			MaxRetries: 1,
			BaseDelay:  10 * time.Millisecond,
			MaxDelay:   50 * time.Millisecond,
			Jitter:     fixedJitter{v: 0},
			Sleep: func(context.Context, time.Duration) error { return nil },
		},
		Concurrency: provider.NewConcurrencyLimiter(2),
	}, server.Client())

	_, err := p.CompleteMonthlySummary(context.Background(), sampleEnvelope())
	if err != nil {
		t.Fatal(err)
	}
	if calls.Load() != 2 {
		t.Fatalf("calls=%d want 2", calls.Load())
	}
}

func TestUpstream503RetriesThenSucceeds(t *testing.T) {
	var calls atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		if calls.Add(1) == 1 {
			w.WriteHeader(http.StatusServiceUnavailable)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"choices":[{"message":{"content":` + jsonString(validDraftJSON()) + `}}]}`))
	}))
	t.Cleanup(server.Close)

	p := newRetryTestProvider(t, server, 1)
	if _, err := p.CompleteMonthlySummary(context.Background(), sampleEnvelope()); err != nil {
		t.Fatal(err)
	}
	if calls.Load() != 2 {
		t.Fatalf("calls=%d", calls.Load())
	}
}

func TestUpstream401NoRetry(t *testing.T) {
	var calls atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		calls.Add(1)
		w.WriteHeader(http.StatusUnauthorized)
	}))
	t.Cleanup(server.Close)

	p := newRetryTestProvider(t, server, 2)
	_, err := p.CompleteMonthlySummary(context.Background(), sampleEnvelope())
	assertUpstreamCode(t, err, contract.ErrProviderUnavailable)
	if calls.Load() != 1 {
		t.Fatalf("calls=%d want 1", calls.Load())
	}
}

func TestUpstream400NoRetry(t *testing.T) {
	var calls atomic.Int32
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		calls.Add(1)
		w.WriteHeader(http.StatusBadRequest)
	}))
	t.Cleanup(server.Close)

	p := newRetryTestProvider(t, server, 2)
	_, err := p.CompleteMonthlySummary(context.Background(), sampleEnvelope())
	assertUpstreamCode(t, err, contract.ErrInvalidProviderResponse)
	if calls.Load() != 1 {
		t.Fatalf("calls=%d want 1", calls.Load())
	}
}

func TestContextDeadlineStopsRetry(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusServiceUnavailable)
	}))
	t.Cleanup(server.Close)

	p := newRetryTestProvider(t, server, 2)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Millisecond)
	defer cancel()
	_, err := p.CompleteMonthlySummary(ctx, sampleEnvelope())
	if err == nil {
		t.Fatal("expected error")
	}
}

func TestConcurrencyLimiterBlocksUntilRelease(t *testing.T) {
	limiter := provider.NewConcurrencyLimiter(1)
	ctx := context.Background()
	if err := limiter.Acquire(ctx); err != nil {
		t.Fatal(err)
	}
	done := make(chan error, 1)
	go func() {
		cctx, cancel := context.WithTimeout(context.Background(), 30*time.Millisecond)
		defer cancel()
		done <- limiter.Acquire(cctx)
	}()
	if err := <-done; err == nil {
		t.Fatal("expected acquire timeout")
	}
	limiter.Release()
	if err := limiter.Acquire(ctx); err != nil {
		t.Fatal(err)
	}
}

func newRetryTestProvider(t *testing.T, server *httptest.Server, maxRetries int) *provider.BailianProvider {
	t.Helper()
	return provider.NewBailianProvider(provider.BailianConfig{
		APIKey:  "test-key",
		BaseURL: server.URL,
		Model:   "qwen-plus",
		Timeout: 5 * time.Second,
		RetryPolicy: provider.RetryPolicy{
			MaxRetries: maxRetries,
			BaseDelay:  5 * time.Millisecond,
			MaxDelay:   20 * time.Millisecond,
			Jitter:     fixedJitter{v: 0},
			Sleep: func(context.Context, time.Duration) error { return nil },
		},
		Concurrency: provider.NewConcurrencyLimiter(4),
	}, server.Client())
}
