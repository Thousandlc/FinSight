package middleware

import (
	"encoding/json"
	"net"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
)

// Clock provides time for deterministic rate limit tests.
type Clock interface {
	Now() time.Time
}

type realClock struct{}

func (realClock) Now() time.Time { return time.Now() }

// FixedWindowRateLimiter limits requests per client key within a fixed time window.
type FixedWindowRateLimiter struct {
	limit       int
	window      time.Duration
	clock       Clock
	mu          sync.Mutex
	buckets     map[string]*fixedWindowBucket
	clientKeyFn func(*http.Request) string
	bypassPaths map[string]struct{}
}

type fixedWindowBucket struct {
	windowStart time.Time
	count       int
}

type RateLimitOptions struct {
	Limit       int
	Window      time.Duration
	Clock       Clock
	ClientKey   func(*http.Request) string
	BypassPaths map[string]struct{}
}

func NewFixedWindowRateLimiter(opts RateLimitOptions) *FixedWindowRateLimiter {
	clock := opts.Clock
	if clock == nil {
		clock = realClock{}
	}
	clientKey := opts.ClientKey
	if clientKey == nil {
		clientKey = remoteAddrClientKey
	}
	bypass := opts.BypassPaths
	if bypass == nil {
		bypass = map[string]struct{}{
			"/health": {},
			"/ready":  {},
		}
	}
	return &FixedWindowRateLimiter{
		limit:       opts.Limit,
		window:      opts.Window,
		clock:       clock,
		buckets:     make(map[string]*fixedWindowBucket),
		clientKeyFn: clientKey,
		bypassPaths: bypass,
	}
}

func (rl *FixedWindowRateLimiter) Middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if _, ok := rl.bypassPaths[r.URL.Path]; ok {
			next.ServeHTTP(w, r)
			return
		}

		key := rl.clientKeyFn(r)
		now := rl.clock.Now()
		var allowed bool
		retryAfter := int(rl.window.Seconds())
		if retryAfter < 1 {
			retryAfter = 1
		}

		rl.mu.Lock()
		bucket := rl.buckets[key]
		if bucket == nil || now.Sub(bucket.windowStart) >= rl.window {
			bucket = &fixedWindowBucket{windowStart: now, count: 0}
			rl.buckets[key] = bucket
		}
		bucket.count++
		allowed = bucket.count <= rl.limit
		if !allowed {
			remaining := rl.window - now.Sub(bucket.windowStart)
			retryAfter = int(remaining.Seconds())
			if retryAfter < 1 {
				retryAfter = 1
			}
		}
		rl.mu.Unlock()

		if !allowed {
			writeGatewayRateLimit(w, requestIDFromRequest(r), retryAfter)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func writeGatewayRateLimit(w http.ResponseWriter, requestID string, retryAfter int) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Retry-After", strconv.Itoa(retryAfter))
	w.WriteHeader(http.StatusTooManyRequests)
	resp := contract.ErrorEnvelope{
		SchemaVersion: "v1",
		RequestID:     requestID,
		Error: contract.GatewayErrorBody{
			Code:              contract.ErrGatewayRateLimited,
			Message:           "请求过于频繁，请稍后再试。",
			RetryAfterSeconds: intPtr(retryAfter),
		},
	}
	_ = json.NewEncoder(w).Encode(resp)
}

func requestIDFromRequest(r *http.Request) string {
	return strings.TrimSpace(r.Header.Get("X-Youshu-Request-Id"))
}

func remoteAddrClientKey(r *http.Request) string {
	host, _, err := net.SplitHostPort(strings.TrimSpace(r.RemoteAddr))
	if err != nil {
		return strings.TrimSpace(r.RemoteAddr)
	}
	return host
}

func intPtr(v int) *int { return &v }
