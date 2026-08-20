package handler

import (
	"encoding/json"
	"net/http"

	"github.com/youshu/youshu-ai-gateway/internal/config"
)

type HealthHandler struct {
	BuildVersion string
}

func (h *HealthHandler) ServeHTTP(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{
		"status":  "ok",
		"service": config.GatewayServiceName,
		"version": h.BuildVersion,
	})
}

type ReadinessHandler struct {
	Config config.Config
}

func (h *ReadinessHandler) ServeHTTP(w http.ResponseWriter, _ *http.Request) {
	ready, reason := h.Config.Ready()
	if !ready {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{
			"status": "not_ready",
			"reason": reason,
		})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{
		"status":   "ready",
		"service":  config.GatewayServiceName,
		"provider": h.Config.UpstreamAIProvider,
		"version":  h.Config.BuildVersion,
	})
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}
