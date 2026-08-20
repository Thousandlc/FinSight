package prompt_test

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/factpack"
	"github.com/youshu/youshu-ai-gateway/internal/prompt"
	"github.com/youshu/youshu-ai-gateway/internal/smoke"
)

func loadBaseSchema(t *testing.T) json.RawMessage {
	t.Helper()
	raw, err := prompt.LoadAssistantAnswerModelDraftSchema()
	if err != nil {
		t.Fatal(err)
	}
	return raw
}

func boundSchema(t *testing.T, facts *contract.MonthlySummaryFactsDTO) json.RawMessage {
	t.Helper()
	schema, err := prompt.BuildAssistantAnswerSchema(loadBaseSchema(t), factpack.BuildKeySets(facts), prompt.ExplanationSchemaKeys{})
	if err != nil {
		t.Fatal(err)
	}
	return schema
}

func sampleFacts() *contract.MonthlySummaryFactsDTO {
	safe := contract.MoneyDTO{Amount: "3000", CurrencyCode: "CNY"}
	minBal := contract.MoneyDTO{Amount: "4500", CurrencyCode: "CNY"}
	return &contract.MonthlySummaryFactsDTO{
		AvailableCash:            contract.MoneyDTO{Amount: "10000", CurrencyCode: "CNY"},
		MonthlyIncome:            contract.MoneyDTO{Amount: "12000", CurrencyCode: "CNY"},
		MonthlyExpense:           contract.MoneyDTO{Amount: "6000", CurrencyCode: "CNY"},
		MonthlyDebtPayment:       contract.MoneyDTO{Amount: "2000", CurrencyCode: "CNY"},
		PrimaryPressure:          "日常支出",
		EstimatedMonthEndBalance: contract.MoneyDTO{Amount: "8000", CurrencyCode: "CNY"},
		SafeBalance:              &safe,
		MinimumBalance:           &minBal,
	}
}

