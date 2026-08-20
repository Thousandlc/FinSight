package eval

import (
	"strings"
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/factpack"
	"github.com/youshu/youshu-ai-gateway/internal/prompt"
	"github.com/youshu/youshu-ai-gateway/internal/provider"
	"github.com/youshu/youshu-ai-gateway/internal/smoke"
)

func loadModelBaseSchema(t *testing.T) []byte {
	t.Helper()
	raw, err := prompt.LoadAssistantAnswerModelDraftSchema()
	if err != nil {
		t.Fatal(err)
	}
	return raw
}

func modelDraftSourceOnly(source string) []byte {
	return []byte(`{
		"title": "本月财务摘要",
		"body": "body",
		"answer": "answer",
		"citedFactKeys": ["availableCash"],
		"confidence": 0.8,
		"keyFacts": [{
			"label": "可用资金",
			"kind": "balance",
			"source": "` + source + `"
		}],
		"references": [{"key": "availableCash"}],
		"riskExplanations": [],
		"unknownExplanations": []
	}`)
}

func modelDraftWithLegacyValue(source string) []byte {
	return []byte(`{
		"title": "本月财务摘要",
		"body": "body",
		"answer": "answer",
		"citedFactKeys": ["availableCash"],
		"confidence": 0.8,
		"keyFacts": [{
			"label": "可用资金",
			"kind": "balance",
			"source": "` + source + `",
			"value": {"type":"money","amount":10000,"currencyCode":"CNY","textValue":null,"percentValue":null,"dateValue":null}
		}],
		"references": [{"key": "availableCash"}],
		"riskExplanations": [],
		"unknownExplanations": []
	}`)
}

func c2bCaseFacts(caseID string) *contract.MonthlySummaryFactsDTO {
	c, err := findCaseByID(caseID)
	if err != nil {
		panic(err)
	}
	return c.Envelope.MonthlySummaryFacts
}

func c2bCaseAssessment(caseID string) *contract.FinancialRiskAssessmentDTO {
	c, err := findCaseByID(caseID)
	if err != nil {
		panic(err)
	}
	return c.Envelope.FinancialRiskAssessment
}

func boundSchemaForCase(t *testing.T, caseID string) []byte {
	t.Helper()
	facts := c2bCaseFacts(caseID)
	assessment := c2bCaseAssessment(caseID)
	schema, err := prompt.BuildAssistantAnswerSchema(
		loadModelBaseSchema(t),
		factpack.BuildKeySetsForRequest(facts, assessment),
		prompt.BuildExplanationSchemaKeys(assessment),
	)
	if err != nil {
		t.Fatal(err)
	}
	return schema
}

func TestC2BModelSchemaRejectsLegacyValueField(t *testing.T) {
	schema := boundSchemaForCase(t, "C03_high_monthly_payment")
	if err := prompt.ValidateDraftJSONWithSchema(modelDraftWithLegacyValue("availableCash"), schema); err == nil {
		t.Fatal("legacy keyFact value must fail strict schema")
	}
}

func TestC2BModelSchemaSourceOnlyPasses(t *testing.T) {
	schema := boundSchemaForCase(t, "C03_high_monthly_payment")
	if err := prompt.ValidateDraftJSONWithSchema(modelDraftSourceOnly("availableCash"), schema); err != nil {
		t.Fatal(err)
	}
}

func TestC2BC01MonthlyDebtPaymentNotInKeyFactEnum(t *testing.T) {
	schema := boundSchemaForCase(t, "C01_no_debt")
	if err := prompt.ValidateDraftJSONWithSchema(modelDraftSourceOnly("monthlyDebtPayment"), schema); err == nil {
		t.Fatal("C01 must forbid monthlyDebtPayment keyFact source")
	}
}

func TestC2BC03MonthlyDebtPaymentInKeyFactEnum(t *testing.T) {
	schema := boundSchemaForCase(t, "C03_high_monthly_payment")
	if err := prompt.ValidateDraftJSONWithSchema(modelDraftSourceOnly("monthlyDebtPayment"), schema); err != nil {
		t.Fatal(err)
	}
}

func TestC2BE01DTIInKeyFactEnum(t *testing.T) {
	schema := boundSchemaForCase(t, "E01_partial_debt_data")
	if err := prompt.ValidateDraftJSONWithSchema(modelDraftSourceOnly("debtPaymentToIncomePercent"), schema); err != nil {
		t.Fatal(err)
	}
}

func TestC2BE05DTINotInKeyFactEnum(t *testing.T) {
	schema := boundSchemaForCase(t, "E05_missing_debt_data")
	if err := prompt.ValidateDraftJSONWithSchema(modelDraftSourceOnly("debtPaymentToIncomePercent"), schema); err == nil {
		t.Fatal("E05 must not allow DTI keyFact source")
	}
}

func TestC2BC04DebtPressureInKeyFactEnum(t *testing.T) {
	schema := boundSchemaForCase(t, "C04_multiple_debts")
	if err := prompt.ValidateDraftJSONWithSchema(modelDraftSourceOnly("debtPressureLevel"), schema); err != nil {
		t.Fatal(err)
	}
}

func TestC2BMaterializeDTIPercentFromSourceOnlyModel(t *testing.T) {
	facts := c2bCaseFacts("E01_partial_debt_data")
	assessment := c2bCaseAssessment("E01_partial_debt_data")
	model := contract.ModelAssistantAnswerDraftDTO{
		KeyFacts: []contract.ModelKeyFactDTO{{
			Label:  "DTI",
			Kind:   "debt",
			Source: "debtPaymentToIncomePercent",
		}},
	}
	draft, err := provider.MapModelDraftToGateway(model, assessment, facts)
	if err != nil {
		t.Fatal(err)
	}
	if len(draft.KeyFacts) != 1 || draft.KeyFacts[0].Value.Type != "percent" {
		t.Fatalf("draft=%+v", draft.KeyFacts)
	}
	if draft.KeyFacts[0].Value.PercentValue == nil || *draft.KeyFacts[0].Value.PercentValue != 25 {
		t.Fatalf("percent=%v", draft.KeyFacts[0].Value.PercentValue)
	}
}

