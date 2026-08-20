package eval

import (
	"fmt"
	"strings"
)

const (
	ReadinessPass = "PASS"
	ReadinessFail = "FAIL"
)

// CaseExpectationAudit documents dataset expectation correction for a case.
type CaseExpectationAudit struct {
	CaseID                 string                     `json:"caseId"`
	DataSemantics          InsufficientDataAnalysis   `json:"dataSemantics,omitempty"`
	DebtSemantics          DebtFactsAnalysis          `json:"debtSemantics,omitempty"`
	PreviousExpectation    UnknownExpectation         `json:"previousExpectation"`
	CorrectedExpectation   UnknownExpectation         `json:"correctedExpectation"`
	ExpectationChanged     bool                       `json:"expectationChanged"`
	OfflineRescorePassed   bool                       `json:"offlineRescorePassed"`
	OfflineRescoreDetail   string                     `json:"offlineRescoreDetail,omitempty"`
	RawVerdict             string                     `json:"rawVerdict"`
	AdjudicatedVerdict     string                     `json:"adjudicatedVerdict"`
	WasEvaluatorFalsePositive bool                    `json:"wasEvaluatorFalsePositive"`
}

// SafetyMetrics separates contract fact safety from scenario semantic safety.
type SafetyMetrics struct {
	InventedAmountCount            int  `json:"inventedAmountCount"`
	InvalidCitedFactCount          int  `json:"invalidCitedFactCount"`
	InvalidKeyFactSourceCount      int  `json:"invalidKeyFactSourceCount"`
	InvalidReferenceCount          int  `json:"invalidReferenceCount"`
	InvalidActionCount             int  `json:"invalidActionCount"`
	ContractFactSafetyPass         bool `json:"contractFactSafetyPass"`

	ForbiddenClaimCount            int  `json:"forbiddenClaimCount"`
	KnownZeroContradictionCount    int  `json:"knownZeroContradictionCount"`
	MissingDataOverconfidenceCount int  `json:"missingDataOverconfidenceCount"`
	DataInsufficientFabricationCount int `json:"dataInsufficientFabricationCount"`
	ScenarioSemanticSafetyPass     bool `json:"scenarioSemanticSafetyPass"`
}

// AdjudicatedMetrics summarizes corrected evaluation metrics.
type AdjudicatedMetrics struct {
	TotalRuns                 int     `json:"totalRuns"`
	EndToEndSuccessCount      int     `json:"endToEndSuccessCount"`
	SemanticSuccessCount      int     `json:"semanticSuccessCount"`
	SemanticSuccessRate       float64 `json:"semanticSuccessRate"`
	ExpectedRiskMatchCount    int     `json:"expectedRiskMatchCount"`
	ExpectedRiskMatchRate     float64 `json:"expectedRiskMatchRate"`
	UnknownBehaviorPassCount  int     `json:"unknownBehaviorPassCount"`
	UnknownBehaviorPassRate   float64 `json:"unknownBehaviorPassRate"`
	ConfirmedModelFailures    int     `json:"confirmedModelFailures"`
	EvaluatorFalsePositives   int     `json:"evaluatorFalsePositives"`
	AmbiguousManualReview     int     `json:"ambiguousManualReview"`
	CriticalSemanticFailures  int     `json:"criticalSemanticFailures"`

	UnknownByExpectation map[string]UnknownExpectationStats `json:"unknownByExpectation"`
	MissingDataUnknown   UnknownExpectationStats            `json:"missingDataUnknown"`
	PartialDataUnknown   UnknownExpectationStats            `json:"partialDataUnknown"`

	ActionValidityPassCount   int  `json:"actionValidityPassCount"`
	ActionValidityTotal       int  `json:"actionValidityTotal"`
	ActionStabilityMixedCases int  `json:"actionStabilityMixedCases"`
}

