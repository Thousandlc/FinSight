package eval

// Legacy P0-4.4 baseline metrics retained for historical comparison only (non-gating in v2).
const (
	LegacyBaselineExpectedRiskMatchRate = 0.541
	LegacyBaselineContractAmongHTTPRate = 1.0
	LegacyMetricLabel                   = "Legacy Metric / Non-Gating"
)

// V2 acceptance thresholds (engineering gate for 37-run sample).
const (
	v2ContractComplianceThreshold     = 0.99
	v2ExplanationCoverageThreshold    = 0.99
	v2CitationAlignmentThreshold      = 0.99
	v2PolicyStructuralThreshold       = 1.0
)

// LegacyBaseline captures P0-4.4 historical metrics for comparison.
type LegacyBaseline struct {
	ExpectedRiskMatchRate float64 `json:"expectedRiskMatchRate"`
	ContractAmongHTTPRate float64 `json:"contractAmongHTTPSuccessesRate"`
	Note                  string  `json:"note"`
}

// ContractMetrics groups contract pipeline KPIs.
type ContractMetrics struct {
	HTTPSuccessRate                       float64 `json:"httpSuccessRate"`
	JSONValidRate                         float64 `json:"jsonValidRate"`
	ModelDTODecodeRate                    float64 `json:"modelDTODecodeRate"`
	ModelSchemaSuccessRate                float64 `json:"modelSchemaSuccessRate"`
	ExplanationAlignmentPassRate          float64 `json:"explanationAlignmentPassRate"`
	GatewayMappingSuccessRate             float64 `json:"gatewayMappingSuccessRate"`
	FinalValidatorPassRate                float64 `json:"finalValidatorPassRate"`
	ContractSuccessRateAmongHTTPSuccesses float64 `json:"contractSuccessRateAmongHTTPSuccesses"`
	FactValidationRate                    float64 `json:"factValidationRate"`
}

// ExplanationMetrics groups explanation fidelity KPIs.
type ExplanationMetrics struct {
	RiskExplanationCoverageRate            float64 `json:"riskExplanationCoverageRate"`
	UnknownExplanationCoverageRate         float64 `json:"unknownExplanationCoverageRate"`
	CitedFactKeyAlignmentRate              float64 `json:"citedFactKeyAlignmentRate"`
	MissingRiskExplanationCount            int     `json:"missingRiskExplanationCount"`
	UnsupportedRiskExplanationCount        int     `json:"unsupportedRiskExplanationCount"`
	MissingRequiredUnknownExplanationCount int     `json:"missingRequiredUnknownExplanationCount"`
	UnsupportedUnknownExplanationCount     int     `json:"unsupportedUnknownExplanationCount"`
	CitationMisalignmentCount              int     `json:"citationMisalignmentCount"`
}

// PolicyMetrics groups deterministic policy projection KPIs.
type PolicyMetrics struct {
	PolicyStructuralAlignmentRate float64 `json:"policyStructuralAlignmentRate"`
}

// FactSafetyMetrics groups fact safety counters.
type FactSafetyMetrics struct {
	InventedAmountCount       int `json:"inventedAmountCount"`
	InvalidCitedFactCount     int `json:"invalidCitedFactCount"`
	InvalidKeyFactSourceCount int `json:"invalidKeyFactSourceCount"`
	InvalidReferenceCount     int `json:"invalidReferenceCount"`
	ForbiddenClaimCount       int `json:"forbiddenClaimCount"`
}

// NarrativeMetrics groups narrative semantic KPIs.
type NarrativeMetrics struct {
	KnownNoDebtContradictionCount      int `json:"knownNoDebtContradictionCount"`
	MissingDebtOverconfidenceCount     int `json:"missingDebtOverconfidenceCount"`
	SafePlusMissingMisstatementCount   int `json:"safePlusMissingMisstatementCount"`
	NarrativeSeverityMismatchCount     int `json:"narrativeSeverityMismatchCount"`
	UnsupportedNarrativeRiskClaimCount int `json:"unsupportedNarrativeRiskClaimCount"`
}

// LatencyMetrics groups HTTP reliability metrics.
type LatencyMetrics struct {
	TimeoutRate              float64 `json:"timeoutRate"`
	LatencyP50Ms             int64   `json:"latencyP50Ms"`
	LatencyP95Ms             int64   `json:"latencyP95Ms"`
	LatencyMaxMs             int64   `json:"latencyMaxMs"`
	SlowRequestCountOver20s  int     `json:"slowRequestCountOver20s"`
	LatencyHTTPSuccessP50Ms  int64   `json:"latencyHTTPSuccessP50Ms"`
	LatencyHTTPSuccessP95Ms  int64   `json:"latencyHTTPSuccessP95Ms"`
	LatencyHTTPSuccessMaxMs  int64   `json:"latencyHTTPSuccessMaxMs"`
}

