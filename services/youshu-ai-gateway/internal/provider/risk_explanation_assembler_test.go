package provider_test

import (
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/factpack"
	"github.com/youshu/youshu-ai-gateway/internal/prompt"
	"github.com/youshu/youshu-ai-gateway/internal/provider"
)

func TestAssembleRiskExplanationsE01DeterministicCitation(t *testing.T) {
	assessment := sampleE01PartialAssessment()
	model := contract.ModelAssistantAnswerDraftDTO{
		RiskExplanations: []contract.ModelRiskExplanationDTO{{
			ReasonCode: "highDebtPaymentToIncome",
			Text:       "partial debt explanation",
		}},
	}
	assembled, err := provider.AssembleRiskExplanations(model.RiskExplanations, assessment)
	if err != nil {
		t.Fatal(err)
	}
	if len(assembled) != 1 {
		t.Fatalf("assembled=%d", len(assembled))
	}
	if assembled[0].CitedFactKeys[0] != "debtPaymentToIncomePercent" {
		t.Fatalf("cited=%v", assembled[0].CitedFactKeys)
	}
	if err := provider.ValidateAssembledRiskExplanationProvenance(assembled, assessment, factpack.BuildKeySets(sampleDTIFacts())); err != nil {
		t.Fatal(err)
	}
}

func TestAssembleRiskExplanationsMultiSourcePreservesOrder(t *testing.T) {
	assessment := sampleMultiSourceAssessment()
	model := contract.ModelAssistantAnswerDraftDTO{
		RiskExplanations: []contract.ModelRiskExplanationDTO{{
			ReasonCode: "cashFlowBelowSafeBalance",
			Text:       "cash flow",
		}},
	}
	assembled, err := provider.AssembleRiskExplanations(model.RiskExplanations, assessment)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"minimumBalance", "safeBalance"}
	if len(assembled[0].CitedFactKeys) != 2 || assembled[0].CitedFactKeys[0] != want[0] || assembled[0].CitedFactKeys[1] != want[1] {
		t.Fatalf("cited=%v want=%v", assembled[0].CitedFactKeys, want)
	}
}

func TestAssembleRiskExplanationsUnsupportedReasonFails(t *testing.T) {
	assessment := sampleDTIAssessment()
	model := contract.ModelAssistantAnswerDraftDTO{
		RiskExplanations: []contract.ModelRiskExplanationDTO{{
			ReasonCode: "negativeProjectedBalance",
			Text:       "wrong",
		}},
	}
	_, err := provider.AssembleRiskExplanations(model.RiskExplanations, assessment)
	if err == nil {
		t.Fatal("expected unsupported reason failure")
	}
}

func sampleMultiSourceAssessment() *contract.FinancialRiskAssessmentDTO {
	return &contract.FinancialRiskAssessmentDTO{
		OverallLevel:  "warning",
		PolicyVersion: "v1",
		DebtDataState: "knownDebt",
		Signals: []contract.FinancialRiskSignalDTO{{
			Kind: "cashFlow", Level: "warning", ReasonCode: "cashFlowBelowSafeBalance",
			SourceFactKeys: []string{"minimumBalance", "safeBalance"},
		}},
		DataCompleteness: contract.FinancialDataCompletenessDTO{
			Debt: "known", CashFlowProjection: "known", Income: "known", Expense: "known",
		},
	}
}

func TestStrictModelSchemaRejectsRiskExplanationCitedFactKeys(t *testing.T) {
	content := `{
		"title":"t","body":"b","answer":"a","citedFactKeys":[],"confidence":0.8,
		"keyFacts":[],"references":[],
		"riskExplanations":[{"reasonCode":"highDebtPaymentToIncome","text":"x","citedFactKeys":["monthlyDebtPayment"]}],
		"unknownExplanations":[]
	}`
	base, err := prompt.LoadAssistantAnswerModelDraftSchema()
	if err != nil {
		t.Fatal(err)
	}
	assessment := sampleE01PartialAssessment()
	schema, err := prompt.BuildAssistantAnswerSchema(base, factpack.BuildKeySets(sampleDTIFacts()), prompt.BuildExplanationSchemaKeys(assessment))
	if err != nil {
		t.Fatal(err)
	}
	if err := prompt.ValidateDraftJSONWithSchema([]byte(content), schema); err == nil {
		t.Fatal("strict schema should reject model citedFactKeys field")
	}
}
