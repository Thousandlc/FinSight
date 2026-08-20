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

// StructuredLogging emits safe request metadata. Never logs bodies or financial context.
func StructuredLogging(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		started := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)

		requestID := strings.TrimSpace(r.Header.Get("X-Youshu-Request-Id"))
		observability.Log(observability.Entry{
			Event:      "http_request",
			RequestID:  requestID,
			Route:      r.URL.Path,
			HTTPStatus: rec.status,
			DurationMs: time.Since(started).Milliseconds(),
		})
	})
}