// TokenMetrics groups token usage totals and averages.
type TokenMetrics struct {
	PromptTokensAverage     float64 `json:"promptTokensAverage"`
	CompletionTokensAverage float64 `json:"completionTokensAverage"`
	TotalTokensAverage      float64 `json:"totalTokensAverage"`
	PromptTokensTotal       int     `json:"promptTokensTotal"`
	CompletionTokensTotal   int     `json:"completionTokensTotal"`
	TotalTokensTotal        int     `json:"totalTokensTotal"`
}

// AdjudicationMetrics summarizes evaluator adjudication outcomes.
type AdjudicationMetrics struct {
	ConfirmedModelFailures  int `json:"confirmedModelFailures"`
	EvaluatorFalsePositives int `json:"evaluatorFalsePositives"`
}

// V2AcceptanceComparison compares v2 metrics against gating thresholds.
type V2AcceptanceComparison struct {
	ContractCompliancePass              bool `json:"contractCompliancePass"`
	InventedAmountPass                  bool `json:"inventedAmountPass"`
	InvalidFactSourcePass               bool `json:"invalidFactSourcePass"`
	InvalidReferencePass                bool `json:"invalidReferencePass"`
	PolicyStructuralAlignmentPass       bool `json:"policyStructuralAlignmentPass"`
	ExplanationAlignmentPass            bool `json:"explanationAlignmentPass"`
	RiskExplanationCoveragePass         bool `json:"riskExplanationCoveragePass"`
	UnknownExplanationCoveragePass      bool `json:"unknownExplanationCoveragePass"`
	CitedFactKeyAlignmentPass           bool `json:"citedFactKeyAlignmentPass"`
	FinalValidatorPass                  bool `json:"finalValidatorPass"`
	KnownNoDebtContradictionPass        bool `json:"knownNoDebtContradictionPass"`
	MissingDebtOverconfidencePass       bool `json:"missingDebtOverconfidencePass"`
	SafePlusMissingMisstatementPass     bool `json:"safePlusMissingMisstatementPass"`
	NarrativeSeverityMismatchPass       bool `json:"narrativeSeverityMismatchPass"`
	UnsupportedNarrativeRiskClaimPass   bool `json:"unsupportedNarrativeRiskClaimPass"`
	LegacyRiskMatchPass                 bool `json:"legacyRiskMatchPass"`
	LegacyRiskMatchNonGating            bool `json:"legacyRiskMatchNonGating"`
}

// ReadinessVerdicts provides multi-dimensional readiness conclusions.
type ReadinessVerdicts struct {
	IntegrationReadiness         string `json:"integrationReadiness"`
	ExplanationContractReadiness string `json:"explanationContractReadiness"`
	NarrativeSemanticReadiness   string `json:"narrativeSemanticReadiness"`
	ProductionReadiness            string `json:"productionReadiness"`
}

