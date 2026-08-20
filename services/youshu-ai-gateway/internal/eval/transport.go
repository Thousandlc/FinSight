package eval

import (
	"fmt"
	"strings"

	"github.com/youshu/youshu-ai-gateway/internal/provider"
)

const (
	ReadinessNotAssessed = "NOT_ASSESSED"
	ReadinessBlocked     = "BLOCKED"

	FailureRequestConstruction = "request-construction-failure"
	FailureConnection          = "connection-failure"
	FailureDNS                 = "dns-failure"
	FailureTLS                 = "tls-failure"
	FailureHTTPAuth            = "provider/http-auth"
	FailureHTTPBadRequest      = "provider/http-bad-request"
	FailureHTTPNotFound        = "provider/http-not-found"
	FailureHTTPRateLimit       = "provider/http-rate-limit"
	FailureHTTP5xx             = "provider/http-5xx"
	FailureProviderRejected    = "provider/http-rejected"
	FailureResponseRead        = "response-read-failure"
)

// TransportFailureDetail holds safe per-run transport diagnostics.
type TransportFailureDetail struct {
	FailureStage         string `json:"failureStage,omitempty"`
	ErrorCategory        string `json:"errorCategory,omitempty"`
	HTTPStatus           int    `json:"httpStatus,omitempty"`
	ProviderErrorCode    string `json:"providerErrorCode,omitempty"`
	ProviderErrorMessage string `json:"providerErrorMessage,omitempty"`
	RequestURLScheme     string `json:"requestURLScheme,omitempty"`
	RequestURLHost       string `json:"requestURLHost,omitempty"`
	RequestURLPath       string `json:"requestURLPath,omitempty"`
	RequestAttempted     bool   `json:"requestAttempted"`
	TransportStarted     bool   `json:"transportPerformStarted"`
	HTTPResponseReceived bool   `json:"httpResponseReceived"`
	HTTP2xxSuccess       bool   `json:"http2xxSuccess"`
	SelectedProvider     string `json:"selectedProvider,omitempty"`
	DurationMs           int64  `json:"durationMs,omitempty"`
}

// TransportStages extends contract stages with HTTP transport semantics.
type TransportStages struct {
	RequestAttempted     bool
	HTTPResponseReceived bool
	HTTP2xxSuccess       bool
	ErrorCategory        string
	HTTPStatus           int
	ProviderErrorCode    string
	ProviderErrorMessage string
	SelectedProvider     string
}

// BuildTransportFailureDetail maps provider diagnostics to eval-safe transport detail.
func BuildTransportFailureDetail(diag provider.DecodeDiagnostics) TransportFailureDetail {
	stage := transportFailureStage(diag)
	return TransportFailureDetail{
		FailureStage:         stage,
		ErrorCategory:        diag.ErrorCategory,
		HTTPStatus:           diag.HTTPStatus,
		ProviderErrorCode:    diag.ProviderErrorCode,
		ProviderErrorMessage: redactTransportText(diag.ProviderErrorMessage),
		RequestURLScheme:     diag.RequestURLScheme,
		RequestURLHost:       diag.RequestURLHost,
		RequestURLPath:       diag.RequestURLPath,
		RequestAttempted:     diag.RequestBuilt && diag.TransportPerformStarted,
		TransportStarted:     diag.TransportPerformStarted,
		HTTPResponseReceived: diag.HTTPResponseReceived,
		HTTP2xxSuccess:       diag.HTTP2xxSuccess,
		SelectedProvider:     diag.SelectedProvider,
		DurationMs:           diag.Latency.Milliseconds(),
	}
}

func redactTransportText(text string) string {
	if strings.Contains(text, "sk-") || strings.Contains(text, "Bearer ") {
		return "[REDACTED]"
	}
	return text
}

func transportFailureStage(diag provider.DecodeDiagnostics) string {
	switch {
	case !diag.RequestBuilt:
		return "requestConstruction"
	case !diag.TransportPerformStarted:
		return "requestConstruction"
	case !diag.HTTPResponseReceived:
		return "transport"
	case !diag.HTTP2xxSuccess:
		return "upstreamHTTP"
	case diag.ExplanationAlignment == provider.StageFail:
		return "explanationAlignment"
	case diag.DraftDTODecode != provider.StagePass:
		return "modelDecode"
	default:
		return ""
	}
}

// ModelResponseAssessed returns true when a contract-valid model response exists.
func ModelResponseAssessed(diag provider.DecodeDiagnostics, contractPass bool) bool {
	return diag.HTTP2xxSuccess && contractPass
}

// MapTransportStages extracts transport stage flags from diagnostics.
func MapTransportStages(diag provider.DecodeDiagnostics) TransportStages {
	return TransportStages{
		RequestAttempted:     diag.RequestBuilt && diag.TransportPerformStarted,
		HTTPResponseReceived: diag.HTTPResponseReceived,
		HTTP2xxSuccess:       diag.HTTP2xxSuccess,
		ErrorCategory:        diag.ErrorCategory,
		HTTPStatus:           diag.HTTPStatus,
		ProviderErrorCode:    diag.ProviderErrorCode,
		ProviderErrorMessage: diag.ProviderErrorMessage,
		SelectedProvider:     diag.SelectedProvider,
	}
}