func draftWithSource(source string) []byte {
	return []byte(`{
		"title": "本月财务摘要",
		"body": "本月可用资金约 ¥10000。",
		"answer": "本月可用资金约 ¥10000。",
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

func TestDynamicSchemaSourceAvailableCashPasses(t *testing.T) {
	schema := boundSchema(t, sampleFacts())
	if err := prompt.ValidateDraftJSONWithSchema(draftWithSource("availableCash"), schema); err != nil {
		t.Fatal(err)
	}
}

func TestDynamicSchemaSourceAccountFails(t *testing.T) {
	schema := boundSchema(t, sampleFacts())
	if err := prompt.ValidateDraftJSONWithSchema(draftWithSource("Account"), schema); err == nil {
		t.Fatal("source=Account must fail bound schema")
	}
}

func TestDynamicSchemaSourceTransactionFails(t *testing.T) {
	schema := boundSchema(t, sampleFacts())
	if err := prompt.ValidateDraftJSONWithSchema(draftWithSource("Transaction"), schema); err == nil {
		t.Fatal("source=Transaction must fail bound schema")
	}
}

func TestDynamicSchemaCitedFactKeyLegalPasses(t *testing.T) {
	schema := boundSchema(t, sampleFacts())
	raw := []byte(strings.Replace(string(draftWithSource("availableCash")), `"citedFactKeys": ["availableCash"]`, `"citedFactKeys": ["primaryPressure"]`, 1))
	if err := prompt.ValidateDraftJSONWithSchema(raw, schema); err != nil {
		t.Fatal(err)
	}
}

func TestDynamicSchemaCitedFactKeyContextOnlyFails(t *testing.T) {
	schema := boundSchema(t, sampleFacts())
	raw := []byte(strings.Replace(string(draftWithSource("availableCash")), `"citedFactKeys": ["availableCash"]`, `"citedFactKeys": ["cashFlow30"]`, 1))
	if err := prompt.ValidateDraftJSONWithSchema(raw, schema); err == nil {
		t.Fatal("citedFactKeys=cashFlow30 must fail when not in allowedFactKeys")
	}
}

func TestDynamicSchemaReferenceKeyLegalPasses(t *testing.T) {
	schema := boundSchema(t, sampleFacts())
	raw := []byte(strings.Replace(string(draftWithSource("availableCash")), `"references": [{"key": "availableCash"}]`, `"references": [{"key": "cashFlow30"}]`, 1))
	if err := prompt.ValidateDraftJSONWithSchema(raw, schema); err != nil {
		t.Fatal(err)
	}
}

func TestDynamicSchemaReferenceKeyIllegalFails(t *testing.T) {
	schema := boundSchema(t, sampleFacts())
	raw := []byte(strings.Replace(string(draftWithSource("availableCash")), `"references": [{"key": "availableCash"}]`, `"references": [{"key": "Account"}]`, 1))
	if err := prompt.ValidateDraftJSONWithSchema(raw, schema); err == nil {
		t.Fatal("reference.key=Account must fail bound schema")
	}
}

func TestDynamicSchemaReferenceKeyFactBackedPassesWhenPresent(t *testing.T) {
	schema := boundSchema(t, sampleFacts())
	raw := []byte(strings.Replace(string(draftWithSource("availableCash")), `"references": [{"key": "availableCash"}]`, `"references": [{"key": "availableCash"}]`, 1))
	if err := prompt.ValidateDraftJSONWithSchema(raw, schema); err != nil {
		t.Fatal(err)
	}
}

func TestDynamicSchemaReferenceKeyFactBackedAbsentFails(t *testing.T) {
	facts := &contract.MonthlySummaryFactsDTO{
		AvailableCash:            contract.MoneyDTO{Amount: "2000", CurrencyCode: "CNY"},
		MonthlyIncome:            contract.MoneyDTO{Amount: "5000", CurrencyCode: "CNY"},
		MonthlyExpense:           contract.MoneyDTO{Amount: "4500", CurrencyCode: "CNY"},
		MonthlyDebtPayment:       contract.MoneyDTO{Amount: "800", CurrencyCode: "CNY"},
		PrimaryPressure:          "日常支出",
		EstimatedMonthEndBalance: contract.MoneyDTO{Amount: "1500", CurrencyCode: "CNY"},
	}
	schema, err := prompt.BuildAssistantAnswerSchema(loadBaseSchema(t), factpack.BuildKeySets(facts), prompt.ExplanationSchemaKeys{})
	if err != nil {
		t.Fatal(err)
	}
	raw := []byte(`{
		"title": "本月财务摘要",
		"body": "body",
		"answer": "answer",
		"citedFactKeys": ["availableCash"],
		"confidence": 0.8,
		"keyFacts": [],
		"references": [{"key": "debtPaymentToIncomePercent"}],
		"riskExplanations": [],
		"unknownExplanations": []
	}`)
	if err := prompt.ValidateDraftJSONWithSchema(raw, schema); err == nil {
		t.Fatal("reference.key=debtPaymentToIncomePercent must fail when fact absent")
	}
}

func TestDynamicSchemaReferenceKeyFactBackedPresentPasses(t *testing.T) {
	pct := "40"
	facts := &contract.MonthlySummaryFactsDTO{
		AvailableCash:              contract.MoneyDTO{Amount: "5000", CurrencyCode: "CNY"},
		MonthlyIncome:              contract.MoneyDTO{Amount: "10000", CurrencyCode: "CNY"},
		MonthlyExpense:             contract.MoneyDTO{Amount: "5000", CurrencyCode: "CNY"},
		MonthlyDebtPayment:         contract.MoneyDTO{Amount: "4000", CurrencyCode: "CNY"},
		DebtPaymentToIncomePercent: &pct,
		PrimaryPressure:            "债务还款",
		EstimatedMonthEndBalance:   contract.MoneyDTO{Amount: "3000", CurrencyCode: "CNY"},
	}
	schema, err := prompt.BuildAssistantAnswerSchema(loadBaseSchema(t), factpack.BuildKeySets(facts), prompt.ExplanationSchemaKeys{})
	if err != nil {
		t.Fatal(err)
	}
	raw := []byte(`{
		"title": "本月财务摘要",
		"body": "body",
		"answer": "answer",
		"citedFactKeys": ["availableCash"],
		"confidence": 0.8,
		"keyFacts": [],
		"references": [{"key": "debtPaymentToIncomePercent"}],
		"riskExplanations": [],
		"unknownExplanations": []
	}`)
	if err := prompt.ValidateDraftJSONWithSchema(raw, schema); err != nil {
		t.Fatal(err)
	}
}

func TestDynamicSchemaEnumDiffersBySyntheticCase(t *testing.T) {
	caseC := smoke.AllCases()[2].Envelope.MonthlySummaryFacts
	caseD := smoke.AllCases()[3].Envelope.MonthlySummaryFacts
	schemaC, err := prompt.BuildAssistantAnswerSchema(loadBaseSchema(t), factpack.BuildKeySets(caseC), prompt.ExplanationSchemaKeys{})
	if err != nil {
		t.Fatal(err)
	}
	schemaD, err := prompt.BuildAssistantAnswerSchema(loadBaseSchema(t), factpack.BuildKeySets(caseD), prompt.ExplanationSchemaKeys{})
	if err != nil {
		t.Fatal(err)
	}
	if string(schemaC) == string(schemaD) {
		t.Fatal("different synthetic cases must produce different bound schemas")
	}
}

func TestDynamicSchemaKeysMatchValidateFactsAllowedSet(t *testing.T) {
	facts := sampleFacts()
	keys := factpack.BuildKeySets(facts)
	schema := boundSchema(t, facts)

	var doc map[string]any
	if err := json.Unmarshal(schema, &doc); err != nil {
		t.Fatal(err)
	}
	defs := doc["$defs"].(map[string]any)
	keyFact := defs["keyFact"].(map[string]any)
	sourceEnum := keyFact["properties"].(map[string]any)["source"].(map[string]any)["enum"].([]any)

	allowed := smokeAllowedFactKeySet(facts)
	if len(sourceEnum) != len(allowed) {
		t.Fatalf("source enum size=%d allowed=%d", len(sourceEnum), len(allowed))
	}
	for _, item := range sourceEnum {
		key, _ := item.(string)
		if !allowed[key] {
			t.Fatalf("schema source enum contains unexpected key %q", key)
		}
	}
	for key := range allowed {
		found := false
		for _, item := range sourceEnum {
			if item.(string) == key {
				found = true
				break
			}
		}
		if !found {
			t.Fatalf("schema source enum missing allowed key %q", key)
		}
	}
	_ = keys
}

func TestDynamicSchemaEmptyAllowedFactKeysForcesEmptyArrays(t *testing.T) {
	schema, err := prompt.BuildAssistantAnswerSchema(loadBaseSchema(t), factpack.KeySets{}, prompt.ExplanationSchemaKeys{})
	if err != nil {
		t.Fatal(err)
	}
	var doc map[string]any
	if err := json.Unmarshal(schema, &doc); err != nil {
		t.Fatal(err)
	}
	props := doc["properties"].(map[string]any)
	for _, field := range []string{"citedFactKeys", "keyFacts"} {
		node := props[field].(map[string]any)
		if node["maxItems"].(float64) != 0 {
			t.Fatalf("%s must force maxItems=0 when allowedFactKeys empty", field)
		}
	}
}

func smokeAllowedFactKeySet(facts *contract.MonthlySummaryFactsDTO) map[string]bool {
	amounts, textFacts, _ := smoke.AllowedKeys(facts)
	out := make(map[string]bool)
	for k := range amounts {
		out[k] = true
	}
	for k := range textFacts {
		out[k] = true
	}
	return out
}

func TestDynamicSchemaRequestContainsSourceEnum(t *testing.T) {
	schema := boundSchema(t, sampleFacts())
	var doc map[string]any
	if err := json.Unmarshal(schema, &doc); err != nil {
		t.Fatal(err)
	}
	source := doc["$defs"].(map[string]any)["keyFact"].(map[string]any)["properties"].(map[string]any)["source"].(map[string]any)
	enum, ok := source["enum"].([]any)
	if !ok || len(enum) == 0 {
		t.Fatal("bound schema must include source enum")
	}
	found := false
	for _, item := range enum {
		if item.(string) == "availableCash" {
			found = true
			break
		}
	}
	if !found {
		t.Fatal("source enum must include availableCash")
	}
}

func TestDynamicSchemaDebtPressureLevelAbsentFromFactEnums(t *testing.T) {
	schema := boundSchema(t, sampleFacts())
	raw := schemaString(t, schema)
	if strings.Contains(raw, `"debtPressureLevel"`) {
		t.Fatal("debtPressureLevel must not appear in bound schema when fact absent")
	}
}

func TestDynamicSchemaDebtPressureLevelPresentInFactEnums(t *testing.T) {
	level := "high"
	facts := sampleFacts()
	facts.DebtPressureLevel = &level
	schema := boundSchema(t, facts)
	raw := schemaString(t, schema)
	if !strings.Contains(raw, `"debtPressureLevel"`) {
		t.Fatal("debtPressureLevel must appear in bound schema when fact present")
	}
}

func TestDynamicSchemaDebtPressureLevelReferenceAbsentFails(t *testing.T) {
	schema := boundSchema(t, sampleFacts())
	raw := []byte(strings.Replace(string(draftWithSource("availableCash")), `"references": [{"key": "availableCash"}]`, `"references": [{"key": "debtPressureLevel"}]`, 1))
	if err := prompt.ValidateDraftJSONWithSchema(raw, schema); err == nil {
		t.Fatal("reference.key=debtPressureLevel must fail when fact absent")
	}
}

func TestDynamicSchemaDebtPressureLevelReferencePresentPasses(t *testing.T) {
	level := "high"
	facts := sampleFacts()
	facts.DebtPressureLevel = &level
	schema := boundSchema(t, facts)
	raw := []byte(strings.Replace(string(draftWithSource("availableCash")), `"references": [{"key": "availableCash"}]`, `"references": [{"key": "debtPressureLevel"}]`, 1))
	if err := prompt.ValidateDraftJSONWithSchema(raw, schema); err != nil {
		t.Fatal(err)
	}
}

func schemaString(t *testing.T, schema json.RawMessage) string {
	t.Helper()
	return string(schema)
}
