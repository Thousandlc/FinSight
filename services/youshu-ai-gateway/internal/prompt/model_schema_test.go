package prompt_test

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/factpack"
	"github.com/youshu/youshu-ai-gateway/internal/handler"
	"github.com/youshu/youshu-ai-gateway/internal/prompt"
	"github.com/youshu/youshu-ai-gateway/internal/provider"
)

func loadModelBaseSchema(t *testing.T) json.RawMessage {
	t.Helper()
	raw, err := prompt.LoadAssistantAnswerModelDraftSchema()
	if err != nil {
		t.Fatal(err)
	}
	return raw
}

func modelDraftJSON(source string) []byte {
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

func modelDraftJSONWithLegacyValue(source string) []byte {
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

func modelSchemaSampleFacts() *contract.MonthlySummaryFactsDTO {
	return &contract.MonthlySummaryFactsDTO{
		AvailableCash:            contract.MoneyDTO{Amount: "10000", CurrencyCode: "CNY"},
		MonthlyIncome:            contract.MoneyDTO{Amount: "12000", CurrencyCode: "CNY"},
		MonthlyExpense:           contract.MoneyDTO{Amount: "6000", CurrencyCode: "CNY"},
		MonthlyDebtPayment:       contract.MoneyDTO{Amount: "2000", CurrencyCode: "CNY"},
		PrimaryPressure:          "日常支出",
		EstimatedMonthEndBalance: contract.MoneyDTO{Amount: "8000", CurrencyCode: "CNY"},
	}
}

func TestModelSchemaSourceOnlyPasses(t *testing.T) {
	if err := prompt.ValidateDraftJSONWithSchema(modelDraftJSON("availableCash"), loadModelBaseSchema(t)); err != nil {
		t.Fatal(err)
	}
}

func TestModelSchemaLegacyValueFieldFails(t *testing.T) {
	if err := prompt.ValidateDraftJSONWithSchema(modelDraftJSONWithLegacyValue("availableCash"), loadModelBaseSchema(t)); err == nil {
		t.Fatal("legacy value field must fail strict schema")
	}
}

func TestModelSchemaUnexpectedFieldFails(t *testing.T) {
	raw := modelDraftJSONWithLegacyValue("availableCash")
	if err := prompt.ValidateDraftJSONWithSchema(raw, loadModelBaseSchema(t)); err == nil {
		t.Fatal("unexpected value field must fail")
	}
}

func TestModelSchemaHasNoConditionalKeywords(t *testing.T) {
	raw, err := prompt.LoadAssistantAnswerModelDraftSchema()
	if err != nil {
		t.Fatal(err)
	}
	text := string(raw)
	for _, forbidden := range []string{`"allOf"`, `"if"`, `"then"`} {
		if strings.Contains(text, forbidden) {
			t.Fatalf("model schema must not contain %s", forbidden)
		}
	}
}

func TestModelBoundSchemaUsesAllowedKeyFactKeys(t *testing.T) {
	facts := modelSchemaSampleFacts()
	assessment := &contract.FinancialRiskAssessmentDTO{DebtDataState: "knownNoDebt"}
	bound, err := prompt.BuildAssistantAnswerSchema(loadModelBaseSchema(t), factpack.BuildKeySetsForRequest(facts, assessment), prompt.ExplanationSchemaKeys{})
	if err != nil {
		t.Fatal(err)
	}
	var doc map[string]any
	if err := json.Unmarshal(bound, &doc); err != nil {
		t.Fatal(err)
	}
	sourceEnum := doc["$defs"].(map[string]any)["keyFact"].(map[string]any)["properties"].(map[string]any)["source"].(map[string]any)["enum"].([]any)
	for _, item := range sourceEnum {
		if item == "monthlyDebtPayment" {
			t.Fatal("knownNoDebt schema must exclude monthlyDebtPayment from keyFact source enum")
		}
	}
}

func TestModelDraftDecodeAndMapMaterializesMoney(t *testing.T) {
	facts := modelSchemaSampleFacts()
	var model contract.ModelAssistantAnswerDraftDTO
	raw := modelDraftJSON("availableCash")
	if err := json.Unmarshal(raw, &model); err != nil {
		t.Fatal(err)
	}
	if err := provider.ValidateModelDraft(model); err != nil {
		t.Fatal(err)
	}
	draft, err := provider.MapModelDraftToGateway(model, &contract.FinancialRiskAssessmentDTO{OverallLevel: "safe", DebtDataState: "knownDebt"}, facts)
	if err != nil {
		t.Fatal(err)
	}
	if draft.KeyFacts[0].Value.Amount == nil {
		t.Fatal("expected materialized money value")
	}
}

func TestAnalyzeContentModelSourceOnlyMapsToGateway(t *testing.T) {
	facts := modelSchemaSampleFacts()
	_, diag := provider.AnalyzeContent(string(modelDraftJSON("availableCash")), &contract.FinancialRiskAssessmentDTO{OverallLevel: "safe", DebtDataState: "knownDebt"}, facts)
	if diag.DraftDTODecode != provider.StagePass {
		t.Fatalf("decode=%s kind=%s path=%s", diag.DraftDTODecode, diag.DTODecodeErrorKind, diag.DTODecodeErrorPath)
	}
}

func TestAnalyzeContentGatewayValidateDraftStillApplies(t *testing.T) {
	facts := modelSchemaSampleFacts()
	draft, diag := provider.AnalyzeContent(string(modelDraftJSON("availableCash")), &contract.FinancialRiskAssessmentDTO{OverallLevel: "safe", DebtDataState: "knownDebt"}, facts)
	if diag.DraftDTODecode != provider.StagePass {
		t.Fatal(diag.DraftDTODecode)
	}
	if err := handler.ValidateDraft(draft); err != nil {
		t.Fatal(err)
	}
}

func TestDescribeModelKeyFactValueSchemaMetadata(t *testing.T) {
	meta, err := prompt.DescribeKeyFactValueSchema(loadModelBaseSchema(t))
	if err != nil {
		t.Fatal(err)
	}
	if meta.SchemaMode != prompt.KeyFactValueSchemaModeApplicationMaterialized {
		t.Fatalf("mode=%q", meta.SchemaMode)
	}
	summary := meta.Summary()
	if !strings.Contains(summary, "applicationMaterialized") {
		t.Fatalf("summary=%s", summary)
	}
}
