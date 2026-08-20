package middleware

import (
	"crypto/subtle"
	"net/http"
	"strings"
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
			writeAuthError(w, "")
			return
		}
		next.ServeHTTP(w, r)
	})
}

func writeAuthError(w http.ResponseWriter, requestID string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusUnauthorized)
	if requestID == "" {
		_, _ = w.Write([]byte(`{"schemaVersion":"v1","requestId":"","error":{"code":"unauthorized","message":"未授权访问。"}}`))
		return
	}
	_, _ = w.Write([]byte(`{"schemaVersion":"v1","requestId":"` + requestID + `","error":{"code":"unauthorized","message":"未授权访问。"}}`))
}
