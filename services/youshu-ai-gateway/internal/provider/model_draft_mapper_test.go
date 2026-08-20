package provider_test

import (
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/handler"
	"github.com/youshu/youshu-ai-gateway/internal/provider"
)

func sampleFacts() *contract.MonthlySummaryFactsDTO {
	return &contract.MonthlySummaryFactsDTO{
		AvailableCash:            contract.MoneyDTO{Amount: "10000", CurrencyCode: "CNY"},
		MonthlyIncome:            contract.MoneyDTO{Amount: "12000", CurrencyCode: "CNY"},
		MonthlyExpense:           contract.MoneyDTO{Amount: "6000", CurrencyCode: "CNY"},
		MonthlyDebtPayment:       contract.MoneyDTO{Amount: "2000", CurrencyCode: "CNY"},
		PrimaryPressure:          "日常支出",
		EstimatedMonthEndBalance: contract.MoneyDTO{Amount: "8000", CurrencyCode: "CNY"},
	}
}

func emptyAssessment() *contract.FinancialRiskAssessmentDTO {
	return &contract.FinancialRiskAssessmentDTO{
		OverallLevel:  "safe",
		DebtDataState: "knownDebt",
		DataCompleteness: contract.FinancialDataCompletenessDTO{
			Debt: "known", CashFlowProjection: "known", Income: "known", Expense: "known",
		},
	}
}

func TestMapModelDraftMaterializesMoneyFromFactPack(t *testing.T) {
	facts := sampleFacts()
	model := contract.ModelAssistantAnswerDraftDTO{
		Title:         "t",
		Body:          "b",
		Answer:        "a",
		CitedFactKeys: []string{},
		Confidence:    0.8,
		KeyFacts: []contract.ModelKeyFactDTO{{
			Label:  "可用资金",
			Kind:   "balance",
			Source: "availableCash",
		}},
		References:          []contract.Reference{},
		RiskExplanations:    []contract.ModelRiskExplanationDTO{},
		UnknownExplanations: []contract.ModelUnknownExplanationDTO{},
	}
	draft, err := provider.MapModelDraftToGateway(model, emptyAssessment(), facts)
	if err != nil {
		t.Fatal(err)
	}
	if draft.KeyFacts[0].Value.Amount == nil || *draft.KeyFacts[0].Value.Amount != 10000 {
		t.Fatalf("amount=%v", draft.KeyFacts[0].Value.Amount)
	}
	if len(draft.Warnings) != 0 || len(draft.Actions) != 0 {
		t.Fatal("gateway draft warnings/actions must default empty")
	}
}

func TestMapModelDraftUnknownExplanationsToUnknowns(t *testing.T) {
	model := contract.ModelAssistantAnswerDraftDTO{
		Title:         "t",
		Body:          "b",
		Answer:        "a",
		CitedFactKeys: []string{},
		Confidence:    0.8,
		KeyFacts:        []contract.ModelKeyFactDTO{},
		References:      []contract.Reference{},
		RiskExplanations: []contract.ModelRiskExplanationDTO{},
		UnknownExplanations: []contract.ModelUnknownExplanationDTO{
			{ReasonCode: "debtDataMissing", Text: "债务数据不足"},
		},
	}
	draft, err := provider.MapModelDraftToGateway(model, emptyAssessment(), sampleFacts())
	if err != nil {
		t.Fatal(err)
	}
	if len(draft.Unknowns) != 1 || draft.Unknowns[0] != "债务数据不足" {
		t.Fatalf("unknowns=%v", draft.Unknowns)
	}
}

func TestMapModelDraftMaterializesPercentFromFactPack(t *testing.T) {
	pct := "40"
	facts := sampleFacts()
	facts.DebtPaymentToIncomePercent = &pct
	model := sampleModelDraft("debtPaymentToIncomePercent")
	draft, err := provider.MapModelDraftToGateway(model, emptyAssessment(), facts)
	if err != nil {
		t.Fatal(err)
	}
	if draft.KeyFacts[0].Value.PercentValue == nil || *draft.KeyFacts[0].Value.PercentValue != 40 {
		t.Fatal("percent not materialized")
	}
}

func TestMapModelDraftMaterializesTextFromFactPack(t *testing.T) {
	model := sampleModelDraft("primaryPressure")
	draft, err := provider.MapModelDraftToGateway(model, emptyAssessment(), sampleFacts())
	if err != nil {
		t.Fatal(err)
	}
	if draft.KeyFacts[0].Value.TextValue == nil || *draft.KeyFacts[0].Value.TextValue != "日常支出" {
		t.Fatal("text not materialized")
	}
}

func TestValidateModelDraftMissingSourceFails(t *testing.T) {
	model := sampleModelDraft("")
	model.KeyFacts[0].Source = ""
	if err := provider.ValidateModelDraft(model); err == nil {
		t.Fatal("missing source must fail")
	}
}

func TestValidateModelDraftMappedGatewayDraftPassesValidateDraft(t *testing.T) {
	facts := sampleFacts()
	model := contract.ModelAssistantAnswerDraftDTO{
		Title:         "本月财务摘要",
		Body:          "body",
		Answer:        "answer",
		CitedFactKeys: []string{"availableCash"},
		Confidence:    0.8,
		KeyFacts: []contract.ModelKeyFactDTO{{
			Label:  "可用资金",
			Kind:   "balance",
			Source: "availableCash",
		}},
		References:          []contract.Reference{{Key: "availableCash"}},
		RiskExplanations:    []contract.ModelRiskExplanationDTO{},
		UnknownExplanations: []contract.ModelUnknownExplanationDTO{},
	}
	draft, err := provider.MapModelDraftToGateway(model, emptyAssessment(), facts)
	if err != nil {
		t.Fatal(err)
	}
	if err := handler.ValidateDraft(draft); err != nil {
		t.Fatal(err)
	}
}

func sampleModelDraft(source string) contract.ModelAssistantAnswerDraftDTO {
	return contract.ModelAssistantAnswerDraftDTO{
		Title:      "t",
		Body:       "b",
		Answer:     "a",
		Confidence: 0.8,
		KeyFacts: []contract.ModelKeyFactDTO{{
			Label:  "x",
			Kind:   "other",
			Source: source,
		}},
		References:          []contract.Reference{},
		RiskExplanations:    []contract.ModelRiskExplanationDTO{},
		UnknownExplanations: []contract.ModelUnknownExplanationDTO{},
	}
}
