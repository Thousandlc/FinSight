package eval

import (
	"github.com/youshu/youshu-ai-gateway/internal/contract"
)

// NarrativeClassifierExpectation describes expected offline classifier behavior.
type NarrativeClassifierExpectation string

const (
	ClassifierExpectPass         NarrativeClassifierExpectation = "pass"
	ClassifierExpectFail         NarrativeClassifierExpectation = "fail"
	ClassifierExpectManualReview NarrativeClassifierExpectation = "manualReview"
)

// NarrativeClassifierFixture defines an offline evaluator false-positive guard case.
type NarrativeClassifierFixture struct {
	Name        string
	CaseID      string
	Narrative   string
	Expected    NarrativeClassifierExpectation
	Classifier  string
}

// ClassifierFixtureResult summarizes offline fixture evaluation.
type ClassifierFixtureResult struct {
	ConfirmedCorrectClassifications int
	EvaluatorFalsePositives         int
	AmbiguousManualReview             int
	Failures                        []string
}

// AllNarrativeClassifierFixtures returns the offline evaluator FP guard suite.
func AllNarrativeClassifierFixtures() []NarrativeClassifierFixture {
	return []NarrativeClassifierFixture{
		// knownNoDebt
		{Name: "knownNoDebt_pass_inventory", CaseID: "C01_no_debt", Narrative: "当前确认的债务清单中没有未结清债务，现金流稳定。", Expected: ClassifierExpectPass, Classifier: "knownNoDebt"},
		{Name: "knownNoDebt_pass_negated_pressure", CaseID: "C01_no_debt", Narrative: "目前没有债务压力。", Expected: ClassifierExpectPass, Classifier: "knownNoDebt"},
		{Name: "knownNoDebt_pass_negated_repayment", CaseID: "C01_no_debt", Narrative: "当前没有还款压力。", Expected: ClassifierExpectPass, Classifier: "knownNoDebt"},
		{Name: "knownNoDebt_fail_pressure", CaseID: "C01_no_debt", Narrative: "当前债务压力较高，需要关注。", Expected: ClassifierExpectFail, Classifier: "knownNoDebt"},
		{Name: "knownNoDebt_fail_exist_pressure", CaseID: "C01_no_debt", Narrative: "你目前存在债务压力。", Expected: ClassifierExpectFail, Classifier: "knownNoDebt"},
		{Name: "knownNoDebt_fail_bare_pressure", CaseID: "C01_no_debt", Narrative: "正文包含债务压力。", Expected: ClassifierExpectFail, Classifier: "knownNoDebt"},
		{Name: "knownNoDebt_manual_ambiguous", CaseID: "C01_no_debt", Narrative: "债务方面还需要继续观察。", Expected: ClassifierExpectManualReview, Classifier: "knownNoDebt"},
		{Name: "knownNoDebt_manual_watch", CaseID: "C01_no_debt", Narrative: "债务方面仍值得关注。", Expected: ClassifierExpectManualReview, Classifier: "knownNoDebt"},

		// missing debt
		{Name: "missingDebt_pass_acknowledge", CaseID: "E05_missing_debt_data", Narrative: "目前债务数据不足，暂无法完整判断。", Expected: ClassifierExpectPass, Classifier: "missingDebt"},
		{Name: "missingDebt_fail_no_debt_claim", CaseID: "E05_missing_debt_data", Narrative: "你没有债务，整体情况良好。", Expected: ClassifierExpectFail, Classifier: "missingDebt"},
		{Name: "missingDebt_manual_ambiguous", CaseID: "E05_missing_debt_data", Narrative: "债务方面暂时看起来问题不大。", Expected: ClassifierExpectManualReview, Classifier: "missingDebt"},

		// safe + missing
		{Name: "safeMissing_pass_qualified", CaseID: "E05_missing_debt_data", Narrative: "在目前已知信息中，没有发现需要提醒的风险，但债务资料仍不完整。", Expected: ClassifierExpectPass, Classifier: "safePlusMissing"},
		{Name: "safeMissing_fail_absolute", CaseID: "E05_missing_debt_data", Narrative: "你的整体财务状况完全安全。", Expected: ClassifierExpectFail, Classifier: "safePlusMissing"},
		{Name: "safeMissing_manual_stable", CaseID: "E05_missing_debt_data", Narrative: "目前整体较稳定。", Expected: ClassifierExpectManualReview, Classifier: "safePlusMissing"},

		// severity
		{Name: "severity_warning_pass_notice", CaseID: "C03_high_monthly_payment", Narrative: "还款占比值得关注，需要留意现金流。", Expected: ClassifierExpectPass, Classifier: "severity"},
		{Name: "severity_warning_fail_crisis", CaseID: "C03_high_monthly_payment", Narrative: "已经出现严重资金危机。", Expected: ClassifierExpectFail, Classifier: "severity"},
		{Name: "severity_risk_pass_gap", CaseID: "B04_short_term_negative_balance", Narrative: "存在明显资金缺口风险。", Expected: ClassifierExpectPass, Classifier: "severity"},
		{Name: "severity_risk_fail_downplay", CaseID: "B04_short_term_negative_balance", Narrative: "只是一个很轻微的问题。", Expected: ClassifierExpectFail, Classifier: "severity"},

		// unsupported narrative risk
		{Name: "unsupported_pass_budget_tip", CaseID: "A01_healthy_cashflow", Narrative: "建议继续保持记账习惯并关注预算。", Expected: ClassifierExpectPass, Classifier: "unsupportedRisk"},
		{Name: "unsupported_fail_new_risk", CaseID: "A01_healthy_cashflow", Narrative: "存在高债务风险，即将出现资金缺口。", Expected: ClassifierExpectFail, Classifier: "unsupportedRisk"},
	}
}

