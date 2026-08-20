package smoke_test

import (
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/smoke"
)

func TestFactValidatorRejectsInventedAmount(t *testing.T) {
	facts := smoke.AllCases()[0].Envelope.MonthlySummaryFacts
	draft := contract.AssistantAnswerDraftDTO{
		Title:         "t",
		Body:          "存在未提供金额 ¥99999",
		Answer:        "存在未提供金额 ¥99999",
		CitedFactKeys: []string{},
		Unknowns:      []string{},
		KeyFacts:      []contract.KeyFact{},
		Warnings:      []contract.Warning{},
		Actions:       []contract.Action{},
		References:    []contract.Reference{},
	}
	result := smoke.ValidateFacts(draft, facts)
	if result.Passed() {
		t.Fatal("expected invented amount failure")
	}
	if result.InventedFactCount == 0 {
		t.Fatal("expected invented fact count > 0")
	}
}

func TestSyntheticCasesCount(t *testing.T) {
	cases := smoke.AllCases()
	if len(cases) != 4 {
		t.Fatalf("expected 4 cases, got %d", len(cases))
	}
	if cases[0].Repeats != 3 || cases[1].Repeats != 3 {
		t.Fatal("Case A/B should repeat 3 times")
	}
}
