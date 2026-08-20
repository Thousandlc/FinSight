package config

import "strings"

const (
	// GatewayServiceName is the production-facing runtime service identifier.
	GatewayServiceName = "finsight-ai-gateway"

	// BuildVersionPlaceholder must not appear in production runtime configuration.
	BuildVersionPlaceholder = "CHANGE_ME"
)

func isPlaceholderBuildVersion(version string) bool {
	return strings.EqualFold(strings.TrimSpace(version), BuildVersionPlaceholder)
}