// AdjudicationReport is the offline full-eval adjudication output.
type AdjudicationReport struct {
	SourceReportPath string `json:"sourceReportPath,omitempty"`

	RawMetrics        AdjudicatedMetrics `json:"rawMetrics"`
	AdjudicatedMetrics AdjudicatedMetrics `json:"adjudicatedMetrics"`

	E03Audit CaseExpectationAudit  `json:"e03Audit"`
	E04Audit CaseExpectationAudit  `json:"e04Audit"`
	C01Audit ForbiddenClaimAudit   `json:"c01Audit,omitempty"`

	ContractFactSafety   SafetyMetrics `json:"contractFactSafety"`
	ScenarioSemanticSafety SafetyMetrics `json:"scenarioSemanticSafety"`

	RiskMismatchDirections map[string]int `json:"riskMismatchDirections"`
	RepeatStability        []CaseStabilityReport `json:"repeatStability"`

	IntegrationReadiness         string `json:"integrationReadiness"`
	ProductionSemanticReadiness  string `json:"productionSemanticReadiness"`
	PromptOptimizationNeeded     bool   `json:"promptOptimizationNeeded"`
	ModelComparisonRecommended   bool   `json:"modelComparisonRecommended"`
	DeterministicRiskPolicyRecommended bool `json:"deterministicRiskPolicyRecommended"`
	P0Verdict                    string `json:"p0Verdict"`
	SummaryText                  string `json:"summaryText"`
}

// AdjudicateFullEvaluation performs offline adjudication on a saved evaluation report.
func AdjudicateFullEvaluation(report EvaluationReport, cases []EvaluationCase) AdjudicationReport {
	caseMap := map[string]EvaluationCase{}
	for _, c := range cases {
		caseMap[c.ID] = c
	}

	raw := computeAdjudicatedMetrics(report.Results, caseMap, false)
	adjResults := applyExpectationCorrections(report.Results, caseMap)
	adj := computeAdjudicatedMetrics(adjResults, caseMap, true)

	e03 := auditCaseExpectation(caseMap["E03_no_budget"], findRun(report.Results, "E03_no_budget", 1))
	e04 := auditCaseExpectation(caseMap["E04_partial_facts_missing"], findRun(report.Results, "E04_partial_facts_missing", 1))

	var c01Audit ForbiddenClaimAudit
	if r := findRun(report.Results, "C01_no_debt", 1); r != nil {
		c01Audit = AuditC01ForbiddenClaim(caseMap["C01_no_debt"], *r)
	}

	contractSafety, scenarioSafety := computeSafetyMetrics(report.Results, caseMap, adjResults)

	integration := deriveIntegrationReadiness(report.Metrics, contractSafety)
	production := deriveProductionSemanticReadiness(adj, scenarioSafety, c01Audit, report.Analysis)

	out := AdjudicationReport{
		RawMetrics:         raw,
		AdjudicatedMetrics: adj,
		E03Audit:           e03,
		E04Audit:           e04,
		C01Audit:           c01Audit,
		ContractFactSafety: contractSafety,
		ScenarioSemanticSafety: scenarioSafety,
		RiskMismatchDirections: copyIntMap(report.Analysis.RiskMismatchDirections),
		RepeatStability:        report.Analysis.RepeatStability,
		IntegrationReadiness:        integration,
		ProductionSemanticReadiness: production,
		PromptOptimizationNeeded:    report.Analysis.PromptOptimizationNeeded,
		ModelComparisonRecommended:  report.Analysis.ModelComparisonNeeded,
		DeterministicRiskPolicyRecommended: production == ReadinessFail,
	}
	out.P0Verdict = fmt.Sprintf("Integration=%s ProductionSemantic=%s", integration, production)
	out.SummaryText = FormatAdjudicationSummary(out, report)
	return out
}

func auditCaseExpectation(c EvaluationCase, r *RunResult) CaseExpectationAudit {
	audit := CaseExpectationAudit{
		CaseID:              c.ID,
		DataSemantics:       AnalyzeInsufficientDataCase(c),
		PreviousExpectation: UnknownRequired, // historical bug for E03/E04
		CorrectedExpectation: AnalyzeInsufficientDataCase(c).RecommendedExpectation,
		ExpectationChanged:  ResolveUnknownExpectation(c) != UnknownRequired || c.ID == "E03_no_budget" || c.ID == "E04_partial_facts_missing",
	}
	audit.ExpectationChanged = audit.PreviousExpectation != audit.CorrectedExpectation

	if r == nil {
		return audit
	}
	audit.RawVerdict = r.EvaluationVerdict
	if r.EvaluationVerdict == EvaluationVerdictEvaluatorFalsePositive {
		audit.WasEvaluatorFalsePositive = true
	}

	corrected := c
	corrected.UnknownExpectation = audit.CorrectedExpectation
	rescore := RescoreRunOffline(corrected, r.StructuredSnapshot)
	audit.OfflineRescorePassed = rescore.Passed
	if !rescore.Passed {
		audit.OfflineRescoreDetail = strings.Join(rescore.Details, "; ")
	}
	audit.AdjudicatedVerdict = ResolveEvaluationVerdictFromSemantic(r.ContractPass, rescore, *r)
	return audit
}

