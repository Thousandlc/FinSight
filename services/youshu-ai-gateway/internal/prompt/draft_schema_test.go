package prompt_test

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/prompt"
)

func legalDraftJSON() []byte {
	return []byte(`{
		"title": "本月财务摘要",
		"body": "本月可用资金约 ¥10000。",
		"answer": "本月可用资金约 ¥10000。",
		"citedFactKeys": ["availableCash"],
		"unknowns": [],
		"confidence": 0.8,
		"keyFacts": [{
			"label": "可用资金",
			"kind": "balance",
			"source": "availableCash",
			"value": {"type": "money", "amount": 10000, "currencyCode": "CNY"}
		}],
		"warnings": [{"title": "提示", "message": "关注现金流", "severity": "warning", "source": "availableCash"}],
		"actions": [{"title": "查看未来现金流", "destination": "cashFlow"}],
		"references": [{"key": "availableCash"}]
	}`)
}

func TestSchemaLegalDraftPasses(t *testing.T) {
	if err := prompt.ValidateDraftJSON(legalDraftJSON()); err != nil {
		t.Fatal(err)
	}
}

func TestSchemaAmountNumberPasses(t *testing.T) {
	if err := prompt.ValidateDraftJSON(legalDraftJSON()); err != nil {
		t.Fatal(err)
	}
}

func TestSchemaAmountStringFails(t *testing.T) {
	raw := []byte(strings.Replace(string(legalDraftJSON()), `"amount": 10000`, `"amount": "10000"`, 1))
	if err := prompt.ValidateDraftJSON(raw); err == nil {
		t.Fatal("string amount must fail schema")
	}
}

func TestSchemaReferencesObjectArrayPasses(t *testing.T) {
	if err := prompt.ValidateDraftJSON(legalDraftJSON()); err != nil {
		t.Fatal(err)
	}
}

func TestSchemaReferencesStringArrayFails(t *testing.T) {
	raw := []byte(strings.Replace(string(legalDraftJSON()), `"references": [{"key": "availableCash"}]`, `"references": ["availableCash"]`, 1))
	if err := prompt.ValidateDraftJSON(raw); err == nil {
		t.Fatal("string array references must fail")
	}
}

func TestSchemaLegalSeverityPasses(t *testing.T) {
	if err := prompt.ValidateDraftJSON(legalDraftJSON()); err != nil {
		t.Fatal(err)
	}
}

func TestSchemaIllegalSeverityFails(t *testing.T) {
	raw := []byte(strings.Replace(string(legalDraftJSON()), `"severity": "warning"`, `"severity": "critical"`, 1))
	if err := prompt.ValidateDraftJSON(raw); err == nil {
		t.Fatal("illegal severity must fail")
	}
}

func TestSchemaLegalDestinationPasses(t *testing.T) {
	if err := prompt.ValidateDraftJSON(legalDraftJSON()); err != nil {
		t.Fatal(err)
	}
}

func TestSchemaIllegalDestinationFails(t *testing.T) {
	raw := []byte(strings.Replace(string(legalDraftJSON()), `"destination": "cashFlow"`, `"destination": "settings"`, 1))
	if err := prompt.ValidateDraftJSON(raw); err == nil {
		t.Fatal("illegal destination must fail")
	}
}

func TestSchemaSingularTopLevelActionRejected(t *testing.T) {
	var obj map[string]any
	if err := json.Unmarshal(legalDraftJSON(), &obj); err != nil {
		t.Fatal(err)
	}
	obj["action"] = map[string]any{"title": "x", "destination": "cashFlow"}
	raw, _ := json.Marshal(obj)
	if err := prompt.ValidateDraftJSON(raw); err == nil {
		t.Fatal("singular action must be rejected")
	}
}

func TestSchemaUnknownTopLevelKeyRejected(t *testing.T) {
	var obj map[string]any
	if err := json.Unmarshal(legalDraftJSON(), &obj); err != nil {
		t.Fatal(err)
	}
	obj["keyFact"] = map[string]any{"label": "x"}
	raw, _ := json.Marshal(obj)
	if err := prompt.ValidateDraftJSON(raw); err == nil {
		t.Fatal("unknown top-level key must be rejected")
	}
}

func TestSchemaIllegalKeyFactKindFails(t *testing.T) {
	raw := []byte(strings.Replace(string(legalDraftJSON()), `"kind": "balance"`, `"kind": "money"`, 1))
	if err := prompt.ValidateDraftJSON(raw); err == nil {
		t.Fatal("illegal keyFact kind must fail")
	}
}

func TestSchemaMoneyWithoutCurrencyCodeFails(t *testing.T) {
	var doc map[string]any
	if err := json.Unmarshal(legalDraftJSON(), &doc); err != nil {
		t.Fatal(err)
	}
	keyFacts := doc["keyFacts"].([]any)
	fact := keyFacts[0].(map[string]any)
	value := fact["value"].(map[string]any)
	delete(value, "currencyCode")
	raw, err := json.Marshal(doc)
	if err != nil {
		t.Fatal(err)
	}
	if err := prompt.ValidateDraftJSON(raw); err == nil {
		t.Fatal("money without currencyCode must fail schema")
	}
}

func TestSchemaRequiredArraysPresent(t *testing.T) {
	raw := []byte(`{
		"title": "t",
		"body": "b",
		"answer": "a",
		"confidence": 0.1
	}`)
	if err := prompt.ValidateDraftJSON(raw); err == nil {
		t.Fatal("missing required arrays must fail")
	}
}

func TestSchemaFileMatchesDTOTopLevelKeys(t *testing.T) {
	raw, err := prompt.LoadAssistantAnswerDraftSchema()
	if err != nil {
		t.Fatal(err)
	}
	var schema map[string]any
	if err := json.Unmarshal(raw, &schema); err != nil {
		t.Fatal(err)
	}
	props := schema["properties"].(map[string]any)
	for _, key := range prompt.AllowedDraftTopLevelKeys {
		if _, ok := props[key]; !ok {
			t.Fatalf("schema missing DTO field %s", key)
		}
	}
	if _, ok := props["action"]; ok {
		t.Fatal("schema must not include singular action")
	}
	add, _ := schema["additionalProperties"].(bool)
	if add {
		t.Fatal("additionalProperties must be false")
	}
}
