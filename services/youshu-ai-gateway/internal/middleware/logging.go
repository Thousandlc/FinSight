package middleware

import (
	"net/http"
	"strings"
	"time"

	"github.com/youshu/youshu-ai-gateway/internal/observability"
)

type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(code int) {
	r.status = code
	r.ResponseWriter.WriteHeader(code)
}

// StructuredLogging emits one canonical AI request completion event.
// Never logs bodies, prompts, financial context, or secrets.
func StructuredLogging(gatewayVersion string, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		started := time.Now()
		requestID := strings.TrimSpace(r.Header.Get("X-Youshu-Request-Id"))
		if requestID == "" {
			requestID = observability.NewRequestID()
			r.Header.Set("X-Youshu-Request-Id", requestID)
		}
		w.Header().Set("X-Youshu-Request-Id", requestID)

		rec := observability.NewRecorder()
		ctx := observability.WithRecorder(r.Context(), rec)
		ctx = observability.WithRequestID(ctx, requestID)
		status := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(status, r.WithContext(ctx))

		if !rec.HasOutcome() {
			if status.status >= 200 && status.status < 300 {
				rec.Success()
			} else {
				rec.Fail(observability.InferFromHTTPStatus(status.status))
			}
		}

		op, outcome, failureStage, errorCode, failureClass, retryability, provider, model, providerStatus, schemaStage, prompt, completion, total, retryCount := rec.Snapshot()
		if op == "" {
			op = observability.OperationUnknown
		}
		entry := observability.Entry{
			Event:            observability.EventAIRequest,
			RequestID:        requestID,
			Route:            r.URL.Path,
			HTTPStatus:       status.status,
			DurationMs:       time.Since(started).Milliseconds(),
			Operation:        op,
			Outcome:          outcome,
			Provider:         provider,
			Model:            model,
			ProviderStatus:   providerStatus,
			SchemaStage:      schemaStage,
			PromptTokens:     prompt,
			CompletionTokens: completion,
			TotalTokens:      total,
			RetryCount:       retryCount,
			GatewayVersion:   gatewayVersion,
		}
		if outcome != observability.OutcomeSuccess {
			entry.FailureStage = failureStage
			entry.ErrorCode = errorCode
			entry.FailureClass = failureClass
			entry.Retryability = retryability
		}
		observability.SafeLog(entry)
	})
}

// WrapFinancialAssistant is the production AI request middleware stack.
// Logging is outermost so auth and rate-limit failures emit a completion event.
func WrapFinancialAssistant(gatewayVersion, clientToken string, limiter *FixedWindowRateLimiter, next http.Handler) http.Handler {
	handler := next
	handler = Auth(clientToken, handler)
	if limiter != nil {
		handler = limiter.Middleware(handler)
	}
	return StructuredLogging(gatewayVersion, handler)
}