func ResolveEvaluationVerdictFromSemantic(contractPass bool, semantic SemanticResult, r RunResult) string {
	if !contractPass {
		if r.Timeout {
			return EvaluationVerdictAmbiguous
		}
		return EvaluationVerdictAmbiguous
	}
	if semantic.Passed {
		return EvaluationVerdictPass
	}
	return EvaluationVerdictConfirmedModelFailure
}

func applyExpectationCorrections(results []RunResult, caseMap map[string]EvaluationCase) []RunResult {
	out := make([]RunResult, len(results))
	copy(out, results)
	for i, r := range out {
		c, ok := caseMap[r.CaseID]
		if !ok || !r.ContractPass {
			continue
		}
		corrected := c
		if r.CaseID == "E03_no_budget" || r.CaseID == "E04_partial_facts_missing" {
			corrected.UnknownExpectation = UnknownNotRequired
		}
		semantic := RescoreRunOffline(corrected, r.StructuredSnapshot)
		out[i].Semantic = semantic
		out[i].SemanticPass = semantic.Passed
		out[i].UnknownBehaviorPass = semantic.UnknownBehaviorPass
		out[i].RiskMatch = semantic.RiskMatch
		out[i].EndToEndPass = r.ContractPass && semantic.Passed
		out[i].ForbiddenClaimCount = len(semantic.ForbiddenClaimHits)
		out[i].MissingConclusionCount = len(semantic.MissingStructuredConclusions)
		if out[i].EndToEndPass {
			out[i].FailureClass = ""
			out[i].FailureSeverity = ""
			out[i].EvaluationVerdict = EvaluationVerdictPass
			out[i].AuditVerdict = SemanticAuditVerdict{Verdict: VerdictNotApplicable}
		} else {
			if len(semantic.FailureClasses) > 0 {
				out[i].FailureClass = semantic.FailureClasses[0]
			} else {
				out[i].FailureClass = FailureSemanticRisk
			}
			out[i].FailureSeverity = ClassifyFailureSeverity(out[i].FailureClass, corrected, r.StructuredSnapshot)
			out[i].EvaluationVerdict = EvaluationVerdictConfirmedModelFailure
			out[i].AuditVerdict = AuditSemanticFailure(corrected, out[i], r.StructuredSnapshot)
		}
	}
	return out
}

