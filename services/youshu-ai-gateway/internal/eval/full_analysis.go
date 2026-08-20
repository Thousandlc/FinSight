package eval

import (
	"fmt"
	"sort"
	"strings"
)

// Model readiness verdict constants.
const (
	VerdictProductionReady    = "Production Ready"
	VerdictConditionallyReady = "Conditionally Ready"
	VerdictNotReady           = "Not Ready"
)

// FullEvalAnalysis holds extended metrics for full dataset evaluation.
type FullEvalAnalysis struct {
	DatasetSummary DatasetSummary `json:"datasetSummary"`

	RiskMismatchDirections   map[string]int `json:"riskMismatchDirections"`
	HealthyOverWarningRuns   int            `json:"healthyOverWarningRuns"`
	HealthyOverWarningTotal  int            `json:"healthyOverWarningTotal"`
	RiskScenarioUnderWarning int            `json:"riskScenarioUnderWarningRuns"`
	RiskScenarioUnderTotal   int            `json:"riskScenarioUnderWarningTotal"`

	RiskByCategory map[string]CategoryRiskStats `json:"riskByCategory"`

	UnknownByExpectation   map[string]UnknownExpectationStats `json:"unknownByExpectation"`
	MissingDataUnknown     UnknownExpectationStats              `json:"missingDataUnknown"`
	PartialDataUnknown     UnknownExpectationStats              `json:"partialDataUnknown"`

	StructuredConclusionPassCount int     `json:"structuredConclusionPassCount"`
	StructuredConclusionTotal     int     `json:"structuredConclusionTotal"`
	StructuredConclusionPassRate  float64 `json:"structuredConclusionPassRate"`

	ActionCompliancePassCount      int      `json:"actionCompliancePassCount"`
	ActionComplianceTotal          int      `json:"actionComplianceTotal"`
	UnexpectedActionDestinations   []string `json:"unexpectedActionDestinations,omitempty"`

	RepeatStability []CaseStabilityReport `json:"repeatStability"`

	LatencyHTTPSuccessP50Ms int64 `json:"latencyHTTPSuccessP50Ms"`
	LatencyHTTPSuccessP95Ms int64 `json:"latencyHTTPSuccessP95Ms"`
	LatencyHTTPSuccessMaxMs int64 `json:"latencyHTTPSuccessMaxMs"`

	PromptTokensTotal     int `json:"promptTokensTotal"`
	CompletionTokensTotal int `json:"completionTokensTotal"`
	TotalTokensTotal      int `json:"totalTokensTotal"`

	SeverityBreakdown map[string]int `json:"severityBreakdown"`

	WorstCases []EnhancedCaseScore `json:"worstCases"`

	SystemicPatterns SystemicPatternReport `json:"systemicPatterns"`

	Acceptance       AcceptanceComparison `json:"acceptance"`
	ModelVerdict     string               `json:"modelVerdict"`
	PromptOptimizationNeeded bool         `json:"promptOptimizationNeeded"`
	PromptOptimizationPatterns []string   `json:"promptOptimizationPatterns,omitempty"`
	ModelComparisonNeeded      bool       `json:"modelComparisonNeeded"`

	ConfirmedModelFailures  int `json:"confirmedModelFailures"`
	EvaluatorFalsePositives int `json:"evaluatorFalsePositives"`

	V2Acceptance      V2AcceptanceComparison `json:"v2Acceptance,omitempty"`
	ReadinessVerdicts ReadinessVerdicts      `json:"readinessVerdicts,omitempty"`
}

// CategoryRiskStats summarizes risk match per category.
type CategoryRiskStats struct {
	Category      string  `json:"category"`
	Runs          int     `json:"runs"`
	RiskPass      int     `json:"riskPass"`
	RiskFail      int     `json:"riskFail"`
	RiskMatchRate float64 `json:"riskMatchRate"`
}

// UnknownExpectationStats summarizes unknown behavior for an expectation type.
type UnknownExpectationStats struct {
	Expectation string  `json:"expectation"`
	Runs        int     `json:"runs"`
	Pass        int     `json:"pass"`
	Fail        int     `json:"fail"`
	PassRate    float64 `json:"passRate"`
}

// CaseStabilityReport describes repeat-run consistency for a case.
type CaseStabilityReport struct {
	CaseID            string   `json:"caseId"`
	Repeats           int      `json:"repeats"`
	RiskOutcomes      []string `json:"riskOutcomes"`
	UnknownOutcomes   []string `json:"unknownOutcomes"`
	ActionOutcomes    []string `json:"actionOutcomes"`
	ContractOutcomes  []string `json:"contractOutcomes"`
	RiskStable        bool     `json:"riskStable"`
	UnknownStable     bool     `json:"unknownStable"`
	ActionStable      bool     `json:"actionStable"`
	ContractStable    bool     `json:"contractStable"`
	StabilitySummary  string   `json:"stabilitySummary"`
}