// EvaluateClassifierFixtures runs the offline FP guard suite.
func EvaluateClassifierFixtures() ClassifierFixtureResult {
	result := ClassifierFixtureResult{}
	for _, fixture := range AllNarrativeClassifierFixtures() {
		c := caseForClassifierFixture(fixture)
		actual := classifyNarrativeFixture(c, fixture.Narrative, fixture.Classifier)
		if actual == fixture.Expected {
			result.ConfirmedCorrectClassifications++
			if actual == ClassifierExpectManualReview {
				result.AmbiguousManualReview++
			}
			continue
		}
		if fixture.Expected == ClassifierExpectPass {
			result.EvaluatorFalsePositives++
		}
		result.Failures = append(result.Failures, fixture.Name+": expected "+string(fixture.Expected)+" got "+string(actual))
	}
	return result
}

func caseForClassifierFixture(fixture NarrativeClassifierFixture) EvaluationCase {
	for _, c := range AllCases() {
		if c.ID == fixture.CaseID {
			return c
		}
	}
	return EvaluationCase{ID: fixture.CaseID, Assessment: contract.FinancialRiskAssessmentDTO{}}
}

func classifyNarrativeFixture(c EvaluationCase, narrative string, classifier string) NarrativeClassifierExpectation {
	draft := contract.AssistantAnswerDraftDTO{Title: "t", Body: narrative, Answer: "a"}
	analysis := AnalyzeNarrativeSemantics(c, draft)
	switch classifier {
	case "knownNoDebt":
		if analysis.KnownNoDebtContradictionCount > 0 {
			return ClassifierExpectFail
		}
		if analysis.ManualReviewRequired {
			return ClassifierExpectManualReview
		}
		return ClassifierExpectPass
	case "missingDebt":
		if analysis.MissingDebtOverconfidenceCount > 0 {
			return ClassifierExpectFail
		}
		if analysis.ManualReviewRequired {
			return ClassifierExpectManualReview
		}
		return ClassifierExpectPass
	case "safePlusMissing":
		if analysis.SafePlusMissingMisstatementCount > 0 {
			return ClassifierExpectFail
		}
		if analysis.ManualReviewRequired {
			return ClassifierExpectManualReview
		}
		return ClassifierExpectPass
	case "severity":
		if analysis.NarrativeSeverityMismatchCount > 0 {
			return ClassifierExpectFail
		}
		return ClassifierExpectPass
	case "unsupportedRisk":
		if analysis.UnsupportedNarrativeRiskClaimCount > 0 {
			return ClassifierExpectFail
		}
		return ClassifierExpectPass
	default:
		return ClassifierExpectPass
	}
}