func computeAdjudicatedMetrics(results []RunResult, caseMap map[string]EvaluationCase, adjudicated bool) AdjudicatedMetrics {
	m := AdjudicatedMetrics{
		TotalRuns:            len(results),
		UnknownByExpectation: map[string]UnknownExpectationStats{},
	}
	for _, r := range results {
		c := caseMap[r.CaseID]
		if r.EndToEndPass {
			m.EndToEndSuccessCount++
		}
		if r.ContractPass && r.SemanticPass {
			m.SemanticSuccessCount++
		}
		if r.RiskMatch {
			m.ExpectedRiskMatchCount++
		}
		if r.UnknownBehaviorPass {
			m.UnknownBehaviorPassCount++
		}

		switch r.EvaluationVerdict {
		case EvaluationVerdictConfirmedModelFailure:
			m.ConfirmedModelFailures++
		case EvaluationVerdictEvaluatorFalsePositive:
			if !adjudicated {
				m.EvaluatorFalsePositives++
			}
		case EvaluationVerdictAmbiguous, EvaluationVerdictManualReview:
			m.AmbiguousManualReview++
		}
		if r.FailureSeverity == SeverityCritical && !r.EndToEndPass {
			m.CriticalSemanticFailures++
		}

		exp := string(ResolveUnknownExpectation(c))
		if adjudicated && (c.ID == "E03_no_budget" || c.ID == "E04_partial_facts_missing") {
			exp = string(UnknownNotRequired)
		}
		stat := m.UnknownByExpectation[exp]
		stat.Expectation = exp
		stat.Runs++
		if r.UnknownBehaviorPass {
			stat.Pass++
		} else {
			stat.Fail++
		}
		m.UnknownByExpectation[exp] = stat

		debt := AnalyzeDebtFacts(c)
		if debt.DebtFactsMissing {
			m.MissingDataUnknown.Runs++
			if r.UnknownBehaviorPass {
				m.MissingDataUnknown.Pass++
			} else {
				m.MissingDataUnknown.Fail++
			}
		} else if debt.DebtFactsPartial || AnalyzeInsufficientDataCase(c).Classification == DataOptionalAbsent {
			m.PartialDataUnknown.Runs++
			if r.UnknownBehaviorPass {
				m.PartialDataUnknown.Pass++
			} else {
				m.PartialDataUnknown.Fail++
			}
		}

		if len(c.AllowedActions) > 0 {
			m.ActionValidityTotal++
			if r.Semantic.ActionCompliancePass {
				m.ActionValidityPassCount++
			}
		}
	}
	if m.TotalRuns > 0 {
		m.SemanticSuccessRate = rate(m.SemanticSuccessCount, m.TotalRuns)
		m.ExpectedRiskMatchRate = rate(m.ExpectedRiskMatchCount, m.TotalRuns)
		m.UnknownBehaviorPassRate = rate(m.UnknownBehaviorPassCount, m.TotalRuns)
	}
	for exp, stat := range m.UnknownByExpectation {
		stat.PassRate = rate(stat.Pass, stat.Runs)
		m.UnknownByExpectation[exp] = stat
	}
	m.MissingDataUnknown.Expectation = "genuinelyMissingData"
	m.MissingDataUnknown.PassRate = rate(m.MissingDataUnknown.Pass, m.MissingDataUnknown.Runs)
	m.PartialDataUnknown.Expectation = "partialData"
	m.PartialDataUnknown.PassRate = rate(m.PartialDataUnknown.Pass, m.PartialDataUnknown.Runs)
	return m
}

func computeSafetyMetrics(rawResults []RunResult, caseMap map[string]EvaluationCase, adjResults []RunResult) (SafetyMetrics, SafetyMetrics) {
	contract := SafetyMetrics{}
	scenario := SafetyMetrics{}

	for _, r := range rawResults {
		contract.InventedAmountCount += r.InventedFacts
		contract.InvalidCitedFactCount += r.InvalidCitedFactCount
		contract.InvalidKeyFactSourceCount += r.InvalidKeyFactSource
		contract.InvalidReferenceCount += r.InvalidReferenceCount
		contract.InvalidActionCount += r.InvalidActionCount

		scenario.ForbiddenClaimCount += r.ForbiddenClaimCount
		c := caseMap[r.CaseID]
		if c.ID == "C01_no_debt" {
			audit := AuditC01ForbiddenClaim(c, r)
			if audit.ConfirmedSemanticHallucination {
				scenario.KnownZeroContradictionCount++
			}
		}
	}

	for _, r := range adjResults {
		c := caseMap[r.CaseID]
		debt := AnalyzeDebtFacts(c)
		if ResolveUnknownExpectation(c) == UnknownRequired && debt.DebtFactsMissing && !r.UnknownBehaviorPass {
			scenario.MissingDataOverconfidenceCount++
		}
		if ResolveUnknownExpectation(c) == UnknownRequired && debt.DebtFactsMissing && (r.InventedFacts > 0 || !r.Semantic.FactKeyCompliancePass) {
			scenario.DataInsufficientFabricationCount++
		}
	}

	contract.ContractFactSafetyPass = contract.InventedAmountCount == 0 &&
		contract.InvalidKeyFactSourceCount == 0 &&
		contract.InvalidReferenceCount == 0 &&
		contract.InvalidActionCount == 0

	scenario.ScenarioSemanticSafetyPass = scenario.KnownZeroContradictionCount == 0 &&
		scenario.DataInsufficientFabricationCount == 0
	return contract, scenario
}

func deriveIntegrationReadiness(metrics AggregateMetrics, contract SafetyMetrics) string {
	contractRate := rate(metrics.ContractAmongHTTPSuccesses, metrics.HTTPSuccessCount)
	if contractRate >= contractComplianceThreshold && contract.ContractFactSafetyPass {
		return ReadinessPass
	}
	return ReadinessFail
}