// EnhancedCaseScore ranks cases with audit context.
type EnhancedCaseScore struct {
	CaseID                string  `json:"caseId"`
	Category              string  `json:"category"`
	TotalRuns             int     `json:"totalRuns"`
	Failures              int     `json:"failures"`
	FailureRate           float64 `json:"failureRate"`
	TopFailureClass       string  `json:"topFailureClass"`
	PrimaryRiskMismatch   string  `json:"primaryRiskMismatchDirection,omitempty"`
	PrimaryAuditVerdict   string  `json:"primaryAuditVerdict,omitempty"`
	CriticalFailures      int     `json:"criticalFailures"`
	MajorFailures         int     `json:"majorFailures"`
	TimeoutCount          int     `json:"timeoutCount"`
}

// SystemicPatternReport summarizes cross-case failure patterns.
type SystemicPatternReport struct {
	HealthyOverWarning       bool     `json:"healthyOverWarning"`
	RiskUnderWarning         bool     `json:"riskUnderWarning"`
	MissingDataOverconfidence bool    `json:"missingDataOverconfidence"`
	ActionInstability        bool     `json:"actionInstability"`
	ContractDrift            bool     `json:"contractDrift"`
	Notes                    []string `json:"notes,omitempty"`
}

// AcceptanceComparison compares metrics against thresholds.
type AcceptanceComparison struct {
	ContractComplianceThreshold float64 `json:"contractComplianceThreshold"`
	ContractComplianceRate      float64 `json:"contractComplianceRate"`
	ContractCompliancePass      bool    `json:"contractCompliancePass"`

	InventedAmountPass          bool `json:"inventedAmountPass"`
	InvalidFactSourcePass       bool `json:"invalidFactSourcePass"`
	InvalidReferencePass        bool `json:"invalidReferencePass"`
	InvalidActionPass           bool `json:"invalidActionPass"`
	DataInsufficientHallucPass  bool `json:"dataInsufficientHallucinationPass"`
	DataInsufficientHallucAssessed bool `json:"dataInsufficientHallucinationAssessed"`

	RiskMatchThreshold float64 `json:"riskMatchThreshold"`
	RiskMatchRate      float64 `json:"riskMatchRate"`
	RiskMatchPass      bool    `json:"riskMatchPass"`
}

const (
	defaultWorstCaseLimit          = 10
	contractComplianceThreshold    = 0.99
	riskMatchThreshold             = 0.95
)

var riskDebtCategories = map[string]bool{
	CategoryCashFlowRisk:     true,
	CategoryDebt:             true,
	CategoryIncomeExpense:    true,
}

var repeatStabilityCaseIDs = []string{
	"A01_healthy_cashflow",
	"B01_minimum_below_safe",
	"C03_high_monthly_payment",
	"E01_partial_debt_data",
}

