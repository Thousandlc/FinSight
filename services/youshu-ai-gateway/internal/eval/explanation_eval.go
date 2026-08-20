package eval

import (
	"fmt"
	"sort"
	"strings"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/factpack"
	"github.com/youshu/youshu-ai-gateway/internal/provider"
)

// ExplanationAlignmentAnalysis holds granular explanation contract metrics for one run.
type ExplanationAlignmentAnalysis struct {
	RiskCoveragePass          bool
	UnknownCoveragePass       bool
	CitationAlignmentPass     bool
	MissingRiskExplanationCount          int
	UnsupportedRiskExplanationCount      int
	MissingRequiredUnknownExplanationCount int
	UnsupportedUnknownExplanationCount   int
	CitationMisalignmentCount            int
}

// NarrativeSemanticAnalysis holds conservative narrative contradiction metrics.
type NarrativeSemanticAnalysis struct {
	KnownNoDebtContradictionCount      int
	MissingDebtOverconfidenceCount     int
	SafePlusMissingMisstatementCount   int
	NarrativeSeverityMismatchCount     int
	UnsupportedNarrativeRiskClaimCount int
	ManualReviewRequired               bool
	ManualReviewNotes                  []string
}

// V2SemanticResult extends semantic evaluation for explanation-alignment mode.
type V2SemanticResult struct {
	Passed                     bool
	FailureClasses             []string
	Details                    []string
	Explanation                ExplanationAlignmentAnalysis
	PolicyStructuralPass       bool
	FinalValidatorPass         bool
	Narrative                  NarrativeSemanticAnalysis
	ManualReviewRequired       bool
}

// AnalyzeModelExplanationAlignment computes granular explanation metrics from model DTO.
func AnalyzeModelExplanationAlignment(
	model contract.ModelAssistantAnswerDraftDTO,
	assessment contract.FinancialRiskAssessmentDTO,
	facts *contract.MonthlySummaryFactsDTO,
) ExplanationAlignmentAnalysis {
	keys := factpack.BuildKeySets(facts)
	expectedRisk := expectedSignalReasonCodes(&assessment)
	expectedUnknown := append([]string(nil), assessment.DataCompleteness.RequiredUnknownReasonCodes...)
	sort.Strings(expectedUnknown)

	actualRisk := collectReasonCodes(model.RiskExplanations)
	actualUnknown := collectUnknownReasonCodes(model.UnknownExplanations)

	analysis := ExplanationAlignmentAnalysis{
		RiskCoveragePass:      setEqual(actualRisk, expectedRisk),
		UnknownCoveragePass:   setEqual(actualUnknown, expectedUnknown),
		CitationAlignmentPass: true,
	}

	if !analysis.RiskCoveragePass {
		analysis.MissingRiskExplanationCount = len(setDifference(expectedRisk, actualRisk))
		analysis.UnsupportedRiskExplanationCount = len(setDifference(actualRisk, expectedRisk))
	}
	if !analysis.UnknownCoveragePass {
		analysis.MissingRequiredUnknownExplanationCount = len(setDifference(expectedUnknown, actualUnknown))
		analysis.UnsupportedUnknownExplanationCount = len(setDifference(actualUnknown, expectedUnknown))
	}

	if err := validateAssembledRiskCitationAlignment(model.RiskExplanations, &assessment, keys); err != nil {
		analysis.CitationAlignmentPass = false
		analysis.CitationMisalignmentCount = 1
	}
	return analysis
}