func deriveProductionSemanticReadiness(adj AdjudicatedMetrics, scenario SafetyMetrics, c01 ForbiddenClaimAudit, analysis FullEvalAnalysis) string {
	if c01.ConfirmedSemanticHallucination {
		return ReadinessFail
	}
	if adj.EvaluatorFalsePositives > 0 {
		return ReadinessFail
	}
	if adj.ExpectedRiskMatchRate < riskMatchThreshold {
		return ReadinessFail
	}
	if !scenario.ScenarioSemanticSafetyPass {
		return ReadinessFail
	}
	if analysis.ConfirmedModelFailures > 0 {
		return ReadinessFail
	}
	return ReadinessPass
}

func findRun(results []RunResult, caseID string, runIndex int) *RunResult {
	for i := range results {
		if results[i].CaseID == caseID && results[i].RunIndex == runIndex {
			return &results[i]
		}
	}
	return nil
}

func copyIntMap(in map[string]int) map[string]int {
	out := map[string]int{}
	for k, v := range in {
		out[k] = v
	}
	return out
}

// LoadAndAdjudicateReport loads latest.json and adjudicates offline.
func LoadAndAdjudicateReport(path string) (AdjudicationReport, error) {
	report, err := LoadReport(path)
	if err != nil {
		return AdjudicationReport{}, err
	}
	adj := AdjudicateFullEvaluation(report, AllCases())
	adj.SourceReportPath = path
	return adj, nil
}

