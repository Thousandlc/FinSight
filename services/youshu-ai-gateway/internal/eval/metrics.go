package eval

import (
	"sort"
	"time"
)

// RunResult holds one evaluation run outcome.
type RunResult struct {
	CaseID    string
	Category  string
	RunIndex  int
	RequestID string

	ContractPass bool
	SemanticPass bool
	EndToEndPass bool

	FailureClass string
	FailureDetail string

	UpstreamModel    string
	LatencyMs        int64
	PromptTokens     int
	CompletionTokens int
	TotalTokens      int
	Timeout          bool

	InventedFacts         int
	InvalidCitedFactCount int
	InvalidKeyFactSource  int
	InvalidReferenceCount int
	InvalidActionCount    int
	ForbiddenClaimCount   int
	MissingConclusionCount int
	RiskMatch             bool
	UnknownBehaviorPass   bool

	ExplanationAlignmentPass bool
	ProvenanceAssemblyPass   bool
	PolicyStructuralPass     bool
	FinalValidatorPass       bool
	V2Semantic               V2SemanticResult `json:"v2Semantic,omitempty"`

	ContractStages ContractStages
	Semantic       SemanticResult

	Transport            TransportFailureDetail `json:"transport,omitempty"`
	ModelResponseAssessed bool                  `json:"modelResponseAssessed"`

	StructuredSnapshot StructuredSnapshot `json:"structuredSnapshot,omitempty"`
	DiagnosticSnapshot EvaluationDiagnosticSnapshot `json:"diagnosticSnapshot,omitempty"`
	AuditVerdict       SemanticAuditVerdict `json:"auditVerdict,omitempty"`
	FailureSeverity    string               `json:"failureSeverity,omitempty"`
	EvaluationVerdict  string               `json:"evaluationVerdict,omitempty"`
}

// AggregateMetrics summarizes all run results.
type AggregateMetrics struct {
	TotalRuns int

	RequestAttemptedCount     int
	HTTPResponseReceivedCount int
	HTTP2xxSuccessCount       int
	ModelMetricsAssessed      bool

	HTTPSuccessCount           int
	JSONValidCount             int
	ModelDTODecodeCount        int
	SchemaSuccessCount         int
	FactValidationCount        int
	ContractAmongHTTPSuccesses int
	EndToEndSuccessCount       int

	InventedAmountCount       int
	InvalidCitedFactCount     int
	InvalidKeyFactSourceCount int
	InvalidReferenceCount     int
	InvalidActionCount        int
	ForbiddenClaimCount       int
	MissingConclusionCount    int
	ExpectedRiskMatchCount    int
	UnknownBehaviorPassCount  int

	ExplanationAlignmentPassCount int
	PolicyStructuralPassCount     int
	FinalValidatorPassCount       int

	RiskExplanationCoveragePassCount      int
	UnknownExplanationCoveragePassCount int
	CitationAlignmentPassCount            int
	DeterministicProvenanceAssemblyPassCount int
	MissingRiskExplanationCount           int
	UnsupportedRiskExplanationCount       int
	MissingRequiredUnknownExplanationCount int
	UnsupportedUnknownExplanationCount    int
	PolicyStructuralAlignmentPassCount    int

	KnownNoDebtContradictionCount      int
	MissingDebtOverconfidenceCount     int
	SafePlusMissingMisstatementCount   int
	NarrativeSeverityMismatchCount     int
	UnsupportedNarrativeRiskClaimCount int

	TimeoutCount      int
	SlowRequestCount  int // >20s

	LatencyP50Ms int64
	LatencyP95Ms int64
	LatencyMaxMs int64

	PromptTokensAverage     float64
	CompletionTokensAverage float64
	TotalTokensAverage      float64

	FailureBreakdown map[string]int
	CasePassRate     map[string]float64
	WorstCases       []CaseScore
}

// CaseScore ranks cases by failure rate.
type CaseScore struct {
	CaseID     string
	Category   string
	TotalRuns  int
	Failures   int
	FailureRate float64
	TopFailure string
}

const slowRequestThreshold = 20 * time.Second

