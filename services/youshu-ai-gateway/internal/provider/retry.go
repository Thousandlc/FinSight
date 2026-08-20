package provider

import (
	"context"
	"math/rand"
	"net/http"
	"strings"
	"sync"
	"time"
)

// JitterSource returns a fraction in [0,1) for bounded jitter.
type JitterSource interface {
	Float64() float64
}

type randJitter struct{}

func (randJitter) Float64() float64 { return rand.Float64() }

// RetryPolicy configures bounded upstream retries.
type RetryPolicy struct {
	MaxRetries int
	BaseDelay  time.Duration
	MaxDelay   time.Duration
	Jitter     JitterSource
	Sleep      func(context.Context, time.Duration) error
}

func DefaultRetryPolicy(maxRetries, baseDelayMS, maxDelayMS int) RetryPolicy {
	return RetryPolicy{
		MaxRetries: maxRetries,
		BaseDelay:  time.Duration(baseDelayMS) * time.Millisecond,
		MaxDelay:   time.Duration(maxDelayMS) * time.Millisecond,
		Jitter:     randJitter{},
		Sleep:      sleepWithContext,
	}
}

func sleepWithContext(ctx context.Context, d time.Duration) error {
	timer := time.NewTimer(d)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-timer.C:
		return nil
	}
}

// RetryAfterHint captures provider-directed wait time.
type RetryAfterHint struct {
	Seconds int
}

func isTransientHTTPStatus(status int) bool {
	switch status {
	case http.StatusTooManyRequests, http.StatusBadGateway, http.StatusServiceUnavailable, http.StatusGatewayTimeout:
		return true
	default:
		return false
	}
}

func isTransientDoError(err error) bool {
	if err == nil {
		return false
	}
	if err == context.DeadlineExceeded || err == context.Canceled {
		return false
	}
	msg := strings.ToLower(err.Error())
	return strings.Contains(msg, "timeout") ||
		strings.Contains(msg, "connection reset") ||
		strings.Contains(msg, "temporary") ||
		strings.Contains(msg, "eof")
}

func computeBackoff(policy RetryPolicy, attemptIndex int, retryAfter *RetryAfterHint) time.Duration {
	if retryAfter != nil && retryAfter.Seconds > 0 {
		return time.Duration(retryAfter.Seconds) * time.Second
	}
	delay := policy.BaseDelay
	for i := 0; i < attemptIndex; i++ {
		delay *= 2
		if delay > policy.MaxDelay {
			delay = policy.MaxDelay
			break
		}
	}
	if policy.Jitter != nil {
		j := policy.Jitter.Float64()
		if j < 0 {
			j = 0
		}
		if j > 1 {
			j = 1
		}
		delay += time.Duration(float64(delay) * 0.25 * j)
	}
	if delay > policy.MaxDelay {
		delay = policy.MaxDelay
	}
	return delay
}

func hasRetryBudget(ctx context.Context, wait time.Duration) bool {
	deadline, ok := ctx.Deadline()
	if !ok {
		return true
	}
	return time.Now().Add(wait).Before(deadline)
}

// ConcurrencyLimiter bounds in-flight upstream calls for a single process.
type ConcurrencyLimiter struct {
	sem chan struct{}
}

func NewConcurrencyLimiter(max int) *ConcurrencyLimiter {
	if max <= 0 {
		max = 1
	}
	return &ConcurrencyLimiter{sem: make(chan struct{}, max)}
}

func (l *ConcurrencyLimiter) Acquire(ctx context.Context) error {
	select {
	case <-ctx.Done():
		return ctx.Err()
	case l.sem <- struct{}{}:
		return nil
	}
}

func (l *ConcurrencyLimiter) Release() {
	select {
	case <-l.sem:
	default:
	}
}

type attemptTracker struct {
	mu       sync.Mutex
	attempts int
	backoff  time.Duration
}

func (t *attemptTracker) nextAttempt() int {
	t.mu.Lock()
	defer t.mu.Unlock()
	t.attempts++
	return t.attempts
}

func (t *attemptTracker) addBackoff(d time.Duration) {
	t.mu.Lock()
	defer t.mu.Unlock()
	t.backoff += d
}

func (t *attemptTracker) snapshot() (attempts int, backoff time.Duration) {
	t.mu.Lock()
	defer t.mu.Unlock()
	return t.attempts, t.backoff
}
