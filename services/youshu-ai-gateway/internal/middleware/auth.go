package middleware

import (
	"crypto/subtle"
	"encoding/json"
	"net/http"
	"strings"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/observability"
)

func Auth(clientToken string, next http.Handler) http.Handler {
	token := strings.TrimSpace(clientToken)
	if token == "" {
		return next
	}
	expected := []byte("Bearer " + token)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		auth := r.Header.Get("Authorization")
		if subtle.ConstantTimeCompare([]byte(auth), expected) != 1 {
			if rec := observability.FromContext(r.Context()); rec != nil {
				rec.Fail(observability.Classify(observability.CodeUnauthorized, observability.StageGatewayAuth))
			}
			writeAuthError(w, requestIDFromContextOrHeader(r))
			return
		}
		next.ServeHTTP(w, r)
	})
}

func writeAuthError(w http.ResponseWriter, requestID string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusUnauthorized)
	resp := contract.ErrorEnvelope{
		SchemaVersion: "v1",
		RequestID:     requestID,
		Error: contract.GatewayErrorBody{
			Code:    contract.ErrUnauthorized,
			Message: "未授权访问。",
		},
	}
	_ = json.NewEncoder(w).Encode(resp)
}

func requestIDFromContextOrHeader(r *http.Request) string {
	if id := observability.RequestIDFromContext(r.Context()); id != "" {
		return id
	}
	return strings.TrimSpace(r.Header.Get("X-Youshu-Request-Id"))
}