// ComputeMetrics aggregates run results into summary metrics.
func ComputeMetrics(results []RunResult, mode string) AggregateMetrics {
	m := AggregateMetrics{
		TotalRuns:        len(results),
		FailureBreakdown: map[string]int{},
		CasePassRate:     map[string]float64{},
	}

	var latencies []int64
	var promptSum, completionSum, tokenSum int

	caseStats := map[string]*caseAccumulator{}

	for _, r := range results {
		acc := caseStats[r.CaseID]
		if acc == nil {
			acc = &caseAccumulator{
				caseID:         r.CaseID,
				category:       r.Category,
				failureClasses: map[string]int{},
			}
			caseStats[r.CaseID] = acc
		}
		acc.total++
		if !r.EndToEndPass {
			acc.failures++
			if r.FailureClass != "" {
				acc.failureClasses[r.FailureClass]++
			}
		}

		if r.Transport.RequestAttempted || r.ContractStages.RequestAttempted {
			m.RequestAttemptedCount++
		}
		if r.Transport.HTTPResponseReceived || r.ContractStages.HTTPResponseReceived {
			m.HTTPResponseReceivedCount++
		}
		http2xx := r.Transport.HTTP2xxSuccess || r.ContractStages.HTTP2xxSuccess
		if http2xx {
			m.HTTP2xxSuccessCount++
		}

		if r.ContractStages.HTTPSuccess {
			m.HTTPSuccessCount++
		}
		if r.ContractStages.ContentJSONValid {
			m.JSONValidCount++
		}
		if r.ContractStages.DraftDTODecode == "pass" {
			m.ModelDTODecodeCount++
		}
		if http2xx && r.ContractStages.ExplanationAlignment == "pass" {
			m.ExplanationAlignmentPassCount++
		}
		if http2xx && r.ContractStages.ProvenanceAssembly == "pass" {
			m.DeterministicProvenanceAssemblyPassCount++
		}
		if r.ContractStages.GatewaySchemaValidation == "pass" {
			m.SchemaSuccessCount++
		}
		if r.ContractStages.FactValidation == "pass" {
			m.FactValidationCount++
		}
		if r.ContractStages.HTTPSuccess && r.ContractPass {
			m.ContractAmongHTTPSuccesses++
		}
		if r.EndToEndPass {
			m.EndToEndSuccessCount++
		}

		m.InventedAmountCount += r.InventedFacts
		m.InvalidCitedFactCount += r.InvalidCitedFactCount
		m.InvalidKeyFactSourceCount += r.InvalidKeyFactSource
		m.InvalidReferenceCount += r.InvalidReferenceCount
		m.InvalidActionCount += r.InvalidActionCount
		m.ForbiddenClaimCount += r.ForbiddenClaimCount
		m.MissingConclusionCount += r.MissingConclusionCount
		modelAssessed := r.ModelResponseAssessed || r.ContractStages.ModelResponseAssessed
		if modelAssessed {
			if r.RiskMatch {
				m.ExpectedRiskMatchCount++
			}
			if r.UnknownBehaviorPass {
				m.UnknownBehaviorPassCount++
			}
		}

		if modelAssessed && r.ExplanationAlignmentPass {
			// kept for backward-compatible per-run flag; aggregate count uses ContractStages above
		}
		if modelAssessed && r.PolicyStructuralPass {
			m.PolicyStructuralPassCount++
		}
		if modelAssessed && r.FinalValidatorPass {
			m.FinalValidatorPassCount++
		}

		if IsV2EvaluationMode(mode) && http2xx && r.ContractPass {
			exp := r.V2Semantic.Explanation
			if exp.RiskCoveragePass {
				m.RiskExplanationCoveragePassCount++
			}
			if exp.UnknownCoveragePass {
				m.UnknownExplanationCoveragePassCount++
			}
			if exp.CitationAlignmentPass {
				m.CitationAlignmentPassCount++
			}
			m.MissingRiskExplanationCount += exp.MissingRiskExplanationCount
			m.UnsupportedRiskExplanationCount += exp.UnsupportedRiskExplanationCount
			m.MissingRequiredUnknownExplanationCount += exp.MissingRequiredUnknownExplanationCount
			m.UnsupportedUnknownExplanationCount += exp.UnsupportedUnknownExplanationCount
			if r.PolicyStructuralPass {
				m.PolicyStructuralAlignmentPassCount++
			}

			narr := r.V2Semantic.Narrative
			m.KnownNoDebtContradictionCount += narr.KnownNoDebtContradictionCount
			m.MissingDebtOverconfidenceCount += narr.MissingDebtOverconfidenceCount
			m.SafePlusMissingMisstatementCount += narr.SafePlusMissingMisstatementCount
			m.NarrativeSeverityMismatchCount += narr.NarrativeSeverityMismatchCount
			m.UnsupportedNarrativeRiskClaimCount += narr.UnsupportedNarrativeRiskClaimCount
		}

		if r.Timeout {
			m.TimeoutCount++
		}
		if r.LatencyMs > slowRequestThreshold.Milliseconds() {
			m.SlowRequestCount++
		}

		latencies = append(latencies, r.LatencyMs)
		promptSum += r.PromptTokens
		completionSum += r.CompletionTokens
		tokenSum += r.TotalTokens

		if r.FailureClass != "" {
			m.FailureBreakdown[r.FailureClass]++
		}
	}

	if m.TotalRuns > 0 {
		m.LatencyP50Ms = Percentile(latencies, 50)
		m.LatencyP95Ms = Percentile(latencies, 95)
		m.LatencyMaxMs = MaxInt64(latencies)
		m.PromptTokensAverage = float64(promptSum) / float64(m.TotalRuns)
		m.CompletionTokensAverage = float64(completionSum) / float64(m.TotalRuns)
		m.TotalTokensAverage = float64(tokenSum) / float64(m.TotalRuns)
	}

	for id, acc := range caseStats {
		passRate := 1.0
		if acc.total > 0 {
			passRate = float64(acc.total-acc.failures) / float64(acc.total)
		}
		m.CasePassRate[id] = passRate
	}

	m.WorstCases = rankWorstCases(caseStats, defaultWorstCaseLimit)
	m.ModelMetricsAssessed = m.HTTP2xxSuccessCount > 0
	return m
}

