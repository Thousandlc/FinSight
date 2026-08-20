package provider

import "fmt"

// UpstreamError carries a Gateway-safe error code. Cause is never exposed to clients.
type UpstreamError struct {
	Code       string
	Message    string
	RetryAfter *int
	Cause      error
}

func (e *UpstreamError) Error() string {
	if e.Cause != nil {
		return fmt.Sprintf("%s: %v", e.Code, e.Cause)
	}
	return e.Code
}

func upstreamErr(code string, cause error) *UpstreamError {
	return &UpstreamError{Code: code, Cause: cause}
}

func upstreamErrRetry(code string, retryAfter int, cause error) *UpstreamError {
	return &UpstreamError{Code: code, RetryAfter: &retryAfter, Cause: cause}
}