// BuildV2MetricSections assembles structured v2 report sections from aggregate metrics.
func BuildV2MetricSections(metrics AggregateMetrics, analysis FullEvalAnalysis) (
	legacy LegacyBaseline,
	contract ContractMetrics,
	explanation ExplanationMetrics,
	policy PolicyMetrics,
	factSafety FactSafetyMetrics,
	narrative NarrativeMetrics,
	latency LatencyMetrics,
	tokens TokenMetrics,
	adjudication AdjudicationMetrics,
) {
	httpBase := metrics.HTTPSuccessCount
	contractBase := metrics.ContractAmongHTTPSuccesses
	v2ContractRuns := countV2ContractRuns(metrics)

	legacy = LegacyBaseline{
		ExpectedRiskMatchRate:   LegacyBaselineExpectedRiskMatchRate,
		ContractAmongHTTPRate: LegacyBaselineContractAmongHTTPRate,
		Note: "not directly comparable KPI — risk ownership moved from LLM to deterministic Policy",
	}

	contract = ContractMetrics{
		HTTPSuccessRate:                       rate(metrics.HTTPSuccessCount, metrics.TotalRuns),
		JSONValidRate:                         rate(metrics.JSONValidCount, httpBase),
		ModelDTODecodeRate:                    rate(metrics.ModelDTODecodeCount, httpBase),
		ModelSchemaSuccessRate:                rate(metrics.SchemaSuccessCount, httpBase),
		ExplanationAlignmentPassRate:          rate(metrics.ExplanationAlignmentPassCount, httpBase),
		GatewayMappingSuccessRate:             rate(metrics.ModelDTODecodeCount, httpBase),
		FinalValidatorPassRate:                rate(metrics.FinalValidatorPassCount, v2ContractRuns),
		ContractSuccessRateAmongHTTPSuccesses: rate(contractBase, httpBase),
		FactValidationRate:                    rate(metrics.FactValidationCount, httpBase),
	}

	explanation = ExplanationMetrics{
		RiskExplanationCoverageRate:            rate(metrics.RiskExplanationCoveragePassCount, v2ContractRuns),
		UnknownExplanationCoverageRate:         rate(metrics.UnknownExplanationCoveragePassCount, v2ContractRuns),
		CitedFactKeyAlignmentRate:              rate(metrics.CitationAlignmentPassCount, v2ContractRuns),
		MissingRiskExplanationCount:            metrics.MissingRiskExplanationCount,
		UnsupportedRiskExplanationCount:          metrics.UnsupportedRiskExplanationCount,
		MissingRequiredUnknownExplanationCount: metrics.MissingRequiredUnknownExplanationCount,
		UnsupportedUnknownExplanationCount:     metrics.UnsupportedUnknownExplanationCount,
	}

	policy = PolicyMetrics{
		PolicyStructuralAlignmentRate: rate(metrics.PolicyStructuralAlignmentPassCount, v2ContractRuns),
	}

	factSafety = FactSafetyMetrics{
		InventedAmountCount:       metrics.InventedAmountCount,
		InvalidCitedFactCount:     metrics.InvalidCitedFactCount,
		InvalidKeyFactSourceCount: metrics.InvalidKeyFactSourceCount,
		InvalidReferenceCount:     metrics.InvalidReferenceCount,
		ForbiddenClaimCount:       metrics.ForbiddenClaimCount,
	}

	narrative = NarrativeMetrics{
		KnownNoDebtContradictionCount:      metrics.KnownNoDebtContradictionCount,
		MissingDebtOverconfidenceCount:     metrics.MissingDebtOverconfidenceCount,
		SafePlusMissingMisstatementCount:   metrics.SafePlusMissingMisstatementCount,
		NarrativeSeverityMismatchCount:     metrics.NarrativeSeverityMismatchCount,
		UnsupportedNarrativeRiskClaimCount: metrics.UnsupportedNarrativeRiskClaimCount,
	}

	latency = LatencyMetrics{
		TimeoutRate:             rate(metrics.TimeoutCount, metrics.TotalRuns),
		LatencyP50Ms:            metrics.LatencyP50Ms,
		LatencyP95Ms:            metrics.LatencyP95Ms,
		LatencyMaxMs:            metrics.LatencyMaxMs,
		SlowRequestCountOver20s: metrics.SlowRequestCount,
		LatencyHTTPSuccessP50Ms: analysis.LatencyHTTPSuccessP50Ms,
		LatencyHTTPSuccessP95Ms: analysis.LatencyHTTPSuccessP95Ms,
		LatencyHTTPSuccessMaxMs: analysis.LatencyHTTPSuccessMaxMs,
	}

	tokens = TokenMetrics{
		PromptTokensAverage:     metrics.PromptTokensAverage,
		CompletionTokensAverage: metrics.CompletionTokensAverage,
		TotalTokensAverage:      metrics.TotalTokensAverage,
		PromptTokensTotal:       analysis.PromptTokensTotal,
		CompletionTokensTotal:   analysis.CompletionTokensTotal,
		TotalTokensTotal:        analysis.TotalTokensTotal,
	}

	adjudication = AdjudicationMetrics{
		ConfirmedModelFailures:  analysis.ConfirmedModelFailures,
		EvaluatorFalsePositives: analysis.EvaluatorFalsePositives,
	}
	return
}

func countV2ContractRuns(metrics AggregateMetrics) int {
	if metrics.FinalValidatorPassCount > 0 {
		return metrics.FinalValidatorPassCount +
			(metrics.PolicyStructuralPassCount - metrics.FinalValidatorPassCount)
	}
	if metrics.PolicyStructuralPassCount > 0 {
		return metrics.PolicyStructuralPassCount
	}
	if metrics.ContractAmongHTTPSuccesses > 0 {
		return metrics.ContractAmongHTTPSuccesses
	}
	return metrics.TotalRuns
}

