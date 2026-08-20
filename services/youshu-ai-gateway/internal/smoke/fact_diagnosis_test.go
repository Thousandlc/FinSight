package smoke

import (
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
)

func TestDiagnoseFactsAllValidPass(t *testing.T) {
	facts := sampleFacts()
	draft := validFactDraft(facts)
	diag := DiagnoseFacts(draft, facts)
	if !diag.Passed {
		t.Fatalf("expected pass, rules=%s invalidRule=%s", diag.FailureRulesSummary(), diag.InvalidFactRule)
	}
}

func TestDiagnoseFactsInvalidCitedFactKey(t *testing.T) {
	facts := sampleFacts()
	draft := validFactDraft(facts)
	draft.CitedFactKeys = append(draft.CitedFactKeys, "totalDebt")
	diag := DiagnoseFacts(draft, facts)
	if diag.Passed || diag.CitedFactKeysValid {
		t.Fatal("expected citedFactKeys failure")
	}
	if !containsRule(diag, FactRuleCitedUnknownFact) || diag.InvalidFactKey != "totalDebt" {
		t.Fatalf("diag=%+v", diag)
	}
}

func TestDiagnoseFactsInvalidKeyFactSource(t *testing.T) {
	facts := sampleFacts()
	draft := validFactDraft(facts)
	draft.KeyFacts = append(draft.KeyFacts, moneyKeyFact("总债务", "totalDebt", "debt", "20000"))
	diag := DiagnoseFacts(draft, facts)
	if diag.Passed || diag.KeyFactSourcesValid {
		t.Fatal("expected invalid keyFact source failure")
	}
	if !containsRule(diag, FactRuleInvalidKeyFactSource) {
		t.Fatalf("diag=%+v", diag)
	}
}

func TestDiagnoseFactsKeyFactValueMismatch(t *testing.T) {
	facts := sampleFacts()
	draft := validFactDraft(facts)
	draft.KeyFacts[0].Value.Amount = ptrFloat(9999)
	diag := DiagnoseFacts(draft, facts)
	if diag.Passed || diag.KeyFactValuesValid {
		t.Fatal("expected keyFact value mismatch")
	}
	if !containsRule(diag, FactRuleKeyFactValueMismatch) {
		t.Fatalf("diag=%+v", diag)
	}
}

func TestDiagnoseFactsInvalidReference(t *testing.T) {
	facts := sampleFacts()
	draft := validFactDraft(facts)
	draft.References = append(draft.References, contract.Reference{Key: "unknownReferenceKey"})
	diag := DiagnoseFacts(draft, facts)
	if diag.Passed || diag.ReferencesValid {
		t.Fatal("expected invalid reference failure")
	}
	if !containsRule(diag, FactRuleInvalidReference) {
		t.Fatalf("diag=%+v", diag)
	}
}

func TestDiagnoseFactsDebtPressureLevelReferenceAbsentFails(t *testing.T) {
	facts := sampleFacts()
	draft := validFactDraft(facts)
	draft.References = append(draft.References, contract.Reference{Key: "debtPressureLevel"})
	diag := DiagnoseFacts(draft, facts)
	if diag.Passed || diag.ReferencesValid {
		t.Fatal("expected debtPressureLevel reference failure when fact absent")
	}
}

func TestDiagnoseFactsDebtPressureLevelReferencePresentPasses(t *testing.T) {
	level := "high"
	facts := sampleFacts()
	facts.DebtPressureLevel = &level
	draft := validFactDraft(facts)
	draft.References = append(draft.References, contract.Reference{Key: "debtPressureLevel"})
	diag := DiagnoseFacts(draft, facts)
	if !diag.Passed || !diag.ReferencesValid {
		t.Fatalf("expected pass, diag=%+v", diag)
	}
}

func TestDiagnoseFactsDebtPressureLevelWarningSourceAbsentFails(t *testing.T) {
	facts := sampleFacts()
	draft := validFactDraft(facts)
	draft.Warnings = append(draft.Warnings, contract.Warning{
		Title:    "债务压力",
		Message:  "关注",
		Severity: "warning",
		Source:   "debtPressureLevel",
	})
	diag := DiagnoseFacts(draft, facts)
	if diag.Passed || diag.WarningSourcesValid {
		t.Fatal("expected invalid warning source when debtPressureLevel fact absent")
	}
}

