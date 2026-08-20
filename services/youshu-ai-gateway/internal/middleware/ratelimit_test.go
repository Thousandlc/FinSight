package middleware_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/middleware"
)

type fakeClock struct {
	now time.Time
}

func (c *fakeClock) Now() time.Time { return c.now }

func TestFixedWindowWithinLimit(t *testing.T) {
	clock := &fakeClock{now: time.Unix(0, 0)}
	rl := middleware.NewFixedWindowRateLimiter(middleware.RateLimitOptions{
		Limit:  2,
		Window: time.Minute,
		Clock:  clock,
	})
	next := http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})
	h := rl.Middleware(next)

	for i := 0; i < 2; i++ {
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/v1/ai/financial-assistant", nil))
		if rec.Code != http.StatusOK {
			t.Fatalf("request %d status=%d", i, rec.Code)
		}
	}
}

func TestFixedWindowExceedReturnsGateway429(t *testing.T) {
	clock := &fakeClock{now: time.Unix(0, 0)}
	rl := middleware.NewFixedWindowRateLimiter(middleware.RateLimitOptions{
		Limit:  1,
		Window: time.Minute,
		Clock:  clock,
	})
	h := rl.Middleware(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/v1/ai/financial-assistant", nil))
	rec2 := httptest.NewRecorder()
	h.ServeHTTP(rec2, httptest.NewRequest(http.MethodPost, "/v1/ai/financial-assistant", nil))

	if rec2.Code != http.StatusTooManyRequests {
		t.Fatalf("status=%d", rec2.Code)
	}
	if rec2.Header().Get("Retry-After") == "" {
		t.Fatal("missing Retry-After header")
	}
	var envelope contract.ErrorEnvelope
	if err := json.NewDecoder(rec2.Body).Decode(&envelope); err != nil {
		t.Fatal(err)
	}
	if envelope.Error.Code != contract.ErrGatewayRateLimited {
		t.Fatalf("code=%q", envelope.Error.Code)
	}
}

func TestFixedWindowResetsAfterWindow(t *testing.T) {
	start := time.Unix(0, 0)
	clock := &fakeClock{now: start}
	rl := middleware.NewFixedWindowRateLimiter(middleware.RateLimitOptions{
		Limit:  1,
		Window: time.Minute,
		Clock:  clock,
	})
	h := rl.Middleware(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/v1/ai/financial-assistant", nil))
	rec2 := httptest.NewRecorder()
	h.ServeHTTP(rec2, httptest.NewRequest(http.MethodPost, "/v1/ai/financial-assistant", nil))
	if rec2.Code != http.StatusTooManyRequests {
		t.Fatalf("expected first window block status=%d", rec2.Code)
	}

	clock.now = start.Add(time.Minute)
	rec3 := httptest.NewRecorder()
	h.ServeHTTP(rec3, httptest.NewRequest(http.MethodPost, "/v1/ai/financial-assistant", nil))
	if rec3.Code != http.StatusOK {
		t.Fatalf("expected reset status=%d", rec3.Code)
	}
}

func TestHealthBypassesRateLimit(t *testing.T) {
	clock := &fakeClock{now: time.Unix(0, 0)}
	rl := middleware.NewFixedWindowRateLimiter(middleware.RateLimitOptions{
		Limit:  1,
		Window: time.Minute,
		Clock:  clock,
	})
	h := rl.Middleware(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	for i := 0; i < 5; i++ {
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/health", nil))
		if rec.Code != http.StatusOK {
			t.Fatalf("health request %d status=%d", i, rec.Code)
		}
	}
}

func TestRateLimiterConcurrentRaceSafe(t *testing.T) {
	clock := &fakeClock{now: time.Unix(0, 0)}
	rl := middleware.NewFixedWindowRateLimiter(middleware.RateLimitOptions{
		Limit:  100,
		Window: time.Minute,
		Clock:  clock,
	})
	h := rl.Middleware(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	}))

	var wg sync.WaitGroup
	for i := 0; i < 50; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			rec := httptest.NewRecorder()
			h.ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/v1/ai/financial-assistant", nil))
		}()
	}
	wg.Wait()
}
