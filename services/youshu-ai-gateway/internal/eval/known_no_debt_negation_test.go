package eval

import (
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
)

func knownNoDebtCase(t *testing.T) EvaluationCase {
	t.Helper()
	c, err := findCaseByID("C01_no_debt")
	if err != nil {
		t.Fatal(err)
	}
	return c
}

func narrativeResult(t *testing.T, c EvaluationCase, body string) NarrativeSemanticAnalysis {
	t.Helper()
	return AnalyzeNarrativeSemantics(c, contract.AssistantAnswerDraftDTO{
		Title: "t", Body: body, Answer: "a",
	})
}

func v2Result(t *testing.T, c EvaluationCase, body string) V2SemanticResult {
	t.Helper()
	return CheckExplanationExpectationsV2(c, contract.AssistantAnswerDraftDTO{
		Title: "t", Body: body, Answer: "a",
	}, true, true)
}

func TestKnownNoDebtNegatedPressurePass(t *testing.T) {
	c := knownNoDebtCase(t)
	cases := []string{
		"目前没有债务压力。",
		"当前没有还款压力。",
		"当前确认的债务清单中没有未结清债务。",
		"从已确认的债务信息看，目前不存在未结清债务。",
	}
	for _, body := range cases {
		narr := narrativeResult(t, c, body)
		if narr.KnownNoDebtContradictionCount != 0 {
			t.Fatalf("body=%q expected PASS, got contradiction=%d", body, narr.KnownNoDebtContradictionCount)
		}
		if narr.ManualReviewRequired {
			t.Fatalf("body=%q should not require manual review", body)
		}
	}
}

func TestKnownNoDebtPositiveContradictionFail(t *testing.T) {
	c := knownNoDebtCase(t)
	cases := []string{
		"你目前存在债务压力。",
		"当前债务压力较高。",
		"还款压力比较大。",
		"需要优先偿还现有债务。",
	}
	for _, body := range cases {
		narr := narrativeResult(t, c, body)
		if narr.KnownNoDebtContradictionCount != 1 {
			t.Fatalf("body=%q expected FAIL, got %+v", body, narr)
		}
	}
}

func TestKnownNoDebtBarePressureFrozenC01Fail(t *testing.T) {
	c := knownNoDebtCase(t)
	v2 := v2Result(t, c, "债务压力")
	if v2.Narrative.KnownNoDebtContradictionCount != 1 {
		t.Fatalf("expected contradiction count=1, got %d", v2.Narrative.KnownNoDebtContradictionCount)
	}
	if !containsString(v2.FailureClasses, FailureNarrativeKnownNoDebt) {
		t.Fatalf("expected %s, got %v", FailureNarrativeKnownNoDebt, v2.FailureClasses)
	}
}

func TestKnownNoDebtAmbiguousManualReview(t *testing.T) {
	c := knownNoDebtCase(t)
	narr := narrativeResult(t, c, "债务方面仍值得关注。")
	if narr.KnownNoDebtContradictionCount != 0 {
		t.Fatalf("expected no auto-fail, got contradiction=%d", narr.KnownNoDebtContradictionCount)
	}
	if !narr.ManualReviewRequired {
		t.Fatal("expected manualReview for ambiguous debt wording")
	}
}

func TestKnownNoDebtNegatedDoesNotTriggerForbiddenClaim(t *testing.T) {
	c := knownNoDebtCase(t)
	semantic := CheckExpectations(c, contract.AssistantAnswerDraftDTO{
		Title: "t", Body: "目前没有债务压力。", Answer: "a",
	})
	if len(semantic.ForbiddenClaimHits) != 0 {
		t.Fatalf("negated phrase must not hit forbidden claims: %v", semantic.ForbiddenClaimHits)
	}
}