func buildV2Acceptance(metrics AggregateMetrics, analysis FullEvalAnalysis) V2AcceptanceComparison {
	if !metrics.ModelMetricsAssessed {
		return V2AcceptanceComparison{LegacyRiskMatchNonGating: true}
	}
	_, contract, explanation, policy, factSafety, narrative, _, _, _ := BuildV2MetricSections(metrics, analysis)
	legacyRiskRate := rate(metrics.ExpectedRiskMatchCount, metrics.TotalRuns)
	return V2AcceptanceComparison{
		ContractCompliancePass:            contract.ContractSuccessRateAmongHTTPSuccesses >= v2ContractComplianceThreshold,
		ExplanationAlignmentPass:          contract.ExplanationAlignmentPassRate >= v2ExplanationCoverageThreshold,
		InventedAmountPass:                factSafety.InventedAmountCount == 0,
		InvalidFactSourcePass:             factSafety.InvalidKeyFactSourceCount == 0,
		InvalidReferencePass:              factSafety.InvalidReferenceCount == 0,
		PolicyStructuralAlignmentPass:     policy.PolicyStructuralAlignmentRate >= v2PolicyStructuralThreshold,
		RiskExplanationCoveragePass:       explanation.RiskExplanationCoverageRate >= v2ExplanationCoverageThreshold,
		UnknownExplanationCoveragePass:    explanation.UnknownExplanationCoverageRate >= v2ExplanationCoverageThreshold,
		CitedFactKeyAlignmentPass:         explanation.CitedFactKeyAlignmentRate >= v2CitationAlignmentThreshold,
		FinalValidatorPass:                contract.FinalValidatorPassRate >= v2ExplanationCoverageThreshold,
		KnownNoDebtContradictionPass:      narrative.KnownNoDebtContradictionCount == 0,
		MissingDebtOverconfidencePass:     narrative.MissingDebtOverconfidenceCount == 0,
		SafePlusMissingMisstatementPass:   narrative.SafePlusMissingMisstatementCount == 0,
		NarrativeSeverityMismatchPass:     narrative.NarrativeSeverityMismatchCount == 0,
		UnsupportedNarrativeRiskClaimPass: narrative.UnsupportedNarrativeRiskClaimCount == 0,
		LegacyRiskMatchPass:               legacyRiskRate >= riskMatchThreshold,
		LegacyRiskMatchNonGating:          true,
	}
}

func deriveV2ReadinessVerdicts(acceptance V2AcceptanceComparison, metrics AggregateMetrics) ReadinessVerdicts {
	if !metrics.ModelMetricsAssessed {
		infraPass := metrics.RequestAttemptedCount > 0
		return ReadinessVerdicts{
			IntegrationReadiness:         passFail(infraPass && metrics.HTTP2xxSuccessCount > 0),
			ExplanationContractReadiness: ReadinessNotAssessed,
			NarrativeSemanticReadiness:   ReadinessNotAssessed,
			ProductionReadiness:          ReadinessFail,
		}
	}

	integrationPass := acceptance.ContractCompliancePass &&
		acceptance.ExplanationAlignmentPass &&
		acceptance.InventedAmountPass &&
		acceptance.InvalidFactSourcePass &&
		acceptance.InvalidReferencePass

	explanationPass := acceptance.ExplanationAlignmentPass &&
		acceptance.PolicyStructuralAlignmentPass &&
		acceptance.RiskExplanationCoveragePass &&
		acceptance.UnknownExplanationCoveragePass &&
		acceptance.CitedFactKeyAlignmentPass &&
		acceptance.FinalValidatorPass

	narrativePass := acceptance.KnownNoDebtContradictionPass &&
		acceptance.MissingDebtOverconfidencePass &&
		acceptance.SafePlusMissingMisstatementPass &&
		acceptance.NarrativeSeverityMismatchPass &&
		acceptance.UnsupportedNarrativeRiskClaimPass

	productionPass := integrationPass && explanationPass && narrativePass

	return ReadinessVerdicts{
		IntegrationReadiness:         passFail(integrationPass),
		ExplanationContractReadiness: passFail(explanationPass),
		NarrativeSemanticReadiness:   passFail(narrativePass),
		ProductionReadiness:          passFail(productionPass),
	}
}

func passFail(ok bool) string {
	if ok {
		return ReadinessPass
	}
	return ReadinessFail
}
