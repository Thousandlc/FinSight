package contract_test

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
)

func TestMoneyAmountNumberDecodes(t *testing.T) {
	raw := []byte(`{
		"title": "t",
		"body": "b",
		"answer": "a",
		"citedFactKeys": [],
		"unknowns": [],
		"confidence": 0.8,
		"keyFacts": [{
			"label": "可用资金",
			"kind": "balance",
			"source": "availableCash",
			"value": {"type": "money", "amount": 10000, "currencyCode": "CNY"}
		}],
		"warnings": [],
		"actions": [],
		"references": []
	}`)
	var draft contract.AssistantAnswerDraftDTO
	if err := json.Unmarshal(raw, &draft); err != nil {
		t.Fatalf("number amount must decode: %v", err)
	}
	if len(draft.KeyFacts) != 1 || draft.KeyFacts[0].Value.Amount == nil {
		t.Fatal("expected money amount")
	}
	if *draft.KeyFacts[0].Value.Amount != 10000 {
		t.Fatalf("amount=%v", *draft.KeyFacts[0].Value.Amount)
	}
}

func TestMoneyAmountStringStillFails(t *testing.T) {
	raw := []byte(`{
		"title": "t",
		"body": "b",
		"answer": "a",
		"citedFactKeys": [],
		"unknowns": [],
		"confidence": 0.8,
		"keyFacts": [{
			"label": "可用资金",
			"kind": "balance",
			"source": "availableCash",
			"value": {"type": "money", "amount": "10000", "currencyCode": "CNY"}
		}],
		"warnings": [],
		"actions": [],
		"references": []
	}`)
	var draft contract.AssistantAnswerDraftDTO
	if err := json.Unmarshal(raw, &draft); err == nil {
		t.Fatal("quoted string amount must continue to fail; decoder must not be relaxed")
	}
}

func TestPercentValueNumberDecodes(t *testing.T) {
	raw := []byte(`{
		"title": "t",
		"body": "b",
		"answer": "a",
		"citedFactKeys": [],
		"unknowns": [],
		"confidence": 0.8,
		"keyFacts": [{
			"label": "占比",
			"kind": "debt",
			"source": "debtPaymentToIncomePercent",
			"value": {"type": "percent", "value": 40}
		}],
		"warnings": [],
		"actions": [],
		"references": []
	}`)
	var draft contract.AssistantAnswerDraftDTO
	if err := json.Unmarshal(raw, &draft); err != nil {
		t.Fatalf("number percent must decode: %v", err)
	}
	if draft.KeyFacts[0].Value.PercentValue == nil || *draft.KeyFacts[0].Value.PercentValue != 40 {
		t.Fatalf("percent=%v", draft.KeyFacts[0].Value.PercentValue)
	}
	encoded, err := json.Marshal(draft.KeyFacts[0].Value)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(encoded), `"value":40`) {
		t.Fatalf("percent must marshal as JSON number: %s", encoded)
	}
}

func TestPercentValueStringStillFails(t *testing.T) {
	raw := []byte(`{
		"title": "t",
		"body": "b",
		"answer": "a",
		"citedFactKeys": [],
		"unknowns": [],
		"confidence": 0.8,
		"keyFacts": [{
			"label": "占比",
			"kind": "debt",
			"source": "debtPaymentToIncomePercent",
			"value": {"type": "percent", "value": "40"}
		}],
		"warnings": [],
		"actions": [],
		"references": []
	}`)
	var draft contract.AssistantAnswerDraftDTO
	if err := json.Unmarshal(raw, &draft); err == nil {
		t.Fatal("quoted string percent must continue to fail")
	}
}