// AnalyzeFullEvaluation computes extended metrics from run results.
func AnalyzeFullEvaluation(results []RunResult, cases []EvaluationCase, metrics AggregateMetrics, mode string) FullEvalAnalysis {
	caseMap := map[string]EvaluationCase{}
	for _, c := range cases {
		caseMap[c.ID] = c
	}

	summary, _ := BuildDatasetSummary()

	analysis := FullEvalAnalysis{
		DatasetSummary:         summary,
		RiskMismatchDirections: map[string]int{},
		RiskByCategory:         map[string]CategoryRiskStats{},
		UnknownByExpectation:   map[string]UnknownExpectationStats{},
		SeverityBreakdown:      map[string]int{},
	}

	var httpSuccessLatencies []int64
	var unexpectedActions = map[string]struct{}{}

	caseAcc := map[string]*enhancedCaseAccumulator{}

	for _, r := range results {
		c := caseMap[r.CaseID]
		acc := caseAcc[r.CaseID]
		if acc == nil {
			acc = &enhancedCaseAccumulator{
				caseID: r.CaseID, category: r.Category,
				failureClasses: map[string]int{},
				riskMismatch:   map[string]int{},
				auditVerdicts:  map[string]int{},
			}
			caseAcc[r.CaseID] = acc
		}
		acc.total++
		if !r.EndToEndPass {
			acc.failures++
			if r.FailureClass != "" {
				acc.failureClasses[r.FailureClass]++
			}
		}
		if r.Timeout {
			acc.timeouts++
		}
		if r.FailureSeverity == SeverityCritical {
			acc.critical++
		}
		if r.FailureSeverity == SeverityMajor {
			acc.major++
		}
		if r.FailureClass != "" {
			analysis.SeverityBreakdown[r.FailureSeverity]++
		}
		if r.EvaluationVerdict == EvaluationVerdictConfirmedModelFailure {
			analysis.ConfirmedModelFailures++
		}
		if r.AuditVerdict.Verdict == VerdictEvaluatorFalsePositive {
			analysis.EvaluatorFalsePositives++
		}

		if r.ContractStages.HTTPSuccess {
			httpSuccessLatencies = append(httpSuccessLatencies, r.LatencyMs)
		}

		analysis.PromptTokensTotal += r.PromptTokens
		analysis.CompletionTokensTotal += r.CompletionTokens
		analysis.TotalTokensTotal += r.TotalTokens

		if !(r.ModelResponseAssessed || r.ContractStages.ModelResponseAssessed) {
			if r.AuditVerdict.Verdict != "" && r.AuditVerdict.Verdict != VerdictNotApplicable {
				acc.auditVerdicts[r.AuditVerdict.Verdict]++
			}
			continue
		}

		// Risk mismatch directions (only on contract-pass semantic failures or all mismatches)
		if !r.RiskMatch && r.Semantic.RiskMismatchDirection != "" {
			analysis.RiskMismatchDirections[r.Semantic.RiskMismatchDirection]++
			acc.riskMismatch[r.Semantic.RiskMismatchDirection]++
		}

		// Category risk stats
		crs := analysis.RiskByCategory[r.Category]
		crs.Category = r.Category
		crs.Runs++
		if r.RiskMatch {
			crs.RiskPass++
		} else {
			crs.RiskFail++
		}
		analysis.RiskByCategory[r.Category] = crs

		// Healthy over-warning
		if c.ExpectedRiskLevel == RiskLevelNone && (r.Category == CategoryHealthyFinance || c.ID == "F06_no_warning_expected") {
			analysis.HealthyOverWarningTotal++
			if !r.RiskMatch && (r.Semantic.RiskMismatchDirection == RiskMismatchUnexpectedWarning || r.Semantic.RiskMismatchDirection == RiskMismatchOverclassified) {
				analysis.HealthyOverWarningRuns++
			}
		}

		// Risk scenario under-warning
		if riskDebtCategories[r.Category] && (c.ExpectedRiskLevel == RiskLevelWarning || c.ExpectedRiskLevel == RiskLevelRisk) {
			analysis.RiskScenarioUnderTotal++
			if !r.RiskMatch && (r.Semantic.RiskMismatchDirection == RiskMismatchMissingWarning || r.Semantic.RiskMismatchDirection == RiskMismatchUnderclassified) {
				analysis.RiskScenarioUnderWarning++
			}
		}

		// Unknown by expectation
		exp := string(ResolveUnknownExpectation(c))
		uStat := analysis.UnknownByExpectation[exp]
		uStat.Expectation = exp
		uStat.Runs++
		if r.UnknownBehaviorPass {
			uStat.Pass++
		} else {
			uStat.Fail++
		}
		analysis.UnknownByExpectation[exp] = uStat

		debt := AnalyzeDebtFacts(c)
		if debt.DebtFactsMissing {
			analysis.MissingDataUnknown.Runs++
			if r.UnknownBehaviorPass {
				analysis.MissingDataUnknown.Pass++
			} else {
				analysis.MissingDataUnknown.Fail++
			}
		} else if debt.DebtFactsPartial {
			analysis.PartialDataUnknown.Runs++
			if r.UnknownBehaviorPass {
				analysis.PartialDataUnknown.Pass++
			} else {
				analysis.PartialDataUnknown.Fail++
			}
		}

		// Structured conclusion (cases that require it)
		if !c.StructuredConclusion.IsZero() {
			analysis.StructuredConclusionTotal++
			if r.Semantic.StructuredConclusionPass {
				analysis.StructuredConclusionPassCount++
			}
		}

		// Action compliance
		if len(c.AllowedActions) > 0 {
			analysis.ActionComplianceTotal++
			if r.Semantic.ActionCompliancePass {
				analysis.ActionCompliancePassCount++
			} else {
				for _, dest := range r.StructuredSnapshot.ActionDestinations {
					if !actionAllowed(c.AllowedActions, dest) {
						unexpectedActions[dest] = struct{}{}
					}
				}
				acc.failureClasses[FailureSemanticAction]++
			}
		}

		if r.AuditVerdict.Verdict != "" && r.AuditVerdict.Verdict != VerdictNotApplicable {
			acc.auditVerdicts[r.AuditVerdict.Verdict]++
		}
	}

	for exp, stat := range analysis.UnknownByExpectation {
		stat.PassRate = rate(stat.Pass, stat.Runs)
		analysis.UnknownByExpectation[exp] = stat
	}
	analysis.MissingDataUnknown.Expectation = "genuinelyMissingData"
	analysis.MissingDataUnknown.PassRate = rate(analysis.MissingDataUnknown.Pass, analysis.MissingDataUnknown.Runs)
	analysis.PartialDataUnknown.Expectation = "partialData"
	analysis.PartialDataUnknown.PassRate = rate(analysis.PartialDataUnknown.Pass, analysis.PartialDataUnknown.Runs)

	for cat, crs := range analysis.RiskByCategory {
		crs.RiskMatchRate = rate(crs.RiskPass, crs.Runs)
		analysis.RiskByCategory[cat] = crs
	}

	if analysis.StructuredConclusionTotal > 0 {
		analysis.StructuredConclusionPassRate = rate(analysis.StructuredConclusionPassCount, analysis.StructuredConclusionTotal)
	}

	if len(httpSuccessLatencies) > 0 {
		analysis.LatencyHTTPSuccessP50Ms = Percentile(httpSuccessLatencies, 50)
		analysis.LatencyHTTPSuccessP95Ms = Percentile(httpSuccessLatencies, 95)
		analysis.LatencyHTTPSuccessMaxMs = MaxInt64(httpSuccessLatencies)
	}

	for dest := range unexpectedActions {
		analysis.UnexpectedActionDestinations = append(analysis.UnexpectedActionDestinations, dest)
	}
	sort.Strings(analysis.UnexpectedActionDestinations)

	analysis.RepeatStability = buildRepeatStability(results, caseMap)
	analysis.WorstCases = rankEnhancedWorstCases(caseAcc, defaultWorstCaseLimit)
	analysis.SystemicPatterns = detectSystemicPatterns(analysis, metrics, results)
	analysis.Acceptance = buildAcceptanceComparison(metrics, results, caseMap)
	analysis.V2Acceptance = buildV2Acceptance(metrics, analysis)
	analysis.ReadinessVerdicts = deriveV2ReadinessVerdicts(analysis.V2Acceptance, metrics)
	if IsV2EvaluationMode(mode) {
		analysis.ModelVerdict = analysis.ReadinessVerdicts.ProductionReadiness
		analysis.ModelComparisonNeeded = false
	} else {
		analysis.ModelVerdict, analysis.PromptOptimizationNeeded, analysis.PromptOptimizationPatterns, analysis.ModelComparisonNeeded = deriveLegacyModelVerdict(analysis, metrics)
	}

	return analysis
}

