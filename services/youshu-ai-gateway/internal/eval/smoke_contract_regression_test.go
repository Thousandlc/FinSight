package eval

import (
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/factpack"
	"github.com/youshu/youshu-ai-gateway/internal/provider"
)

func TestSmokeOfflineContractRegression(t *testing.T) {
	t.Run("E01 compliant draft PASS", func(t *testing.T) {
		assessment, err := GoldenBackedAssessment("E01_partial_debt_data")
		if err != nil {
			t.Fatal(err)
		}
		c, err := findCaseByID("E01_partial_debt_data")
		if err != nil {
			t.Fatal(err)
		}
		model := contract.ModelAssistantAnswerDraftDTO{
			RiskExplanations: []contract.ModelRiskExplanationDTO{{
				ReasonCode: "highDebtPaymentToIncome",
				Text:       "explain supplied signal",
			}},
		}
		facts, err := ProductionLikeMonthlySummaryFacts(c)
		if err != nil {
			t.Fatal(err)
		}
		if err := provider.ValidateExplanationAlignment(model, &assessment, factpack.BuildKeySets(facts)); err != nil {
			t.Fatal(err)
		}
		assembled, err := provider.AssembleRiskExplanations(model.RiskExplanations, &assessment)
		if err != nil {
			t.Fatal(err)
		}
		if err := provider.ValidateAssembledRiskExplanationProvenance(assembled, &assessment, factpack.BuildKeySets(facts)); err != nil {
			t.Fatal(err)
		}
		if assembled[0].CitedFactKeys[0] != "debtPaymentToIncomePercent" {
			t.Fatalf("cited=%v", assembled[0].CitedFactKeys)
		}
	})

	t.Run("E01 missing explanation FAIL", func(t *testing.T) {
		assessment, err := GoldenBackedAssessment("E01_partial_debt_data")
		if err != nil {
			t.Fatal(err)
		}
		c, err := findCaseByID("E01_partial_debt_data")
		if err != nil {
			t.Fatal(err)
		}
		model := contract.ModelAssistantAnswerDraftDTO{RiskExplanations: []contract.ModelRiskExplanationDTO{}}
		facts, err := ProductionLikeMonthlySummaryFacts(c)
		if err != nil {
			t.Fatal(err)
		}
		if err := provider.ValidateExplanationAlignment(model, &assessment, factpack.BuildKeySets(facts)); err == nil {
			t.Fatal("expected alignment failure")
		}
	})

	t.Run("E01 deterministic citation PASS", func(t *testing.T) {
		assessment, err := GoldenBackedAssessment("E01_partial_debt_data")
		if err != nil {
			t.Fatal(err)
		}
		c, err := findCaseByID("E01_partial_debt_data")
		if err != nil {
			t.Fatal(err)
		}
		model := contract.ModelAssistantAnswerDraftDTO{
			RiskExplanations: []contract.ModelRiskExplanationDTO{{
				ReasonCode: "highDebtPaymentToIncome",
				Text:       "model no longer chooses citations",
			}},
		}
		facts, err := ProductionLikeMonthlySummaryFacts(c)
		if err != nil {
			t.Fatal(err)
		}
		if err := provider.ValidateExplanationAlignment(model, &assessment, factpack.BuildKeySets(facts)); err != nil {
			t.Fatal(err)
		}
		assembled, err := provider.AssembleRiskExplanations(model.RiskExplanations, &assessment)
		if err != nil {
			t.Fatal(err)
		}
		if len(assembled[0].CitedFactKeys) != 1 || assembled[0].CitedFactKeys[0] != "debtPaymentToIncomePercent" {
			t.Fatalf("assembled citations=%v", assembled[0].CitedFactKeys)
		}
	})

	t.Run("A01 safe empty PASS", func(t *testing.T) {
		assessment, err := GoldenBackedAssessment("A01_healthy_cashflow")
		if err != nil {
			t.Fatal(err)
		}
		c, err := findCaseByID("A01_healthy_cashflow")
		if err != nil {
			t.Fatal(err)
		}
		model := contract.ModelAssistantAnswerDraftDTO{
			RiskExplanations:    []contract.ModelRiskExplanationDTO{},
			UnknownExplanations: []contract.ModelUnknownExplanationDTO{},
		}
		if err := provider.ValidateExplanationAlignment(model, &assessment, factpack.BuildKeySets(c.Envelope.MonthlySummaryFacts)); err != nil {
			t.Fatal(err)
		}
	})

	t.Run("C01 safe narrative PASS", func(t *testing.T) {
		c, err := findCaseByID("C01_no_debt")
		if err != nil {
			t.Fatal(err)
		}
		narr := AnalyzeNarrativeSemantics(c, contract.AssistantAnswerDraftDTO{
			Title: "t", Body: "当前确认的债务清单中没有未结清债务。", Answer: "a",
		})
		if narr.KnownNoDebtContradictionCount != 0 {
			t.Fatalf("expected PASS, got %+v", narr)
		}
	})

	t.Run("C01 debt-pressure contradiction FAIL", func(t *testing.T) {
		c, err := findCaseByID("C01_no_debt")
		if err != nil {
			t.Fatal(err)
		}
		narr := AnalyzeNarrativeSemantics(c, contract.AssistantAnswerDraftDTO{
			Title: "t", Body: "债务压力", Answer: "a",
		})
		if narr.KnownNoDebtContradictionCount != 1 {
			t.Fatalf("expected FAIL, got %+v", narr)
		}
	})

	t.Run("E05 safe+missing PASS", func(t *testing.T) {
		assessment, err := GoldenBackedAssessment("E05_missing_debt_data")
		if err != nil {
			t.Fatal(err)
		}
		model := contract.ModelAssistantAnswerDraftDTO{
			UnknownExplanations: []contract.ModelUnknownExplanationDTO{
				{ReasonCode: "debtDataMissing", Text: "debt inventory missing"},
			},
		}
		c, err := findCaseByID("E05_missing_debt_data")
		if err != nil {
			t.Fatal(err)
		}
		if err := provider.ValidateExplanationAlignment(model, &assessment, factpack.BuildKeySets(c.Envelope.MonthlySummaryFacts)); err != nil {
			t.Fatal(err)
		}
	})

	t.Run("C03 DTI explanation PASS", func(t *testing.T) {
		assessment, err := GoldenBackedAssessment("C03_high_monthly_payment")
		if err != nil {
			t.Fatal(err)
		}
		c, err := findCaseByID("C03_high_monthly_payment")
		if err != nil {
			t.Fatal(err)
		}
		model := contract.ModelAssistantAnswerDraftDTO{
			RiskExplanations: []contract.ModelRiskExplanationDTO{{
				ReasonCode: "highDebtPaymentToIncome",
				Text:       "DTI warning",
			}},
		}
		if err := provider.ValidateExplanationAlignment(model, &assessment, factpack.BuildKeySets(c.Envelope.MonthlySummaryFacts)); err != nil {
			t.Fatal(err)
		}
	})

	t.Run("B04 risk explanation PASS", func(t *testing.T) {
		assessment, err := GoldenBackedAssessment("B04_short_term_negative_balance")
		if err != nil {
			t.Fatal(err)
		}
		c, err := findCaseByID("B04_short_term_negative_balance")
		if err != nil {
			t.Fatal(err)
		}
		model := contract.ModelAssistantAnswerDraftDTO{
			RiskExplanations: []contract.ModelRiskExplanationDTO{{
				ReasonCode: "negativeProjectedBalance",
				Text:       "balance gap",
			}},
		}
		if err := provider.ValidateExplanationAlignment(model, &assessment, factpack.BuildKeySets(c.Envelope.MonthlySummaryFacts)); err != nil {
			t.Fatal(err)
		}
	})
}
