package provider_test

import (
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/factpack"
	"github.com/youshu/youshu-ai-gateway/internal/provider"
)

func sampleSafeAssessment() *contract.FinancialRiskAssessmentDTO {
	return &contract.FinancialRiskAssessmentDTO{
		OverallLevel:  "safe",
		PolicyVersion: "v1",
		DebtDataState: "knownNoDebt",
		Signals:       []contract.FinancialRiskSignalDTO{},
		DataCompleteness: contract.FinancialDataCompletenessDTO{
			Debt:                       "known",
			CashFlowProjection:         "known",
			Income:                     "known",
			Expense:                    "known",
			RequiredUnknownReasonCodes: []string{},
		},
	}
}

func sampleDTIAssessment() *contract.FinancialRiskAssessmentDTO {
	return &contract.FinancialRiskAssessmentDTO{
		OverallLevel:  "warning",
		PolicyVersion: "v1",
		DebtDataState: "knownDebt",
		Signals: []contract.FinancialRiskSignalDTO{
			{
				Kind:           "debt",
				Level:          "warning",
				ReasonCode:     "highDebtPaymentToIncome",
				SourceFactKeys: []string{"debtPaymentToIncomePercent"},
			},
		},
		DataCompleteness: contract.FinancialDataCompletenessDTO{
			Debt: "known", CashFlowProjection: "known", Income: "known", Expense: "known",
		},
	}
}

func sampleMissingDebtAssessment() *contract.FinancialRiskAssessmentDTO {
	return &contract.FinancialRiskAssessmentDTO{
		OverallLevel:  "safe",
		PolicyVersion: "v1",
		DebtDataState: "missing",
		Signals:       []contract.FinancialRiskSignalDTO{},
		DataCompleteness: contract.FinancialDataCompletenessDTO{
			Debt:                       "missing",
			CashFlowProjection:         "known",
			Income:                     "known",
			Expense:                    "known",
			RequiredUnknownReasonCodes: []string{"debtDataMissing"},
		},
	}
}

func sampleE01PartialAssessment() *contract.FinancialRiskAssessmentDTO {
	return &contract.FinancialRiskAssessmentDTO{
		OverallLevel:  "warning",
		PolicyVersion: "v1",
		DebtDataState: "partial",
		Signals: []contract.FinancialRiskSignalDTO{
			{
				Kind:           "debt",
				Level:          "warning",
				ReasonCode:     "highDebtPaymentToIncome",
				SourceFactKeys: []string{"debtPaymentToIncomePercent"},
			},
		},
		DataCompleteness: contract.FinancialDataCompletenessDTO{
			Debt:               "partial",
			CashFlowProjection: "partial",
			Income:             "known",
			Expense:            "known",
		},
	}
}

func sampleB04Assessment() *contract.FinancialRiskAssessmentDTO {
	return &contract.FinancialRiskAssessmentDTO{
		OverallLevel:  "risk",
		PolicyVersion: "v1",
		DebtDataState: "knownDebt",
		Signals: []contract.FinancialRiskSignalDTO{
			{
				Kind:           "cashFlow",
				Level:          "risk",
				ReasonCode:     "negativeProjectedBalance",
				SourceFactKeys: []string{"minimumBalance"},
			},
		},
		DataCompleteness: contract.FinancialDataCompletenessDTO{
			Debt: "known", CashFlowProjection: "known", Income: "known", Expense: "known",
		},
	}
}

func sampleDTIFacts() *contract.MonthlySummaryFactsDTO {
	pct := "25"
	return &contract.MonthlySummaryFactsDTO{
		AvailableCash:              contract.MoneyDTO{Amount: "5000", CurrencyCode: "CNY"},
		MonthlyIncome:              contract.MoneyDTO{Amount: "10000", CurrencyCode: "CNY"},
		MonthlyExpense:             contract.MoneyDTO{Amount: "5000", CurrencyCode: "CNY"},
		MonthlyDebtPayment:         contract.MoneyDTO{Amount: "2500", CurrencyCode: "CNY"},
		DebtPaymentToIncomePercent: &pct,
		PrimaryPressure:            "债务还款",
		EstimatedMonthEndBalance:   contract.MoneyDTO{Amount: "3000", CurrencyCode: "CNY"},
	}
}