type enhancedCaseAccumulator struct {
	caseID         string
	category       string
	total          int
	failures       int
	critical       int
	major          int
	timeouts       int
	failureClasses map[string]int
	riskMismatch   map[string]int
	auditVerdicts  map[string]int
}

func rankEnhancedWorstCases(stats map[string]*enhancedCaseAccumulator, limit int) []EnhancedCaseScore {
	scores := make([]EnhancedCaseScore, 0, len(stats))
	for _, acc := range stats {
		rateVal := 0.0
		if acc.total > 0 {
			rateVal = float64(acc.failures) / float64(acc.total)
		}
		scores = append(scores, EnhancedCaseScore{
			CaseID:              acc.caseID,
			Category:            acc.category,
			TotalRuns:           acc.total,
			Failures:            acc.failures,
			FailureRate:         rateVal,
			TopFailureClass:     topFailureClass(acc.failureClasses),
			PrimaryRiskMismatch: topFailureClass(acc.riskMismatch),
			PrimaryAuditVerdict: topFailureClass(acc.auditVerdicts),
			CriticalFailures:    acc.critical,
			MajorFailures:       acc.major,
			TimeoutCount:        acc.timeouts,
		})
	}
	sort.Slice(scores, func(i, j int) bool {
		a, b := scores[i], scores[j]
		if a.CriticalFailures != b.CriticalFailures {
			return a.CriticalFailures > b.CriticalFailures
		}
		if a.MajorFailures != b.MajorFailures {
			return a.MajorFailures > b.MajorFailures
		}
		if a.Failures != b.Failures {
			return a.Failures > b.Failures
		}
		if a.FailureRate != b.FailureRate {
			return a.FailureRate > b.FailureRate
		}
		return a.TimeoutCount > b.TimeoutCount
	})
	if len(scores) > limit {
		scores = scores[:limit]
	}
	return scores
}

