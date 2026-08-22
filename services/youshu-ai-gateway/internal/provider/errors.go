package provider

import (
	"errors"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
)

// UpstreamError carries a Gateway-safe error code. Cause is never exposed to clients
// or production telemetry fields.
type UpstreamError struct {
	Code              string
	Message           string
	RetryAfter        *int
	Cause             error
	Stage             string
	ObservabilityCode string
	SchemaStage       string
	ProviderStatus    string
}

func (e *UpstreamError) Error() string {
	if e == nil {
		return ""
	}
	return e.Code
}

func (e *UpstreamError) Unwrap() error {
	if e == nil {
		return nil
	}
	return e.Cause
}

func (e *UpstreamError) TelemetryCode() string {
	if e == nil {
		return ""
	}
	if e.ObservabilityCode != "" {
		return e.ObservabilityCode
	}
	return e.Code
}

func upstreamErr(code string, cause error) *UpstreamError {
	return &UpstreamError{Code: code, Cause: cause}
}

func upstreamErrRetry(code string, retryAfter int, cause error) *UpstreamError {
	return &UpstreamError{Code: code, RetryAfter: &retryAfter, Cause: cause}
}

func annotateUpstream(err error, stage, obsCode, schemaStage, providerStatus string) error {
	if err == nil {
		return nil
	}
	var upstream *UpstreamError
	if errors.As(err, &upstream) {
		if stage != "" {
			upstream.Stage = stage
		}
		if obsCode != "" {
			upstream.ObservabilityCode = obsCode
		}
		if schemaStage != "" {
			upstream.SchemaStage = schemaStage
		}
		if providerStatus != "" {
			upstream.ProviderStatus = providerStatus
		}
		return upstream
	}
	httpCode := contract.ErrInvalidProviderResponse
	if obsCode == contract.ErrProviderTimeout || obsCode == contract.ErrProviderUnavailable || obsCode == contract.ErrInternalError {
		httpCode = obsCode
	}
	return &UpstreamError{
		Code:              httpCode,
		Cause:             err,
		Stage:             stage,
		ObservabilityCode: obsCode,
		SchemaStage:       schemaStage,
		ProviderStatus:    providerStatus,
	}
}
