package config

import "strings"

const (
	EnvDevelopment = "development"
	EnvTest        = "test"
	EnvProduction  = "production"
)

func normalizeEnvMode(raw string) string {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case EnvProduction:
		return EnvProduction
	case EnvTest:
		return EnvTest
	case EnvDevelopment, "":
		return EnvDevelopment
	default:
		return strings.ToLower(strings.TrimSpace(raw))
	}
}

func (c Config) IsProduction() bool {
	return c.EnvMode == EnvProduction
}

func (c Config) AllowsMockUpstream() bool {
	return c.EnvMode == EnvDevelopment || c.EnvMode == EnvTest
}

func (c Config) AllowsSmokeDump() bool {
	return !c.IsProduction()
}