func buildRepeatStability(results []RunResult, caseMap map[string]EvaluationCase) []CaseStabilityReport {
	byCase := map[string][]RunResult{}
	for _, r := range results {
		byCase[r.CaseID] = append(byCase[r.CaseID], r)
	}

	var reports []CaseStabilityReport
	for _, caseID := range repeatStabilityCaseIDs {
		runs := byCase[caseID]
		if len(runs) < 2 {
			continue
		}
		sort.Slice(runs, func(i, j int) bool { return runs[i].RunIndex < runs[j].RunIndex })

		report := CaseStabilityReport{CaseID: caseID, Repeats: len(runs)}
		for _, r := range runs {
			report.RiskOutcomes = append(report.RiskOutcomes, string(r.StructuredSnapshot.ActualDerivedRisk))
			if r.UnknownBehaviorPass {
				report.UnknownOutcomes = append(report.UnknownOutcomes, "pass")
			} else {
				report.UnknownOutcomes = append(report.UnknownOutcomes, "fail")
			}
			report.ActionOutcomes = append(report.ActionOutcomes, strings.Join(sortedCopy(r.StructuredSnapshot.ActionDestinations), ","))
			if r.ContractPass {
				report.ContractOutcomes = append(report.ContractOutcomes, "contractPass")
			} else {
				report.ContractOutcomes = append(report.ContractOutcomes, "contractFail")
			}
		}
		report.RiskStable = allSame(report.RiskOutcomes)
		report.UnknownStable = allSame(report.UnknownOutcomes)
		report.ActionStable = allSame(report.ActionOutcomes)
		report.ContractStable = allSame(report.ContractOutcomes)
		report.StabilitySummary = formatStabilitySummary(report)
		reports = append(reports, report)
	}
	return reports
}

func formatStabilitySummary(r CaseStabilityReport) string {
	parts := []string{}
	if r.RiskStable {
		parts = append(parts, fmt.Sprintf("risk=%s stable", strings.Join(r.RiskOutcomes, "/")))
	} else {
		parts = append(parts, fmt.Sprintf("risk=%s mixed", strings.Join(r.RiskOutcomes, "/")))
	}
	if r.UnknownStable {
		parts = append(parts, "unknown=stable")
	} else {
		parts = append(parts, "unknown=mixed")
	}
	if r.ActionStable {
		parts = append(parts, "action=stable")
	} else {
		parts = append(parts, "action=mixed")
	}
	if r.ContractStable {
		parts = append(parts, "contract=stable")
	} else {
		parts = append(parts, "contract=mixed")
	}
	return strings.Join(parts, "; ")
}

func detectSystemicPatterns(analysis FullEvalAnalysis, metrics AggregateMetrics, results []RunResult) SystemicPatternReport {
	if !metrics.ModelMetricsAssessed {
		return SystemicPatternReport{}
	}
	p := SystemicPatternReport{}

	if analysis.HealthyOverWarningTotal > 0 {
		overRate := rate(analysis.HealthyOverWarningRuns, analysis.HealthyOverWarningTotal)
		if overRate >= 0.5 {
			p.HealthyOverWarning = true
			p.Notes = append(p.Notes, fmt.Sprintf("healthy/no-warning cases over-warning rate=%.0f%%", overRate*100))
		}
	}

	if analysis.RiskScenarioUnderTotal > 0 {
		underRate := rate(analysis.RiskScenarioUnderWarning, analysis.RiskScenarioUnderTotal)
		if underRate >= 0.3 {
			p.RiskUnderWarning = true
			p.Notes = append(p.Notes, fmt.Sprintf("risk/debt/cashflow under-warning rate=%.0f%%", underRate*100))
		}
	}

	if analysis.MissingDataUnknown.Runs > 0 && analysis.MissingDataUnknown.Fail > 0 {
		p.MissingDataOverconfidence = true
		p.Notes = append(p.Notes, fmt.Sprintf("genuinely missing data unknown fail=%d/%d", analysis.MissingDataUnknown.Fail, analysis.MissingDataUnknown.Runs))
	}

	for _, stab := range analysis.RepeatStability {
		if !stab.ActionStable || !stab.RiskStable {
			p.ActionInstability = true
			p.Notes = append(p.Notes, fmt.Sprintf("%s stability: %s", stab.CaseID, stab.StabilitySummary))
			break
		}
	}

	contractRate := rate(metrics.ContractAmongHTTPSuccesses, metrics.HTTPSuccessCount)
	if contractRate < contractComplianceThreshold {
		p.ContractDrift = true
		p.Notes = append(p.Notes, fmt.Sprintf("contract compliance dropped to %.1f%%", contractRate*100))
	}

	_ = results
	return p
}