func TestExplanationAlignmentA01SafeEmpty(t *testing.T) {
	model := contract.ModelAssistantAnswerDraftDTO{
		RiskExplanations:    []contract.ModelRiskExplanationDTO{},
		UnknownExplanations: []contract.ModelUnknownExplanationDTO{},
	}
	facts := sampleDTIFacts()
	keys := factpack.BuildKeySets(facts)
	if err := provider.ValidateExplanationAlignment(model, sampleSafeAssessment(), keys); err != nil {
		t.Fatal(err)
	}
}

func TestExplanationAlignmentExtraRiskFails(t *testing.T) {
	model := contract.ModelAssistantAnswerDraftDTO{
		RiskExplanations: []contract.ModelRiskExplanationDTO{
			{ReasonCode: "highDebtPaymentToIncome", Text: "x"},
		},
	}
	if err := provider.ValidateExplanationAlignment(model, sampleSafeAssessment(), factpack.BuildKeySets(sampleDTIFacts())); err == nil {
		t.Fatal("expected coverage mismatch")
	}
}

func TestExplanationAlignmentC03DTIPass(t *testing.T) {
	model := contract.ModelAssistantAnswerDraftDTO{
		RiskExplanations: []contract.ModelRiskExplanationDTO{
			{ReasonCode: "highDebtPaymentToIncome", Text: "DTI high"},
		},
	}
	if err := provider.ValidateExplanationAlignment(model, sampleDTIAssessment(), factpack.BuildKeySets(sampleDTIFacts())); err != nil {
		t.Fatal(err)
	}
}

func TestExplanationAlignmentMissingRiskFails(t *testing.T) {
	model := contract.ModelAssistantAnswerDraftDTO{RiskExplanations: []contract.ModelRiskExplanationDTO{}}
	if err := provider.ValidateExplanationAlignment(model, sampleDTIAssessment(), factpack.BuildKeySets(sampleDTIFacts())); err == nil {
		t.Fatal("expected missing risk explanation")
	}
}

func TestExplanationAlignmentE01PartialPass(t *testing.T) {
	model := contract.ModelAssistantAnswerDraftDTO{
		RiskExplanations: []contract.ModelRiskExplanationDTO{
			{ReasonCode: "highDebtPaymentToIncome", Text: "partial debt data still requires DTI explanation"},
		},
	}
	if err := provider.ValidateExplanationAlignment(model, sampleE01PartialAssessment(), factpack.BuildKeySets(sampleDTIFacts())); err != nil {
		t.Fatal(err)
	}
}

func TestExplanationAlignmentE01MissingRiskFails(t *testing.T) {
	model := contract.ModelAssistantAnswerDraftDTO{RiskExplanations: []contract.ModelRiskExplanationDTO{}}
	if err := provider.ValidateExplanationAlignment(model, sampleE01PartialAssessment(), factpack.BuildKeySets(sampleDTIFacts())); err == nil {
		t.Fatal("expected E01 missing risk explanation failure")
	}
}

func TestExplanationAlignmentB04Pass(t *testing.T) {
	model := contract.ModelAssistantAnswerDraftDTO{
		RiskExplanations: []contract.ModelRiskExplanationDTO{
			{ReasonCode: "negativeProjectedBalance", Text: "projected balance dips below safe level"},
		},
	}
	facts := &contract.MonthlySummaryFactsDTO{
		AvailableCash:            contract.MoneyDTO{Amount: "1000", CurrencyCode: "CNY"},
		MonthlyIncome:            contract.MoneyDTO{Amount: "8000", CurrencyCode: "CNY"},
		MonthlyExpense:           contract.MoneyDTO{Amount: "7000", CurrencyCode: "CNY"},
		MonthlyDebtPayment:       contract.MoneyDTO{Amount: "500", CurrencyCode: "CNY"},
		PrimaryPressure:          "支出",
		EstimatedMonthEndBalance: contract.MoneyDTO{Amount: "1500", CurrencyCode: "CNY"},
		MinimumBalance:           moneyPtr("500"),
	}
	if err := provider.ValidateExplanationAlignment(model, sampleB04Assessment(), factpack.BuildKeySets(facts)); err != nil {
		t.Fatal(err)
	}
}

func moneyPtr(amount string) *contract.MoneyDTO {
	m := contract.MoneyDTO{Amount: amount, CurrencyCode: "CNY"}
	return &m
}