// CheckExplanationExpectationsV2 evaluates post-contract semantic rules for v2 mode.
func CheckExplanationExpectationsV2(
	c EvaluationCase,
	draft contract.AssistantAnswerDraftDTO,
	explanationPass bool,
	provenancePass bool,
) V2SemanticResult {
	result := V2SemanticResult{
		Explanation: ExplanationAlignmentAnalysis{
			RiskCoveragePass:      explanationPass,
			UnknownCoveragePass:   explanationPass,
			CitationAlignmentPass: provenancePass,
		},
		PolicyStructuralPass: true,
		FinalValidatorPass:   true,
	}

	if !explanationPass {
		result.addFailure(FailureExplanationRiskCoverage, "model explanation alignment failed at decode")
	}
	if !provenancePass {
		result.addFailure(FailureProvenanceAssembly, "deterministic provenance assembly failed at decode")
	}

	policyPass, policyDetail := EvaluatePolicyStructuralAlignment(c.Assessment, draft)
	result.PolicyStructuralPass = policyPass
	if !policyPass {
		result.addFailure(FailurePolicyProjection, policyDetail)
	}

	result.FinalValidatorPass = explanationPass && provenancePass && policyPass
	if !result.FinalValidatorPass {
		result.addFailure(FailureFinalValidator, "final validator pipeline failed")
	}

	narrative := AnalyzeNarrativeSemantics(c, draft)
	result.Narrative = narrative
	if narrative.ManualReviewRequired {
		result.ManualReviewRequired = true
		result.addFailure(FailureManualReview, strings.Join(narrative.ManualReviewNotes, "; "))
	}
	if narrative.KnownNoDebtContradictionCount > 0 {
		result.addFailure(FailureNarrativeKnownNoDebt, "knownNoDebt narrative contradiction")
	}
	if narrative.MissingDebtOverconfidenceCount > 0 {
		result.addFailure(FailureNarrativeMissingData, "missing debt overconfidence")
	}
	if narrative.SafePlusMissingMisstatementCount > 0 {
		result.addFailure(FailureNarrativeSafeMissing, "safe plus missing misstatement")
	}
	if narrative.NarrativeSeverityMismatchCount > 0 {
		result.addFailure(FailureNarrativeSeverity, "narrative severity mismatch")
	}
	if narrative.UnsupportedNarrativeRiskClaimCount > 0 {
		result.addFailure(FailureNarrativeUnsupportedRisk, "unsupported narrative risk claim")
	}

	// Fact safety checks retained from legacy expectations.
	legacy := CheckExpectations(c, draft)
	result.ManualReviewRequired = result.ManualReviewRequired || legacy.ManualReviewRequired
	narrativeText := collectNarrative(draft)
	for _, hit := range legacy.ForbiddenClaimHits {
		if isKnownNoDebtNarrativeForbiddenClaim(c, hit, narrativeText) {
			if narrative.KnownNoDebtContradictionCount == 0 {
				narrative.KnownNoDebtContradictionCount++
				result.Narrative = narrative
			}
			result.addFailure(FailureNarrativeKnownNoDebt, "knownNoDebt narrative contradiction: "+hit)
			continue
		}
		result.addFailure(FailureSemanticForbidden, "forbidden claim: "+hit)
	}
	if !legacy.ReferenceCompliancePass {
		result.addFailure(FailureSemanticForbidden, "forbidden reference key")
	}
	if !legacy.KeyFactSelectionSemanticPass {
		result.addFailure(FailureForbiddenKeyFactSource, "forbidden keyFact source")
	}
	if !legacy.CitationSemanticPass {
		result.addFailure(FailureForbiddenCitationFact, "forbidden top-level citation fact key")
	}

	result.Passed = len(result.FailureClasses) == 0
	return result
}

func (r *V2SemanticResult) addFailure(class, detail string) {
	r.FailureClasses = appendUnique(r.FailureClasses, class)
	r.Details = append(r.Details, detail)
}

func expectedSignalReasonCodes(assessment *contract.FinancialRiskAssessmentDTO) []string {
	var reasons []string
	for _, signal := range assessment.Signals {
		if signal.Level == "safe" {
			continue
		}
		reasons = append(reasons, signal.ReasonCode)
	}
	sort.Strings(reasons)
	return reasons
}