type caseAccumulator struct {
	caseID         string
	category       string
	total          int
	failures       int
	failureClasses map[string]int
}

func rankWorstCases(stats map[string]*caseAccumulator, limit int) []CaseScore {
	scores := make([]CaseScore, 0, len(stats))
	for _, acc := range stats {
		rate := 0.0
		if acc.total > 0 {
			rate = float64(acc.failures) / float64(acc.total)
		}
		topFailure := topFailureClass(acc.failureClasses)
		scores = append(scores, CaseScore{
			CaseID:      acc.caseID,
			Category:    acc.category,
			TotalRuns:   acc.total,
			Failures:    acc.failures,
			FailureRate: rate,
			TopFailure:  topFailure,
		})
	}
	sort.Slice(scores, func(i, j int) bool {
		if scores[i].FailureRate == scores[j].FailureRate {
			return scores[i].Failures > scores[j].Failures
		}
		return scores[i].FailureRate > scores[j].FailureRate
	})
	if len(scores) > limit {
		scores = scores[:limit]
	}
	return scores
}

func topFailureClass(counts map[string]int) string {
	top := ""
	topCount := 0
	for class, count := range counts {
		if count > topCount {
			top = class
			topCount = count
		}
	}
	return top
}

// Percentile computes the p-th percentile from sorted latencies.
func Percentile(values []int64, p int) int64 {
	if len(values) == 0 {
		return 0
	}
	sorted := append([]int64(nil), values...)
	sort.Slice(sorted, func(i, j int) bool { return sorted[i] < sorted[j] })
	if p <= 0 {
		return sorted[0]
	}
	if p >= 100 {
		return sorted[len(sorted)-1]
	}
	idx := (len(sorted)*p + 99) / 100
	idx--
	if idx < 0 {
		idx = 0
	}
	if idx >= len(sorted) {
		idx = len(sorted) - 1
	}
	return sorted[idx]
}

func MaxInt64(values []int64) int64 {
	if len(values) == 0 {
		return 0
	}
	max := values[0]
	for _, v := range values[1:] {
		if v > max {
			max = v
		}
	}
	return max
}

func rate(n, total int) float64 {
	if total == 0 {
		return 0
	}
	return float64(n) / float64(total)
}