func buildAcceptanceComparison(metrics AggregateMetrics, results []RunResult, caseMap map[string]EvaluationCase) AcceptanceComparison {
	contractRate := rate(metrics.ContractAmongHTTPSuccesses, metrics.HTTPSuccessCount)
	riskRate := rate(metrics.ExpectedRiskMatchCount, metrics.TotalRuns)

	dataHalluc := 0
	dataHallucAssessed := false
	if metrics.ModelMetricsAssessed {
		dataHallucAssessed = true
		for _, r := range results {
			if !r.ModelResponseAssessed {
				continue
			}
			c := caseMap[r.CaseID]
			if ResolveUnknownExpectation(c) != UnknownRequired {
				continue
			}
			debt := AnalyzeDebtFacts(c)
			if !debt.DebtFactsMissing {
				continue
			}
			if !r.UnknownBehaviorPass && (r.InventedFacts > 0 || !r.Semantic.FactKeyCompliancePass) {
				dataHalluc++
			}
		}
	}

	return AcceptanceComparison{
		ContractComplianceThreshold: contractComplianceThreshold,
		ContractComplianceRate:      contractRate,
		ContractCompliancePass:      metrics.ModelMetricsAssessed && contractRate >= contractComplianceThreshold,
		InventedAmountPass:          metrics.InventedAmountCount == 0,
		InvalidFactSourcePass:       metrics.InvalidKeyFactSourceCount == 0,
		InvalidReferencePass:        metrics.InvalidReferenceCount == 0,
		InvalidActionPass:           metrics.InvalidActionCount == 0,
		DataInsufficientHallucPass:  !dataHallucAssessed || dataHalluc == 0,
		DataInsufficientHallucAssessed: dataHallucAssessed,
		RiskMatchThreshold:          riskMatchThreshold,
		RiskMatchRate:               riskRate,
		RiskMatchPass:               metrics.ModelMetricsAssessed && riskRate >= riskMatchThreshold,
	}
}

func deriveLegacyModelVerdict(analysis FullEvalAnalysis, metrics AggregateMetrics) (verdict string, promptOpt bool, patterns []string, modelComp bool) {
	a := analysis.Acceptance
	factSafe := a.InventedAmountPass && a.InvalidFactSourcePass && a.InvalidReferencePass && a.InvalidActionPass && a.DataInsufficientHallucPass

	if !a.ContractCompliancePass || !factSafe {
		return VerdictNotReady, false, nil, true
	}

	if !a.RiskMatchPass || analysis.ConfirmedModelFailures > 0 {
		promptOpt = true
		p := analysis.SystemicPatterns
		if p.HealthyOverWarning {
			patterns = append(patterns, "healthy over-warning")
		}
		if p.RiskUnderWarning {
			patterns = append(patterns, "debt/risk under-warning")
		}
		if p.MissingDataOverconfidence {
			patterns = append(patterns, "missing-data overconfidence")
		}
		for _, stab := range analysis.RepeatStability {
			if !stab.RiskStable {
				patterns = append(patterns, stab.CaseID+" risk instability")
			}
		}
		return VerdictConditionallyReady, promptOpt, patterns, true
	}

	return VerdictProductionReady, false, nil, false
}

func actionAllowed(allowed []string, dest string) bool {
	for _, a := range allowed {
		if a == dest {
			return true
		}
	}
	return false
}

func allSame(items []string) bool {
	if len(items) <= 1 {
		return true
	}
	for i := 1; i < len(items); i++ {
		if items[i] != items[0] {
			return false
		}
	}
	return true
}

func formatDataInsufficientHallucination(ac AcceptanceComparison) string {
	if !ac.DataInsufficientHallucAssessed {
		return "N/A"
	}
	return "0"
}

func sortedCopy(items []string) []string {
	out := append([]string(nil), items...)
	sort.Strings(out)
	return out
}

