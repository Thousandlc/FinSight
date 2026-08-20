package handler_test

import (
	"encoding/json"
	"reflect"
	"sort"
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/handler"
	"github.com/youshu/youshu-ai-gateway/internal/prompt"
)

func TestSchemaEnumSetsMatchValidator(t *testing.T) {
	raw, err := prompt.LoadAssistantAnswerDraftSchema()
	if err != nil {
		t.Fatal(err)
	}
	var schema map[string]any
	if err := json.Unmarshal(raw, &schema); err != nil {
		t.Fatal(err)
	}
	defs, _ := schema["$defs"].(map[string]any)

	assertEnumEqual(t, schemaEnum(defs, "keyFact", "kind"), handler.AllowedKeyFactKinds)
	assertEnumEqual(t, schemaEnum(defs, "keyFactValue", "type"), handler.AllowedKeyFactValueTypes)
	assertEnumEqual(t, schemaEnum(defs, "warning", "severity"), handler.AllowedWarningSeverities)
	assertEnumEqual(t, schemaEnum(defs, "action", "destination"), handler.AllowedActionDestinations)
}

func TestAllLegalKeyFactKindsPassValidator(t *testing.T) {
	for _, kind := range handler.AllowedKeyFactKinds {
		draft := validDraft()
		draft.KeyFacts[0].Kind = kind
		if err := handler.ValidateDraft(draft); err != nil {
			t.Fatalf("kind=%q: %v", kind, err)
		}
	}
}

func TestIllegalKeyFactKindFailsValidator(t *testing.T) {
	draft := validDraft()
	draft.KeyFacts[0].Kind = "money"
	diag := handler.DiagnoseSchema(draft)
	if diag.KeyFactKindValid {
		t.Fatal("expected keyFact kind failure")
	}
	if diag.InvalidEnumField != "keyFacts.kind" || diag.InvalidEnumValue != "money" {
		t.Fatalf("invalidEnumField=%q invalidEnumValue=%q", diag.InvalidEnumField, diag.InvalidEnumValue)
	}
}

func TestAllLegalWarningSeveritiesPassValidator(t *testing.T) {
	for _, severity := range handler.AllowedWarningSeverities {
		draft := validDraft()
		draft.Warnings = []contract.Warning{{
			Title: "提示", Message: "关注现金流", Severity: severity, Source: "availableCash",
		}}
		if err := handler.ValidateDraft(draft); err != nil {
			t.Fatalf("severity=%q: %v", severity, err)
		}
	}
}

func TestIllegalWarningSeverityFailsValidator(t *testing.T) {
	draft := validDraft()
	draft.Warnings = []contract.Warning{{
		Title: "提示", Message: "关注现金流", Severity: "critical", Source: "availableCash",
	}}
	diag := handler.DiagnoseSchema(draft)
	if diag.WarningSeverityValid {
		t.Fatal("expected warning severity failure")
	}
	if diag.InvalidEnumField != "warnings.severity" || diag.InvalidEnumValue != "critical" {
		t.Fatalf("invalidEnumField=%q invalidEnumValue=%q", diag.InvalidEnumField, diag.InvalidEnumValue)
	}
}

func TestAllLegalActionDestinationsPassValidator(t *testing.T) {
	for _, destination := range handler.AllowedActionDestinations {
		draft := validDraft()
		draft.Actions = []contract.Action{{Title: "查看", Destination: destination}}
		if err := handler.ValidateDraft(draft); err != nil {
			t.Fatalf("destination=%q: %v", destination, err)
		}
	}
}

func TestIllegalActionDestinationFailsValidator(t *testing.T) {
	draft := validDraft()
	draft.Actions = []contract.Action{{Title: "查看", Destination: "settings"}}
	diag := handler.DiagnoseSchema(draft)
	if diag.ActionDestinationValid {
		t.Fatal("expected action destination failure")
	}
	if diag.InvalidEnumField != "actions.destination" || diag.InvalidEnumValue != "settings" {
		t.Fatalf("invalidEnumField=%q invalidEnumValue=%q", diag.InvalidEnumField, diag.InvalidEnumValue)
	}
}

func TestMoneyWithoutCurrencyCodeFailsValidator(t *testing.T) {
	draft := validDraft()
	draft.KeyFacts[0].Value.CurrencyCode = nil
	diag := handler.DiagnoseSchema(draft)
	if diag.KeyFactValueValid {
		t.Fatal("expected keyFact value failure")
	}
	if diag.InvalidEnumField != "keyFacts.value.currencyCode" {
		t.Fatalf("invalidEnumField=%q", diag.InvalidEnumField)
	}
}

func TestDiagnoseSchemaSplitsEnumChecks(t *testing.T) {
	draft := validDraft()
	draft.KeyFacts[0].Value.CurrencyCode = nil
	diag := handler.DiagnoseSchema(draft)
	if diag.EnumValid {
		t.Fatal("enumValid should be false")
	}
	if !diag.KeyFactKindValid || diag.KeyFactValueValid || !diag.WarningSeverityValid || !diag.ActionDestinationValid {
		t.Fatalf("kind=%t value=%t warning=%t action=%t",
			diag.KeyFactKindValid, diag.KeyFactValueValid, diag.WarningSeverityValid, diag.ActionDestinationValid)
	}
}

func validDraft() contract.AssistantAnswerDraftDTO {
	amount := 10000.0
	currency := "CNY"
	return contract.AssistantAnswerDraftDTO{
		Title:         "本月财务摘要",
		Body:          "正文",
		Answer:        "正文",
		CitedFactKeys: []string{"availableCash"},
		Unknowns:      []string{},
		Confidence:    0.8,
		KeyFacts: []contract.KeyFact{{
			Label:  "可用资金",
			Kind:   "balance",
			Source: "availableCash",
			Value: contract.KeyFactValue{
				Type:         "money",
				Amount:       &amount,
				CurrencyCode: &currency,
			},
		}},
		Warnings:   []contract.Warning{},
		Actions:    []contract.Action{{Title: "查看未来现金流", Destination: "cashFlow"}},
		References: []contract.Reference{{Key: "availableCash"}},
	}
}

func schemaEnum(defs map[string]any, defName, property string) []string {
	def, ok := defs[defName].(map[string]any)
	if !ok {
		return nil
	}
	props, ok := def["properties"].(map[string]any)
	if !ok {
		return nil
	}
	prop, ok := props[property].(map[string]any)
	if !ok {
		return nil
	}
	raw, ok := prop["enum"].([]any)
	if !ok {
		return nil
	}
	out := make([]string, 0, len(raw))
	for _, item := range raw {
		value, _ := item.(string)
		out = append(out, value)
	}
	sort.Strings(out)
	return out
}

func assertEnumEqual(t *testing.T, got, want []string) {
	t.Helper()
	if !reflect.DeepEqual(got, handlerSorted(want)) {
		t.Fatalf("schema=%v validator=%v", got, handlerSorted(want))
	}
}

func handlerSorted(values []string) []string {
	out := append([]string(nil), values...)
	sort.Strings(out)
	return out
}
