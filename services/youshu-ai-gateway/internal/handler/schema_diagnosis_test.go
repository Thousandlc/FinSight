package handler_test

import (
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/handler"
)

func TestDiagnoseSchemaEmptyTitle(t *testing.T) {
	d := contract.AssistantAnswerDraftDTO{
		Title:         "",
		Body:          "正文",
		Answer:        "正文",
		CitedFactKeys: []string{},
		Unknowns:      []string{},
		KeyFacts:      []contract.KeyFact{},
		Warnings:      []contract.Warning{},
		Actions:       []contract.Action{},
		References:    []contract.Reference{},
	}
	diag := handler.DiagnoseSchema(d)
	if diag.Passed {
		t.Fatal("expected fail")
	}
	if diag.TitleValid {
		t.Fatal("titleValid")
	}
	if !diag.BodyValid || !diag.AnswerValid || !diag.ArraysValid {
		t.Fatal("other fields should pass")
	}
	if diag.FailedRule == "" {
		t.Fatal("expected failed rule")
	}
}