func TestExplanationAlignmentE05UnknownPass(t *testing.T) {
	model := contract.ModelAssistantAnswerDraftDTO{
		UnknownExplanations: []contract.ModelUnknownExplanationDTO{
			{ReasonCode: "debtDataMissing", Text: "debt missing"},
		},
	}
	facts := sampleDTIFacts()
	if err := provider.ValidateExplanationAlignment(model, sampleMissingDebtAssessment(), factpack.BuildKeySets(facts)); err != nil {
		t.Fatal(err)
	}
}

func TestExplanationAlignmentUnknownEmptyFails(t *testing.T) {
	model := contract.ModelAssistantAnswerDraftDTO{UnknownExplanations: []contract.ModelUnknownExplanationDTO{}}
	if err := provider.ValidateExplanationAlignment(model, sampleMissingDebtAssessment(), factpack.BuildKeySets(sampleDTIFacts())); err == nil {
		t.Fatal("expected unknown coverage mismatch")
	}
}

func TestExplanationAlignmentUnsupportedUnknownFails(t *testing.T) {
	model := contract.ModelAssistantAnswerDraftDTO{
		UnknownExplanations: []contract.ModelUnknownExplanationDTO{
			{ReasonCode: "cashFlowProjectionMissing", Text: "x"},
		},
	}
	if err := provider.ValidateExplanationAlignment(model, sampleMissingDebtAssessment(), factpack.BuildKeySets(sampleDTIFacts())); err == nil {
		t.Fatal("expected unknown coverage mismatch")
	}
}

func TestExplanationAlignmentE01ModelReasonOnlyIgnoresProxyFacts(t *testing.T) {
	model := contract.ModelAssistantAnswerDraftDTO{
		RiskExplanations: []contract.ModelRiskExplanationDTO{
			{ReasonCode: "highDebtPaymentToIncome", Text: "proxy facts only appear in narrative elsewhere"},
		},
	}
	if err := provider.ValidateExplanationAlignment(model, sampleE01PartialAssessment(), factpack.BuildKeySets(sampleDTIFacts())); err != nil {
		t.Fatalf("model alignment should not validate citations: %v", err)
	}
}

func TestExplanationAlignmentNarrativeFactsDoNotRelaxRiskCoverage(t *testing.T) {
	model := contract.ModelAssistantAnswerDraftDTO{
		Title: "t",
		Body:  "本月可用现金与支出均较高。",
		RiskExplanations: []contract.ModelRiskExplanationDTO{
			{ReasonCode: "highDebtPaymentToIncome", Text: "narrative mentions other facts but coverage stays signal-scoped"},
		},
		KeyFacts: []contract.ModelKeyFactDTO{
			{
				Source: "monthlyDebtPayment", Kind: "debt", Label: "还款",
			},
		},
	}
	if err := provider.ValidateExplanationAlignment(model, sampleDTIAssessment(), factpack.BuildKeySets(sampleDTIFacts())); err != nil {
		t.Fatal(err)
	}
}

func TestStandardReferenceKeysNavigationOnly(t *testing.T) {
	facts := sampleDTIFacts()
	keys := factpack.BuildKeySets(facts)
	for _, nav := range []string{"cashFlow30", "cashFlow", "debt", "transactions", "accounts"} {
		if _, ok := keys.RefKeys[nav]; !ok {
			t.Fatalf("missing navigation ref key %s", nav)
		}
	}
	if _, ok := keys.RefKeys["debtPaymentToIncomePercent"]; !ok {
		t.Fatal("present fact must register as reference")
	}
	absent := &contract.MonthlySummaryFactsDTO{
		AvailableCash:            contract.MoneyDTO{Amount: "1000", CurrencyCode: "CNY"},
		MonthlyIncome:            contract.MoneyDTO{Amount: "1000", CurrencyCode: "CNY"},
		MonthlyExpense:           contract.MoneyDTO{Amount: "1000", CurrencyCode: "CNY"},
		MonthlyDebtPayment:       contract.MoneyDTO{Amount: "100", CurrencyCode: "CNY"},
		PrimaryPressure:          "日常",
		EstimatedMonthEndBalance: contract.MoneyDTO{Amount: "900", CurrencyCode: "CNY"},
	}
	absentKeys := factpack.BuildKeySets(absent)
	if _, ok := absentKeys.RefKeys["debtPaymentToIncomePercent"]; ok {
		t.Fatal("absent DTI must not be reference-allowed")
	}
}