// FormatFullAnalysisSummary produces the extended analysis report sections.
func FormatFullAnalysisSummary(a FullEvalAnalysis, mode string) string {
	var b strings.Builder

	b.WriteString("\n--- Contract vs Semantic ---\n")
	b.WriteString("Contract Compliance = JSON/DTO/Schema/Fact pipeline among HTTP successes.\n")
	b.WriteString("Semantic Quality = risk/unknown/action/conclusion expectations after contract pass.\n")
	b.WriteString("overallEndToEndSuccessRate includes semantic failures; not equivalent to contract compliance.\n\n")

	b.WriteString("--- Risk Mismatch Directions ---\n")
	for _, dir := range sortedKeysIntMap(a.RiskMismatchDirections) {
		b.WriteString(fmt.Sprintf("%s=%d\n", dir, a.RiskMismatchDirections[dir]))
	}
	if a.HealthyOverWarningTotal > 0 {
		b.WriteString(fmt.Sprintf("healthyOverWarningRate=%d/%d (%.1f%%)\n",
			a.HealthyOverWarningRuns, a.HealthyOverWarningTotal,
			rate(a.HealthyOverWarningRuns, a.HealthyOverWarningTotal)*100))
	}
	if a.RiskScenarioUnderTotal > 0 {
		b.WriteString(fmt.Sprintf("riskScenarioUnderWarningRate=%d/%d (%.1f%%)\n",
			a.RiskScenarioUnderWarning, a.RiskScenarioUnderTotal,
			rate(a.RiskScenarioUnderWarning, a.RiskScenarioUnderTotal)*100))
	}

	b.WriteString("\n--- Risk By Category ---\n")
	for _, cat := range sortedCategoryRisk(a.RiskByCategory) {
		b.WriteString(fmt.Sprintf("%s: runs=%d riskPass=%d riskFail=%d rate=%.1f%%\n",
			cat.Category, cat.Runs, cat.RiskPass, cat.RiskFail, cat.RiskMatchRate*100))
	}

	b.WriteString("\n--- Unknown Behavior ---\n")
	for _, stat := range sortedUnknownStats(a.UnknownByExpectation) {
		b.WriteString(fmt.Sprintf("%s: pass=%d fail=%d rate=%.1f%%\n",
			stat.Expectation, stat.Pass, stat.Fail, stat.PassRate*100))
	}
	b.WriteString(fmt.Sprintf("genuinelyMissingData: pass=%d fail=%d rate=%.1f%%\n",
		a.MissingDataUnknown.Pass, a.MissingDataUnknown.Fail, a.MissingDataUnknown.PassRate*100))
	b.WriteString(fmt.Sprintf("partialData: pass=%d fail=%d rate=%.1f%%\n",
		a.PartialDataUnknown.Pass, a.PartialDataUnknown.Fail, a.PartialDataUnknown.PassRate*100))

	b.WriteString("\n--- Structured Conclusion ---\n")
	b.WriteString(fmt.Sprintf("structuredConclusionPassRate=%d/%d (%.1f%%)\n",
		a.StructuredConclusionPassCount, a.StructuredConclusionTotal, a.StructuredConclusionPassRate*100))
	b.WriteString("Narrative keywords are diagnostic only; not hard fail.\n")

	b.WriteString("\n--- Action Compliance ---\n")
	if a.ActionComplianceTotal > 0 {
		b.WriteString(fmt.Sprintf("actionCompliancePassRate=%d/%d (%.1f%%)\n",
			a.ActionCompliancePassCount, a.ActionComplianceTotal,
			rate(a.ActionCompliancePassCount, a.ActionComplianceTotal)*100))
	}
	if len(a.UnexpectedActionDestinations) > 0 {
		b.WriteString(fmt.Sprintf("unexpectedActionDestinations=%s\n", strings.Join(a.UnexpectedActionDestinations, ",")))
	}

	b.WriteString("\n--- Repeat Stability ---\n")
	for _, s := range a.RepeatStability {
		b.WriteString(fmt.Sprintf("%s: %s\n", s.CaseID, s.StabilitySummary))
	}

	b.WriteString("\n--- Latency (HTTP Success Only) ---\n")
	b.WriteString(fmt.Sprintf("latencyHTTPSuccessP50Ms=%d latencyHTTPSuccessP95Ms=%d latencyHTTPSuccessMaxMs=%d\n",
		a.LatencyHTTPSuccessP50Ms, a.LatencyHTTPSuccessP95Ms, a.LatencyHTTPSuccessMaxMs))

	b.WriteString("\n--- Token Totals ---\n")
	b.WriteString(fmt.Sprintf("promptTokensTotal=%d completionTokensTotal=%d totalTokensTotal=%d\n",
		a.PromptTokensTotal, a.CompletionTokensTotal, a.TotalTokensTotal))

	b.WriteString("\n--- Severity Breakdown ---\n")
	for _, sev := range []string{SeverityCritical, SeverityMajor, SeverityMinor, SeverityDiagnostic} {
		if count := a.SeverityBreakdown[sev]; count > 0 {
			b.WriteString(fmt.Sprintf("%s=%d\n", sev, count))
		}
	}

	b.WriteString("\n--- Worst 10 Cases ---\n")
	for i, wc := range a.WorstCases {
		b.WriteString(fmt.Sprintf("%d. %s (%s) failures=%d/%d rate=%.0f%% topFailure=%s riskMismatch=%s verdict=%s critical=%d major=%d timeout=%d\n",
			i+1, wc.CaseID, wc.Category, wc.Failures, wc.TotalRuns, wc.FailureRate*100,
			wc.TopFailureClass, wc.PrimaryRiskMismatch, wc.PrimaryAuditVerdict,
			wc.CriticalFailures, wc.MajorFailures, wc.TimeoutCount))
	}

	b.WriteString("\n--- Systemic Patterns ---\n")
	p := a.SystemicPatterns
	b.WriteString(fmt.Sprintf("A.HealthyOverWarning=%v B.RiskUnderWarning=%v C.MissingDataOverconfidence=%v D.ActionInstability=%v E.ContractDrift=%v\n",
		p.HealthyOverWarning, p.RiskUnderWarning, p.MissingDataOverconfidence, p.ActionInstability, p.ContractDrift))
	for _, note := range p.Notes {
		b.WriteString("- " + note + "\n")
	}

	b.WriteString("\n--- Acceptance Threshold Comparison ---\n")
	ac := a.Acceptance
	b.WriteString(fmt.Sprintf("contractCompliance=%.1f%% (threshold %.0f%%) pass=%v\n",
		ac.ContractComplianceRate*100, ac.ContractComplianceThreshold*100, ac.ContractCompliancePass))
	b.WriteString(fmt.Sprintf("inventedAmount=0 pass=%v invalidFactSource=0 pass=%v invalidReference=0 pass=%v invalidAction=0 pass=%v\n",
		ac.InventedAmountPass, ac.InvalidFactSourcePass, ac.InvalidReferencePass, ac.InvalidActionPass))
	b.WriteString(fmt.Sprintf("dataInsufficientHallucination=%s pass=%v\n",
		formatDataInsufficientHallucination(ac), ac.DataInsufficientHallucPass))
	b.WriteString(fmt.Sprintf("expectedRiskMatch=%.1f%% (threshold %.0f%%) pass=%v [%s]\n",
		ac.RiskMatchRate*100, ac.RiskMatchThreshold*100, ac.RiskMatchPass, LegacyMetricLabel))

	if IsV2EvaluationMode(mode) {
		b.WriteString("\n--- v2 Readiness Verdicts ---\n")
		rv := a.ReadinessVerdicts
		b.WriteString(fmt.Sprintf("Integration=%s ExplanationContract=%s NarrativeSemantic=%s Production=%s\n",
			rv.IntegrationReadiness, rv.ExplanationContractReadiness, rv.NarrativeSemanticReadiness, rv.ProductionReadiness))
		b.WriteString("\n--- Legacy Baseline (not directly comparable) ---\n")
		b.WriteString(fmt.Sprintf("old expectedRiskMatch=%.1f%% old contractAmongHTTP=%.0f%%\n",
			LegacyBaselineExpectedRiskMatchRate*100, LegacyBaselineContractAmongHTTPRate*100))
		b.WriteString("Risk ownership moved from LLM to deterministic Policy.\n")
	} else {
		b.WriteString("\n--- Model Verdict (legacy) ---\n")
		b.WriteString(fmt.Sprintf("qwen3.7-plus verdict: %s\n", a.ModelVerdict))
	}
	b.WriteString(fmt.Sprintf("confirmedModelFailures=%d evaluatorFalsePositives=%d\n",
		a.ConfirmedModelFailures, a.EvaluatorFalsePositives))
	b.WriteString(fmt.Sprintf("PromptOptimizationNeeded=%v\n", a.PromptOptimizationNeeded))
	if len(a.PromptOptimizationPatterns) > 0 {
		for _, pat := range a.PromptOptimizationPatterns {
			b.WriteString("- " + pat + "\n")
		}
	}
	b.WriteString(fmt.Sprintf("ModelComparisonNeeded=%v\n", a.ModelComparisonNeeded))

	return b.String()
}

func sortedKeysIntMap(m map[string]int) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}

func sortedCategoryRisk(m map[string]CategoryRiskStats) []CategoryRiskStats {
	out := make([]CategoryRiskStats, 0, len(m))
	for _, v := range m {
		out = append(out, v)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Category < out[j].Category })
	return out
}

func sortedUnknownStats(m map[string]UnknownExpectationStats) []UnknownExpectationStats {
	out := make([]UnknownExpectationStats, 0, len(m))
	for _, v := range m {
		out = append(out, v)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Expectation < out[j].Expectation })
	return out
}
