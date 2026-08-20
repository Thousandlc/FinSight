package provider

import (
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"
)

func parseRetryAfterHeader(h http.Header) *RetryAfterHint {
	raw := strings.TrimSpace(h.Get("Retry-After"))
	if raw == "" {
		return nil
	}
	if seconds, err := strconv.Atoi(raw); err == nil && seconds > 0 {
		return &RetryAfterHint{Seconds: seconds}
	}
	if when, err := http.ParseTime(raw); err == nil {
		seconds := int(time.Until(when).Seconds())
		if seconds < 1 {
			seconds = 1
		}
		return &RetryAfterHint{Seconds: seconds}
	}
	return nil
}

func mergeRetryAfter(header *RetryAfterHint, body []byte) *RetryAfterHint {
	if header != nil {
		return header
	}
	if body == nil {
		return nil
	}
	if retry := parseRetryAfter(body); retry != nil {
		return &RetryAfterHint{Seconds: *retry}
	}
	return nil
}

func readLimitedBody(resp *http.Response) ([]byte, error) {
	defer resp.Body.Close()
	return io.ReadAll(io.LimitReader(resp.Body, 1<<20))
}
