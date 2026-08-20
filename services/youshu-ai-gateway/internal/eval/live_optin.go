package eval

import (
	"fmt"
	"os"
	"strings"

	"github.com/youshu/youshu-ai-gateway/internal/config"
)

const (
	EnvEvalLive              = "YOUSHU_EVAL_LIVE"
	EnvEvalSmokeV2           = "YOUSHU_EVAL_SMOKE_V2"
	EnvEvalConnectivityProbe = "YOUSHU_EVAL_CONNECTIVITY_PROBE"
	EnvEvalFull              = "YOUSHU_EVAL_FULL"
	EnvEvalPilot             = "YOUSHU_EVAL_PILOT"
	EnvEvalE01Diagnostic     = "YOUSHU_EVAL_E01_DIAGNOSTIC"
	EnvEvalC2CTargeted       = "YOUSHU_EVAL_C2C_TARGETED"
)

// IsLiveEvalOptIn reports whether explicit live evaluation opt-in is enabled.
func IsLiveEvalOptIn() bool {
	return envFlagEnabled(EnvEvalLive)
}

func envFlagEnabled(name string) bool {
	v := strings.TrimSpace(os.Getenv(name))
	return v == "1" || strings.EqualFold(v, "true")
}

// IsSmokeV2ModeEnv reports whether smoke v2 mode is explicitly requested.
func IsSmokeV2ModeEnv() bool {
	return envFlagEnabled(EnvEvalSmokeV2)
}

// IsConnectivityProbeModeEnv reports whether connectivity probe mode is explicitly requested.
func IsConnectivityProbeModeEnv() bool {
	return envFlagEnabled(EnvEvalConnectivityProbe)
}

// IsFullEvalModeEnv reports whether full live evaluation mode is explicitly requested.
func IsFullEvalModeEnv() bool {
	return envFlagEnabled(EnvEvalFull)
}

// IsE01DiagnosticModeEnv reports whether E01 targeted diagnostic mode is explicitly requested.
func IsE01DiagnosticModeEnv() bool {
	return envFlagEnabled(EnvEvalE01Diagnostic)
}

// IsPilotModeEnv reports whether pilot live evaluation mode is explicitly requested.
func IsPilotModeEnv() bool {
	return envFlagEnabled(EnvEvalPilot)
}

// IsC2CTargetedModeEnv reports whether C2C keyFact targeted verification is explicitly requested.
func IsC2CTargetedModeEnv() bool {
	return envFlagEnabled(EnvEvalC2CTargeted)
}

// LiveRunGate summarizes why a live run is or is not executable.
type LiveRunGate struct {
	Eligible    bool
	RunStatus   string
	BlockReason string
}

// ResolveLiveRunGate enforces explicit live opt-in, run mode, and credential readiness.
func ResolveLiveRunGate(cfg config.Config, plan EvaluationRunPlan) LiveRunGate {
	if !IsLiveEvalOptIn() {
		return LiveRunGate{
			RunStatus:   RunStatusNotRequested,
			BlockReason: "live evaluation not requested (set YOUSHU_EVAL_LIVE=1)",
		}
	}
	if reason := validateLiveRunMode(plan); reason != "" {
		return LiveRunGate{
			RunStatus:   RunStatusNotRequested,
			BlockReason: reason,
		}
	}

	cred := CheckLiveCredentials(cfg)
	if !cred.Configured {
		return LiveRunGate{
			RunStatus:   RunStatusConfigurationBlocked,
			BlockReason: fmt.Sprintf("missing required config: %s", strings.Join(cred.Missing, ", ")),
		}
	}
	return LiveRunGate{Eligible: true, RunStatus: RunStatusExecuted}
}

func validateLiveRunMode(plan EvaluationRunPlan) string {
	switch plan.Type {
	case RunPlanTypeSmokeV2:
		if !IsSmokeV2ModeEnv() {
			return "smoke v2 not requested (set YOUSHU_EVAL_SMOKE_V2=1)"
		}
	case RunPlanTypeConnectivityProbe:
		if !IsConnectivityProbeModeEnv() {
			return "connectivity probe not requested (set YOUSHU_EVAL_CONNECTIVITY_PROBE=1)"
		}
	case RunPlanTypeE01Diagnostic:
		if !IsE01DiagnosticModeEnv() {
			return "E01 targeted diagnostic not requested (set YOUSHU_EVAL_E01_DIAGNOSTIC=1)"
		}
	case RunPlanTypeFull:
		if !IsFullEvalModeEnv() {
			return "full evaluation not requested (set YOUSHU_EVAL_FULL=1)"
		}
	case RunPlanTypePilot:
		if !IsPilotModeEnv() {
			return "pilot evaluation not requested (set YOUSHU_EVAL_PILOT=1)"
		}
	case RunPlanTypeC2CTargeted:
		if !IsC2CTargetedModeEnv() {
			return "C2C targeted verification not requested (set YOUSHU_EVAL_C2C_TARGETED=1)"
		}
	}
	return ""
}

// RequireLiveEvalOptIn returns a skip reason when live opt-in is absent.
func RequireLiveEvalOptIn() string {
	if IsLiveEvalOptIn() {
		return ""
	}
	return "YOUSHU_EVAL_LIVE=1 required for live evaluation (credentials alone are insufficient)"
}