// ClassifyTransportFailure maps transport diagnostics to failure classes.
func ClassifyTransportFailure(stages TransportStages, contract ContractStages) string {
	if contract.TimeoutStage != "" {
		return FailureTimeout
	}
	switch stages.ErrorCategory {
	case provider.ErrorCategoryRequestConstruction:
		return FailureRequestConstruction
	case provider.ErrorCategoryDNS:
		return FailureDNS
	case provider.ErrorCategoryConnection:
		return FailureConnection
	case provider.ErrorCategoryTLS:
		return FailureTLS
	case provider.ErrorCategoryTimeout:
		return FailureTimeout
	case provider.ErrorCategoryHTTP401, provider.ErrorCategoryHTTP403:
		return FailureHTTPAuth
	case provider.ErrorCategoryHTTP400:
		return FailureHTTPBadRequest
	case provider.ErrorCategoryHTTP404:
		return FailureHTTPNotFound
	case provider.ErrorCategoryHTTP429:
		return FailureHTTPRateLimit
	case provider.ErrorCategoryHTTP5xx:
		return FailureHTTP5xx
	case provider.ErrorCategoryProviderRejected:
		return FailureProviderRejected
	case provider.ErrorCategoryResponseRead:
		return FailureResponseRead
	}
	if stages.HTTPResponseReceived && !stages.HTTP2xxSuccess {
		return FailureProvider
	}
	if stages.RequestAttempted && !stages.HTTPResponseReceived {
		return FailureConnection
	}
	if !contract.HTTPSuccess && stages.RequestAttempted {
		return FailureConnection
	}
	return FailureNetwork
}

// SmokeReadinessVerdicts captures smoke-specific readiness dimensions.
type SmokeReadinessVerdicts struct {
	SmokeInfrastructureReadiness              string `json:"smokeInfrastructureReadiness"`
	SmokeModelStructuralContractReadiness     string `json:"smokeModelStructuralContractReadiness"`
	SmokeExplanationContractReadiness         string `json:"smokeExplanationContractReadiness"`
	SmokeFinalContractReadiness               string `json:"smokeFinalContractReadiness"`
	SmokeNarrativeReadiness                   string `json:"smokeNarrativeReadiness"`
	SmokeFullEvalReadiness                    string `json:"smokeFullEvalReadiness"`
}

// DeriveSmokeReadinessVerdicts computes smoke verdicts with zero-response semantics.
func DeriveSmokeReadinessVerdicts(metrics AggregateMetrics, analysis FullEvalAnalysis) SmokeReadinessVerdicts {
	if metrics.HTTP2xxSuccessCount == 0 {
		infra := ReadinessFail
		if metrics.RequestAttemptedCount == 0 {
			infra = ReadinessBlocked
		}
		return SmokeReadinessVerdicts{
			SmokeInfrastructureReadiness:      infra,
			SmokeExplanationContractReadiness: ReadinessNotAssessed,
			SmokeNarrativeReadiness:           ReadinessNotAssessed,
			SmokeFullEvalReadiness:            ReadinessBlocked,
		}
	}
	ac := analysis.V2Acceptance
	explanationRate := rate(metrics.ExplanationAlignmentPassCount, metrics.HTTP2xxSuccessCount)
	structuralRate := rate(metrics.ModelDTODecodeCount, metrics.HTTP2xxSuccessCount)
	finalContractRate := rate(metrics.ContractAmongHTTPSuccesses, metrics.HTTP2xxSuccessCount)

	explanationContractPass := metrics.HTTP2xxSuccessCount > 0 && explanationRate >= v2ExplanationCoverageThreshold
	structuralPass := metrics.HTTP2xxSuccessCount > 0 && structuralRate >= v2ContractComplianceThreshold
	finalContractPass := metrics.HTTP2xxSuccessCount > 0 && finalContractRate >= v2ContractComplianceThreshold

	narrativePass := ac.KnownNoDebtContradictionPass &&
		ac.MissingDebtOverconfidencePass &&
		ac.SafePlusMissingMisstatementPass &&
		ac.NarrativeSeverityMismatchPass &&
		ac.UnsupportedNarrativeRiskClaimPass &&
		analysis.ConfirmedModelFailures == 0

	infraPass := metrics.HTTPSuccessCount >= metrics.TotalRuns-1

	return SmokeReadinessVerdicts{
		SmokeInfrastructureReadiness:          passFail(infraPass),
		SmokeModelStructuralContractReadiness: passFailReadiness(structuralPass, metrics.ModelMetricsAssessed),
		SmokeExplanationContractReadiness:     passFailReadiness(explanationContractPass, metrics.ModelMetricsAssessed),
		SmokeFinalContractReadiness:           passFailReadiness(finalContractPass, metrics.ModelMetricsAssessed),
		SmokeNarrativeReadiness:               passFailReadiness(narrativePass, metrics.ModelMetricsAssessed),
		SmokeFullEvalReadiness: passFail(
			infraPass &&
				structuralPass &&
				explanationContractPass &&
				finalContractPass &&
				narrativePass &&
				ac.InventedAmountPass &&
				ac.InvalidFactSourcePass &&
				ac.InvalidReferencePass &&
				analysis.EvaluatorFalsePositives == 0,
		),
	}
}

func passFailReadiness(ok, assessed bool) string {
	if !assessed {
		return ReadinessNotAssessed
	}
	return passFail(ok)
}

// FormatRateValue renders a metric rate with N/A semantics.
func FormatRateValue(n, total int, assessed bool) string {
	if !assessed || total == 0 {
		return "N/A"
	}
	return formatPercent(rate(n, total))
}

func formatPercent(v float64) string {
	return fmt.Sprintf("%.1f%%", v*100)
}