func collectReasonCodes(items []contract.ModelRiskExplanationDTO) []string {
	out := make([]string, 0, len(items))
	for _, item := range items {
		out = append(out, strings.TrimSpace(item.ReasonCode))
	}
	sort.Strings(out)
	return out
}

func collectUnknownReasonCodes(items []contract.ModelUnknownExplanationDTO) []string {
	out := make([]string, 0, len(items))
	for _, item := range items {
		out = append(out, strings.TrimSpace(item.ReasonCode))
	}
	sort.Strings(out)
	return out
}

func setEqual(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

func setDifference(want, have []string) []string {
	haveSet := map[string]struct{}{}
	for _, item := range have {
		haveSet[item] = struct{}{}
	}
	var diff []string
	for _, item := range want {
		if _, ok := haveSet[item]; !ok {
			diff = append(diff, item)
		}
	}
	return diff
}

func validateAssembledRiskCitationAlignment(
	modelExplanations []contract.ModelRiskExplanationDTO,
	assessment *contract.FinancialRiskAssessmentDTO,
	keys factpack.KeySets,
) error {
	assembled, err := provider.AssembleRiskExplanations(modelExplanations, assessment)
	if err != nil {
		return err
	}
	return provider.ValidateAssembledRiskExplanationProvenance(assembled, assessment, keys)
}

func primarySourceFactKey(signal contract.FinancialRiskSignalDTO) string {
	if len(signal.SourceFactKeys) > 0 {
		return signal.SourceFactKeys[0]
	}
	return signal.ReasonCode
}

// EvaluatePolicyStructuralAlignment verifies projected warnings/actions match assessment.
func EvaluatePolicyStructuralAlignment(
	assessment contract.FinancialRiskAssessmentDTO,
	aiDraft contract.AssistantAnswerDraftDTO,
) (bool, string) {
	if len(aiDraft.Warnings) > 0 || len(aiDraft.Actions) > 0 {
		return false, "model draft must not include policy-owned warnings/actions pre-projection"
	}
	projected := ApplyEvalPolicyProjection(aiDraft, assessment)
	expectedWarnings := expectedProjectedWarningCount(assessment)
	if len(projected.Warnings) != expectedWarnings {
		return false, fmt.Sprintf("projected warning count=%d expected=%d", len(projected.Warnings), expectedWarnings)
	}
	expectedActions := expectedProjectedActionDestinations(assessment)
	actualActions := actionDestinations(projected.Actions)
	if !setEqual(actualActions, expectedActions) {
		return false, "projected action destinations mismatch assessment"
	}
	for i, warning := range projected.Warnings {
		signal := nonSafeSignals(assessment)[i]
		if warning.Severity != signal.Level {
			return false, fmt.Sprintf("warning severity mismatch for %s", signal.ReasonCode)
		}
		if warning.Source != primarySourceFactKey(signal) {
			return false, fmt.Sprintf("warning source mismatch for %s", signal.ReasonCode)
		}
	}
	return true, ""
}

func expectedProjectedWarningCount(assessment contract.FinancialRiskAssessmentDTO) int {
	return len(nonSafeSignals(assessment))
}

func nonSafeSignals(assessment contract.FinancialRiskAssessmentDTO) []contract.FinancialRiskSignalDTO {
	var out []contract.FinancialRiskSignalDTO
	for _, signal := range assessment.Signals {
		if signal.Level != "safe" {
			out = append(out, signal)
		}
	}
	sort.Slice(out, func(i, j int) bool {
		return out[i].ReasonCode < out[j].ReasonCode
	})
	return out
}

func expectedProjectedActionDestinations(assessment contract.FinancialRiskAssessmentDTO) []string {
	destSet := map[string]struct{}{}
	for _, signal := range assessment.Signals {
		for _, dest := range signal.RecommendedActionDestinations {
			destSet[dest] = struct{}{}
		}
	}
	out := make([]string, 0, len(destSet))
	for dest := range destSet {
		out = append(out, dest)
	}
	sort.Strings(out)
	return out
}

func actionDestinations(actions []contract.Action) []string {
	out := make([]string, 0, len(actions))
	for _, action := range actions {
		out = append(out, action.Destination)
	}
	sort.Strings(out)
	return out
}

// ApplyEvalPolicyProjection mirrors iOS MonthlySummaryPolicyProjection for evaluation only.
func ApplyEvalPolicyProjection(
	aiDraft contract.AssistantAnswerDraftDTO,
	assessment contract.FinancialRiskAssessmentDTO,
) contract.AssistantAnswerDraftDTO {
	projected := aiDraft
	projected.Warnings = projectEvalWarnings(assessment)
	projected.Actions = projectEvalActions(assessment)
	return projected
}

func projectEvalWarnings(assessment contract.FinancialRiskAssessmentDTO) []contract.Warning {
	signals := nonSafeSignals(assessment)
	warnings := make([]contract.Warning, 0, len(signals))
	for _, signal := range signals {
		copyTitle, copyMessage := warningCopyForReason(signal.ReasonCode)
		warnings = append(warnings, contract.Warning{
			Title:    copyTitle,
			Message:  copyMessage,
			Severity: signal.Level,
			Source:   primarySourceFactKey(signal),
		})
	}
	return warnings
}

func projectEvalActions(assessment contract.FinancialRiskAssessmentDTO) []contract.Action {
	destinations := expectedProjectedActionDestinations(assessment)
	actions := make([]contract.Action, 0, len(destinations))
	for _, dest := range destinations {
		actions = append(actions, contract.Action{
			Title:       actionTitleForDestination(dest),
			Destination: dest,
		})
	}
	return actions
}

func warningCopyForReason(reasonCode string) (title, message string) {
	switch reasonCode {
	case "negativeProjectedBalance":
		return "预计余额缺口", "预计余额可能出现缺口，请关注现金流。"
	case "cashFlowBelowSafeBalance":
		return "现金流提醒", "现金流可能低于安全余额。"
	case "monthEndBelowSafeBalance":
		return "月底结余提醒", "预计月底结余可能低于安全余额。"
	case "highDebtPaymentToIncome":
		return "债务压力偏高", "债务还款占收入比例较高，需关注现金流。"
	case "highDebtPressureScore":
		return "债务压力较高", "债务压力评分偏高，建议关注还款安排。"
	case "criticalDebtPressure":
		return "债务压力严重", "债务压力达到临界水平，请优先处理。"
	case "zeroIncomeWithExpenses":
		return "收支异常", "本月暂未记录收入，但已有支出。"
	default:
		return "财务提醒", "请关注当前财务状况。"
	}
}

func actionTitleForDestination(dest string) string {
	switch dest {
	case "cashFlow":
		return "查看未来现金流"
	case "debt":
		return "查看债务详情"
	case "transactions":
		return "查看交易记录"
	case "accounts":
		return "查看账户"
	default:
		return "查看详情"
	}
}

// EvaluateFinalValidatorPass reports whether the end-to-end contract pipeline succeeded.
func EvaluateFinalValidatorPass(explanationPass, policyPass bool) bool {
	return explanationPass && policyPass
}

// AnalyzeNarrativeSemantics applies conservative narrative contradiction detectors.
func AnalyzeNarrativeSemantics(c EvaluationCase, draft contract.AssistantAnswerDraftDTO) NarrativeSemanticAnalysis {
	narrative := strings.ToLower(collectNarrative(draft))
	analysis := NarrativeSemanticAnalysis{}

	switch c.Assessment.DebtDataState {
	case "knownNoDebt":
		if containsAny(narrative, knownNoDebtPassPhrases) {
			break
		}
		if matchesKnownNoDebtContradiction(narrative) {
			analysis.KnownNoDebtContradictionCount++
		} else if containsAny(narrative, knownNoDebtAmbiguousPhrases) {
			analysis.ManualReviewRequired = true
			analysis.ManualReviewNotes = append(analysis.ManualReviewNotes, "ambiguous knownNoDebt narrative")
		}
	case "missing":
		if containsAny(narrative, missingDebtPassPhrases) {
			break
		}
		if containsAny(narrative, missingDebtOverconfidencePhrases) {
			analysis.MissingDebtOverconfidenceCount++
		} else if containsAny(narrative, missingDebtAmbiguousPhrases) {
			analysis.ManualReviewRequired = true
			analysis.ManualReviewNotes = append(analysis.ManualReviewNotes, "ambiguous missing-debt narrative")
		}
	}

	if c.Assessment.OverallLevel == "safe" && len(c.Assessment.DataCompleteness.RequiredUnknownReasonCodes) > 0 {
		if containsAny(narrative, safePlusMissingPassPhrases) {
			// qualified safe wording allowed
		} else if containsAny(narrative, safePlusMissingMisstatementPhrases) {
			analysis.SafePlusMissingMisstatementCount++
		} else if containsAny(narrative, safePlusMissingAmbiguousPhrases) {
			analysis.ManualReviewRequired = true
			analysis.ManualReviewNotes = append(analysis.ManualReviewNotes, "ambiguous safe+missing narrative")
		}
	}

	if mismatch := detectNarrativeSeverityMismatch(c.Assessment, narrative); mismatch {
		analysis.NarrativeSeverityMismatchCount++
	}

	if unsupported := detectUnsupportedNarrativeRisk(c.Assessment, narrative); unsupported {
		analysis.UnsupportedNarrativeRiskClaimCount++
	}

	return analysis
}

var (
	knownNoDebtPassPhrases = []string{
		"确认的债务清单中没有未结清债务", "没有未结清债务",
		"目前没有债务压力", "当前没有还款压力", "没有债务压力",
		"不存在未结清债务", "目前不存在未结清债务",
		"从已确认的债务信息看，目前不存在未结清债务",
	}
	knownNoDebtAmbiguousPhrases = []string{
		"债务方面还需要继续观察", "债务方面仍值得关注", "债务方面",
	}
	knownNoDebtExplicitContradictionPhrases = []string{
		"债务压力较高", "债务压力高", "债务压力较大", "债务负担重",
		"还款负担较重", "高额债务",
		"存在债务压力", "你目前存在债务压力",
		"还款压力比较大", "需要优先偿还现有债务",
	}
	knownNoDebtPressureStems = []string{
		"债务压力", "还款压力",
	}
	knownNoDebtNegationMarkers = []string{
		"没有", "不存在", "无", "未", "并非", "不算", "并无", "暂无", "暂未", "不曾", "不含", "不在",
	}
	missingDebtPassPhrases = []string{
		"债务数据不足", "暂无法完整判断",
	}
	missingDebtAmbiguousPhrases = []string{
		"债务方面暂时看起来问题不大", "债务情况", "债务状态", "债务方面",
	}
	missingDebtOverconfidencePhrases = []string{
		"没有债务", "无债务", "不存在债务", "你没有债务", "债务较低", "债务很低", "债务压力低",
		"债务压力高", "还款负担重", "dti", "债务收入比",
	}
	safePlusMissingPassPhrases = []string{
		"没有发现需要提醒的风险，但债务资料仍不完整",
		"在目前已知信息中，没有发现需要提醒的风险",
	}
	safePlusMissingAmbiguousPhrases = []string{
		"目前整体较稳定", "整体较稳定",
	}
	safePlusMissingMisstatementPhrases = []string{
		"没有任何财务风险", "整体财务完全安全", "完全没有风险", "不存在任何风险",
		"整体财务状况完全安全",
	}
)

func containsAny(text string, phrases []string) bool {
	for _, phrase := range phrases {
		if strings.Contains(text, strings.ToLower(phrase)) {
			return true
		}
	}
	return false
}

func matchesKnownNoDebtContradiction(narrative string) bool {
	narrative = strings.ToLower(narrative)
	for _, phrase := range knownNoDebtExplicitContradictionPhrases {
		if containsUnnegatedPhrase(narrative, phrase) {
			return true
		}
	}
	for _, stem := range knownNoDebtPressureStems {
		if containsUnnegatedPhrase(narrative, stem) {
			return true
		}
	}
	return false
}

func containsUnnegatedPhrase(text, phrase string) bool {
	phrase = strings.ToLower(phrase)
	start := 0
	for {
		idx := strings.Index(text[start:], phrase)
		if idx < 0 {
			return false
		}
		absIdx := start + idx
		if !isKnownNoDebtPhraseNegated(text, absIdx) {
			return true
		}
		start = absIdx + len(phrase)
	}
}

func isKnownNoDebtPhraseNegated(text string, phraseStart int) bool {
	prefix := strings.TrimSpace(text[:phraseStart])
	if prefix == "" {
		return false
	}
	for _, neg := range knownNoDebtNegationMarkers {
		if strings.HasSuffix(prefix, neg) {
			return true
		}
	}
	windowStart := 0
	if len(prefix) > 24 {
		windowStart = len(prefix) - 24
	}
	window := prefix[windowStart:]
	for _, neg := range knownNoDebtNegationMarkers {
		negIdx := strings.LastIndex(window, neg)
		if negIdx < 0 {
			continue
		}
		tail := window[negIdx+len(neg):]
		if len(tail) <= 12 {
			return true
		}
	}
	return false
}

func detectNarrativeSeverityMismatch(assessment contract.FinancialRiskAssessmentDTO, narrative string) bool {
	switch assessment.OverallLevel {
	case "warning":
		if containsAny(narrative, []string{"值得关注", "需要留意", "存在一定压力"}) {
			return false
		}
		return containsAny(narrative, []string{"严重风险", "高危", "极高风险", "严重资金危机"})
	case "risk":
		if containsAny(narrative, []string{"存在明显资金缺口风险", "资金缺口风险"}) {
			return false
		}
		return containsAny(narrative, []string{"只是轻微提醒", "无需担心", "没有风险", "很轻微的问题"})
	}
	return false
}

func detectUnsupportedNarrativeRisk(assessment contract.FinancialRiskAssessmentDTO, narrative string) bool {
	if assessment.OverallLevel != "safe" || len(nonSafeSignals(assessment)) > 0 {
		return false
	}
	unsupported := []string{"存在高债务风险", "即将出现资金缺口", "即将违约", "确定会逾期", "必然破产", "严重债务危机"}
	return containsAny(narrative, unsupported)
}

func isKnownNoDebtNarrativeForbiddenClaim(c EvaluationCase, hit string, narrative string) bool {
	if c.Assessment.DebtDataState != "knownNoDebt" {
		return false
	}
	hit = strings.ToLower(strings.TrimSpace(hit))
	narrative = strings.ToLower(narrative)
	if isKnownNoDebtDebtPressurePhrase(hit) {
		return containsUnnegatedPhrase(narrative, hit)
	}
	for _, forbidden := range c.ForbiddenClaims {
		if strings.EqualFold(strings.TrimSpace(forbidden), hit) && isKnownNoDebtDebtPressurePhrase(forbidden) {
			return containsUnnegatedPhrase(narrative, strings.ToLower(forbidden))
		}
	}
	return false
}

func isKnownNoDebtDebtPressurePhrase(phrase string) bool {
	switch strings.TrimSpace(phrase) {
	case "债务压力", "还款压力", "债务压力高", "债务压力较高", "还款负担较重", "高额债务":
		return true
	default:
		return false
	}
}