// FormatAdjudicationSummary renders the P0-4.4D final report.
func FormatAdjudicationSummary(adj AdjudicationReport, report EvaluationReport) string {
	var b strings.Builder
	m := report.Metrics
	a := report.Analysis

	b.WriteString("=== P0-4.4D Full Evaluation Adjudication ===\n\n")

	b.WriteString("--- E03 no_budget ---\n")
	b.WriteString(fmt.Sprintf("semantics=%s budgetInFactContract=%v\n", adj.E03Audit.DataSemantics.Summary, adj.E03Audit.DataSemantics.BudgetInFactContract))
	b.WriteString(fmt.Sprintf("correctedExpectation=%s offlineRescorePassed=%v adjudicatedVerdict=%s\n",
		adj.E03Audit.CorrectedExpectation, adj.E03Audit.OfflineRescorePassed, adj.E03Audit.AdjudicatedVerdict))

	b.WriteString("\n--- E04 partial_facts_missing ---\n")
	b.WriteString(fmt.Sprintf("semantics=%s safeBalancePresent=%v minimumBalancePresent=%v\n",
		adj.E04Audit.DataSemantics.Summary, adj.E04Audit.DataSemantics.SafeBalancePresent, adj.E04Audit.DataSemantics.MinimumBalancePresent))
	b.WriteString(fmt.Sprintf("correctedExpectation=%s offlineRescorePassed=%v adjudicatedVerdict=%s\n",
		adj.E04Audit.CorrectedExpectation, adj.E04Audit.OfflineRescorePassed, adj.E04Audit.AdjudicatedVerdict))

	b.WriteString(fmt.Sprintf("\nofflineRescoreEvaluatorFalsePositives=%d\n", adj.RawMetrics.EvaluatorFalsePositives-adj.AdjudicatedMetrics.EvaluatorFalsePositives))

	if adj.C01Audit.CaseID != "" {
		b.WriteString("\n--- C01 no_debt ---\n")
		b.WriteString(fmt.Sprintf("debtKnownZero=%v forbiddenClaimType=%s\n", adj.C01Audit.DebtKnownZero, adj.C01Audit.ForbiddenClaimType))
		b.WriteString(fmt.Sprintf("violatedForbiddenFactKeys=%s\n", strings.Join(adj.C01Audit.ViolatedForbiddenFactKeys, ",")))
		b.WriteString(fmt.Sprintf("referencePaths=%s\n", strings.Join(adj.C01Audit.ReferencePaths, ",")))
		b.WriteString(fmt.Sprintf("confirmedSemanticHallucination=%v severity=%s\n",
			adj.C01Audit.ConfirmedSemanticHallucination, adj.C01Audit.Severity))
	}

	b.WriteString("\n--- Contract Fact Safety ---\n")
	b.WriteString(fmt.Sprintf("inventedAmount=%d invalidKeyFactSource=%d invalidReference=%d invalidAction=%d pass=%v\n",
		adj.ContractFactSafety.InventedAmountCount, adj.ContractFactSafety.InvalidKeyFactSourceCount,
		adj.ContractFactSafety.InvalidReferenceCount, adj.ContractFactSafety.InvalidActionCount,
		adj.ContractFactSafety.ContractFactSafetyPass))

	b.WriteString("\n--- Scenario Semantic Safety ---\n")
	b.WriteString(fmt.Sprintf("forbiddenClaim=%d knownZeroContradiction=%d missingDataOverconfidence=%d dataInsufficientFabrication=%d pass=%v\n",
		adj.ScenarioSemanticSafety.ForbiddenClaimCount, adj.ScenarioSemanticSafety.KnownZeroContradictionCount,
		adj.ScenarioSemanticSafety.MissingDataOverconfidenceCount, adj.ScenarioSemanticSafety.DataInsufficientFabricationCount,
		adj.ScenarioSemanticSafety.ScenarioSemanticSafetyPass))

	b.WriteString("\n--- Corrected Unknown Metrics ---\n")
	for _, stat := range sortedUnknownStats(adj.AdjudicatedMetrics.UnknownByExpectation) {
		b.WriteString(fmt.Sprintf("%s: pass=%d fail=%d rate=%.1f%%\n", stat.Expectation, stat.Pass, stat.Fail, stat.PassRate*100))
	}
	b.WriteString(fmt.Sprintf("genuinelyMissingData: pass=%d fail=%d\n", adj.AdjudicatedMetrics.MissingDataUnknown.Pass, adj.AdjudicatedMetrics.MissingDataUnknown.Fail))
	b.WriteString(fmt.Sprintf("partialData: pass=%d fail=%d\n", adj.AdjudicatedMetrics.PartialDataUnknown.Pass, adj.AdjudicatedMetrics.PartialDataUnknown.Fail))

	b.WriteString("\n--- Risk Metrics (unchanged) ---\n")
	b.WriteString(fmt.Sprintf("expectedRiskMatch=%d/%d (%.1f%%)\n", m.ExpectedRiskMatchCount, m.TotalRuns, rate(m.ExpectedRiskMatchCount, m.TotalRuns)*100))
	for _, dir := range sortedKeysIntMap(adj.RiskMismatchDirections) {
		b.WriteString(fmt.Sprintf("%s=%d\n", dir, adj.RiskMismatchDirections[dir]))
	}

	b.WriteString("\n--- Action Validity / Stability ---\n")
	b.WriteString(fmt.Sprintf("actionValidityPass=%d/%d\n", adj.AdjudicatedMetrics.ActionValidityPassCount, adj.AdjudicatedMetrics.ActionValidityTotal))
	for _, s := range adj.RepeatStability {
		b.WriteString(fmt.Sprintf("%s: %s\n", s.CaseID, s.StabilitySummary))
	}

	b.WriteString("\n--- Raw vs Adjudicated ---\n")
	b.WriteString(fmt.Sprintf("rawConfirmedModelFailures=%d rawEvaluatorFalsePositives=%d\n",
		adj.RawMetrics.ConfirmedModelFailures, adj.RawMetrics.EvaluatorFalsePositives))
	b.WriteString(fmt.Sprintf("adjudicatedConfirmedModelFailures=%d adjudicatedEvaluatorFalsePositives=%d\n",
		adj.AdjudicatedMetrics.ConfirmedModelFailures, adj.AdjudicatedMetrics.EvaluatorFalsePositives))
	b.WriteString(fmt.Sprintf("adjudicatedUnknownPass=%d/%d criticalSemanticFailures=%d\n",
		adj.AdjudicatedMetrics.UnknownBehaviorPassCount, adj.AdjudicatedMetrics.TotalRuns, adj.AdjudicatedMetrics.CriticalSemanticFailures))

	b.WriteString("\n--- Readiness ---\n")
	b.WriteString(fmt.Sprintf("IntegrationReadiness=%s\n", adj.IntegrationReadiness))
	b.WriteString(fmt.Sprintf("ProductionSemanticReadiness=%s\n", adj.ProductionSemanticReadiness))
	b.WriteString(fmt.Sprintf("P0-4.4 verdict: %s\n", adj.P0Verdict))
	b.WriteString(fmt.Sprintf("PromptOptimizationNeeded=%v ModelComparisonRecommended=%v DeterministicRiskPolicyRecommended=%v\n",
		adj.PromptOptimizationNeeded, adj.ModelComparisonRecommended, adj.DeterministicRiskPolicyRecommended))

	_ = a
	return b.String()
}
