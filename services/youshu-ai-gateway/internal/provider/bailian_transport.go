package provider

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"net/http"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
)

func (p *BailianProvider) performUpstreamHTTP(
	ctx context.Context,
	endpoint string,
	body []byte,
	tracker *attemptTracker,
) ([]byte, *http.Response, error) {
	policy := p.retryPolicy
	maxAttempts := policy.MaxRetries + 1

	var lastErr error
	for attempt := 0; attempt < maxAttempts; attempt++ {
		if attempt > 0 {
			wait := computeBackoff(policy, attempt-1, retryAfterFromError(lastErr))
			if !hasRetryBudget(ctx, wait) {
				if lastErr != nil {
					return nil, nil, lastErr
				}
				return nil, nil, upstreamErr(contract.ErrProviderTimeout, context.DeadlineExceeded)
			}
			if err := policy.Sleep(ctx, wait); err != nil {
				if lastErr != nil {
					return nil, nil, lastErr
				}
				return nil, nil, upstreamErr(contract.ErrProviderTimeout, err)
			}
			tracker.addBackoff(wait)
		}

		attemptNum := tracker.nextAttempt()
		_ = attemptNum

		httpReq, reqErr := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(body))
		if reqErr != nil {
			return nil, nil, upstreamErr(contract.ErrInternalError, reqErr)
		}
		httpReq.Header.Set("Authorization", "Bearer "+p.config.APIKey)
		httpReq.Header.Set("Content-Type", "application/json")

		resp, doErr := p.client.Do(httpReq)
		if doErr != nil {
			lastErr = classifyDoUpstreamError(doErr, ctx)
			if attempt < maxAttempts-1 && isTransientDoError(doErr) && ctx.Err() == nil {
				continue
			}
			return nil, nil, lastErr
		}

		respBody, readErr := readLimitedBody(resp)
		if readErr != nil {
			lastErr = upstreamErr(contract.ErrProviderUnavailable, readErr)
			return nil, nil, lastErr
		}

		if resp.StatusCode >= 200 && resp.StatusCode < 300 {
			return respBody, resp, nil
		}

		lastErr = mapHTTPStatus(resp.StatusCode, respBody, resp.Header)
		if attempt < maxAttempts-1 && isTransientHTTPStatus(resp.StatusCode) && ctx.Err() == nil {
			continue
		}
		return respBody, resp, lastErr
	}
	if lastErr != nil {
		return nil, nil, lastErr
	}
	return nil, nil, upstreamErr(contract.ErrProviderUnavailable, fmt.Errorf("upstream exhausted retries"))
}

func classifyDoUpstreamError(doErr error, ctx context.Context) error {
	if errors.Is(doErr, context.DeadlineExceeded) || ctx.Err() == context.DeadlineExceeded {
		return upstreamErr(contract.ErrProviderTimeout, doErr)
	}
	return upstreamErr(contract.ErrProviderUnavailable, doErr)
}

func retryAfterFromError(err error) *RetryAfterHint {
	var upstream *UpstreamError
	if errors.As(err, &upstream) && upstream.RetryAfter != nil {
		return &RetryAfterHint{Seconds: *upstream.RetryAfter}
	}
	return nil
}