func TestC2BC01ProductionKeyFactSelectionFails(t *testing.T) {
	facts := c2bCaseFacts("C01_no_debt")
	assessment := c2bCaseAssessment("C01_no_debt")
	model := contract.ModelAssistantAnswerDraftDTO{
		KeyFacts: []contract.ModelKeyFactDTO{{
			Label:  "还款",
			Kind:   "debt",
			Source: "monthlyDebtPayment",
		}},
	}
	keySets := factpack.BuildKeySetsForRequest(facts, assessment)
	if err := provider.ValidateKeyFactSelection(model, keySets); err == nil {
		t.Fatal("C01 monthlyDebtPayment keyFact must fail production selection validator")
	}
}

func TestC2BC01ValidKeyFactsPassProductionSelection(t *testing.T) {
	facts := c2bCaseFacts("C01_no_debt")
	assessment := c2bCaseAssessment("C01_no_debt")
	model := contract.ModelAssistantAnswerDraftDTO{
		KeyFacts: []contract.ModelKeyFactDTO{
			{Label: "收入", Kind: "income", Source: "monthlyIncome"},
			{Label: "支出", Kind: "expense", Source: "monthlyExpense"},
		},
	}
	keySets := factpack.BuildKeySetsForRequest(facts, assessment)
	if err := provider.ValidateKeyFactSelection(model, keySets); err != nil {
		t.Fatal(err)
	}
	draft, err := provider.MapModelDraftToGateway(model, assessment, facts)
	if err != nil {
		t.Fatal(err)
	}
	diag := smoke.DiagnoseFactsWithKeySets(draft, facts, keySets)
	if !diag.Passed {
		t.Fatalf("expected pass, rules=%s", diag.FailureRulesSummary())
	}
}

func TestC2BFrozenC04LegacyMoneyDTINotRepresentable(t *testing.T) {
	schema := boundSchemaForCase(t, "C04_multiple_debts")
	if err := prompt.ValidateDraftJSONWithSchema(modelDraftWithLegacyValue("debtPaymentToIncomePercent"), schema); err == nil {
		t.Fatal("legacy DTI money row must fail schema")
	}
}

func TestC2BAnalyzeContentC01ForbiddenKeyFactFails(t *testing.T) {
	facts := c2bCaseFacts("C01_no_debt")
	assessment := c2bCaseAssessment("C01_no_debt")
	model := contract.ModelAssistantAnswerDraftDTO{
		Title: "t", Body: "b", Answer: "a", Confidence: 0.8,
		KeyFacts: []contract.ModelKeyFactDTO{{Label: "x", Kind: "debt", Source: "monthlyDebtPayment"}},
	}
	keySets := factpack.BuildKeySetsForRequest(facts, assessment)
	if err := provider.ValidateKeyFactSelection(model, keySets); err == nil {
		t.Fatal("expected selection failure")
	}
}

func TestC2BSchemaMetadataApplicationMaterialized(t *testing.T) {
	schema := boundSchemaForCase(t, "C01_no_debt")
	meta, err := prompt.DescribeKeyFactValueSchema(schema)
	if err != nil {
		t.Fatal(err)
	}
	if meta.SchemaMode != prompt.KeyFactValueSchemaModeApplicationMaterialized {
		t.Fatalf("mode=%q", meta.SchemaMode)
	}
	if !strings.Contains(meta.Summary(), "applicationMaterialized") {
		t.Fatalf("summary=%s", meta.Summary())
	}
}

func TestC2BTopLevelCitedFactKeysStillAllowMonthlyDebtPaymentForC01(t *testing.T) {
	facts := c2bCaseFacts("C01_no_debt")
	assessment := c2bCaseAssessment("C01_no_debt")
	schema := boundSchemaForCase(t, "C01_no_debt")
	raw := []byte(strings.Replace(string(modelDraftSourceOnly("monthlyIncome")), `"citedFactKeys": ["availableCash"]`, `"citedFactKeys": ["monthlyDebtPayment"]`, 1))
	if err := prompt.ValidateDraftJSONWithSchema(raw, schema); err != nil {
		t.Fatal("citedFactKeys should still allow monthlyDebtPayment for C01")
	}
	_ = assessment
	_ = facts
}

func TestC2BContractGapClosed(t *testing.T) {
	facts := c2bCaseFacts("C01_no_debt")
	assessment := c2bCaseAssessment("C01_no_debt")
	keySets := factpack.BuildKeySetsForRequest(facts, assessment)
	draft, err := provider.MapModelDraftToGateway(contract.ModelAssistantAnswerDraftDTO{
		KeyFacts: []contract.ModelKeyFactDTO{{Label: "还款", Kind: "debt", Source: "monthlyDebtPayment"}},
	}, assessment, facts)
	if err == nil {
		diag := smoke.DiagnoseFactsWithKeySets(draft, facts, keySets)
		if diag.Passed {
			t.Fatal("C01 forbidden keyFact must not pass production fact validation")
		}
	}
	if err := provider.ValidateKeyFactSelection(contract.ModelAssistantAnswerDraftDTO{
		KeyFacts: []contract.ModelKeyFactDTO{{Label: "还款", Kind: "debt", Source: "monthlyDebtPayment"}},
	}, keySets); err == nil {
		t.Fatal("selection validator must block before materialization")
	}
}
