package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/youshu/youshu-ai-gateway/internal/config"
	"github.com/youshu/youshu-ai-gateway/internal/handler"
	"github.com/youshu/youshu-ai-gateway/internal/middleware"
	"github.com/youshu/youshu-ai-gateway/internal/provider"
)

func main() {
	cfg := config.Load()
	if err := cfg.ValidateForStartup(); err != nil {
		log.Fatalf("invalid gateway configuration: %v", err)
	}

	upstream, err := provider.NewUpstream(cfg)
	if err != nil {
		log.Fatalf("upstream provider: %v", err)
	}

	financialHandler := &handler.FinancialAssistantHandler{
		SchemaVersion: cfg.SchemaVersion,
		ModelAlias:    cfg.ModelAlias,
		Upstream:      upstream,
	}

	var aiHandler http.Handler = financialHandler
	aiHandler = middleware.StructuredLogging(aiHandler)
	aiHandler = middleware.Auth(cfg.GatewayClientToken, aiHandler)

	rateLimiter := middleware.NewFixedWindowRateLimiter(middleware.RateLimitOptions{
		Limit:  cfg.RateLimitRequests,
		Window: time.Duration(cfg.RateLimitWindowSec) * time.Second,
	})
	aiHandler = rateLimiter.Middleware(aiHandler)

	rootMux := http.NewServeMux()
	rootMux.Handle("/health", &handler.HealthHandler{BuildVersion: cfg.BuildVersion})
	rootMux.Handle("/ready", &handler.ReadinessHandler{Config: cfg})
	rootMux.Handle("/v1/ai/financial-assistant", aiHandler)

	server := &http.Server{
		Addr:              cfg.ListenAddr(),
		Handler:           rootMux,
		ReadHeaderTimeout: time.Duration(cfg.ReadHeaderTimeoutSec) * time.Second,
		ReadTimeout:       time.Duration(cfg.ReadTimeoutSec) * time.Second,
		WriteTimeout:      time.Duration(cfg.WriteTimeoutSec) * time.Second,
		IdleTimeout:       time.Duration(cfg.IdleTimeoutSec) * time.Second,
	}

	go func() {
		log.Printf("%s listening on %s env=%s version=%s schema=%s model=%s upstream=%s auth=%t",
			config.GatewayServiceName, server.Addr, cfg.EnvMode, cfg.BuildVersion, cfg.SchemaVersion, cfg.ModelAlias, cfg.UpstreamAIProvider, cfg.GatewayClientToken != "")
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("server error: %v", err)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop

	ctx, cancel := context.WithTimeout(context.Background(), time.Duration(cfg.ShutdownTimeoutSec)*time.Second)
	defer cancel()
	if err := server.Shutdown(ctx); err != nil {
		log.Printf("graceful shutdown failed: %v", err)
	}
}