func TestDiagnoseFactsPercentMismatch(t *testing.T) {
	pct := "40"
	facts := &contract.MonthlySummaryFactsDTO{
		AvailableCash:              contract.MoneyDTO{Amount: "5000", CurrencyCode: "CNY"},
		MonthlyIncome:              contract.MoneyDTO{Amount: "10000", CurrencyCode: "CNY"},
		MonthlyExpense:             contract.MoneyDTO{Amount: "5000", CurrencyCode: "CNY"},
		MonthlyDebtPayment:         contract.MoneyDTO{Amount: "4000", CurrencyCode: "CNY"},
		PrimaryPressure:            "债务还款",
		EstimatedMonthEndBalance:   contract.MoneyDTO{Amount: "3000", CurrencyCode: "CNY"},
		DebtPaymentToIncomePercent: &pct,
		SourceLabels:               []string{"Account"},
	}
	value := 41.0
	draft := validFactDraft(facts)
	draft.KeyFacts = append(draft.KeyFacts, contract.KeyFact{
		Label:  "占比",
		Kind:   "debt",
		Source: "debtPaymentToIncomePercent",
		Value:  contract.KeyFactValue{Type: "percent", PercentValue: &value},
	})
	diag := DiagnoseFacts(draft, facts)
	if diag.Passed || diag.PercentFactsValid {
		t.Fatal("expected percent mismatch failure")
	}
	if !containsRule(diag, FactRuleKeyFactValueMismatch) {
		t.Fatalf("diag=%+v", diag)
	}
}

func TestDiagnoseFactsInvalidWarningSource(t *testing.T) {
	facts := sampleFacts()
	draft := validFactDraft(facts)
	draft.Warnings = []contract.Warning{{
		Title:    "风险",
		Message:  "关注现金流",
		Severity: "warning",
		Source:   "unknownWarningSource",
	}}
	diag := DiagnoseFacts(draft, facts)
	if diag.Passed || diag.WarningSourcesValid {
		t.Fatal("expected invalid warning source failure")
	}
	if !containsRule(diag, FactRuleInvalidWarningSource) {
		t.Fatalf("diag=%+v", diag)
	}
}

func TestDiagnoseFactsValidCitedFactKeysPass(t *testing.T) {
	facts := sampleFacts()
	draft := validFactDraft(facts)
	draft.CitedFactKeys = []string{"availableCash", "monthlyIncome"}
	diag := DiagnoseFacts(draft, facts)
	if !diag.CitedFactKeysValid {
		t.Fatalf("diag=%+v", diag)
	}
}

func containsRule(d FactDiagnostics, rule string) bool {
	for _, item := range d.FailureRules {
		if item == rule {
			return true
		}
	}
	return false
}

func ptrFloat(v float64) *float64 { return &v }

func moneyKeyFact(label, source, kind string, amount string) contract.KeyFact {
	parsed := parseAmount(amount)
	currency := "CNY"
	return contract.KeyFact{
		Label:  label,
		Kind:   kind,
		Source: source,
		Value: contract.KeyFactValue{
			Type:         "money",
			Amount:       &parsed,
			CurrencyCode: &currency,
		},
	}
}

func validFactDraft(facts *contract.MonthlySummaryFactsDTO) contract.AssistantAnswerDraftDTO {
	amountKeys, factKeys, _ := AllowedKeys(facts)
	cited := make([]string, 0, len(amountKeys))
	keyFacts := make([]contract.KeyFact, 0, len(amountKeys)+len(factKeys))
	for source, money := range amountKeys {
		cited = append(cited, source)
		keyFacts = append(keyFacts, moneyKeyFact(source, source, "balance", money.Amount))
	}
	for source, text := range factKeys {
		cited = append(cited, source)
		value := text
		keyFacts = append(keyFacts, contract.KeyFact{
			Label:  source,
			Kind:   "other",
			Source: source,
			Value:  contract.KeyFactValue{Type: "text", TextValue: &value},
		})
	}
	return contract.AssistantAnswerDraftDTO{
		Title:         "本月财务摘要",
		Body:          "基于已提供事实的摘要。",
		Answer:        "基于已提供事实的摘要。",
		CitedFactKeys: cited,
		Unknowns:      []string{},
		Confidence:    0.8,
		KeyFacts:      keyFacts,
		Warnings:      []contract.Warning{},
		Actions:       []contract.Action{{Title: "查看未来现金流", Destination: "cashFlow"}},
		References:    []contract.Reference{{Key: "availableCash"}},
	}
}

func sampleFacts() *contract.MonthlySummaryFactsDTO {
	safe := "3000"
	minBal := "4500"
	return &contract.MonthlySummaryFactsDTO{
		AvailableCash:            contract.MoneyDTO{Amount: "10000", CurrencyCode: "CNY"},
		MonthlyIncome:            contract.MoneyDTO{Amount: "12000", CurrencyCode: "CNY"},
		MonthlyExpense:           contract.MoneyDTO{Amount: "6000", CurrencyCode: "CNY"},
		MonthlyDebtPayment:       contract.MoneyDTO{Amount: "2000", CurrencyCode: "CNY"},
		PrimaryPressure:          "日常支出",
		EstimatedMonthEndBalance: contract.MoneyDTO{Amount: "8000", CurrencyCode: "CNY"},
		SafeBalance:              &contract.MoneyDTO{Amount: safe, CurrencyCode: "CNY"},
		MinimumBalance:           &contract.MoneyDTO{Amount: minBal, CurrencyCode: "CNY"},
		SourceLabels:             []string{"Account", "Transaction", "Debt"},
	}
}
