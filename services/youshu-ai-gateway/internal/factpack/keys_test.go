package factpack_test

import (
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/factpack"
	"github.com/youshu/youshu-ai-gateway/internal/smoke"
)

func TestBuildKeySetsAllowedFactKeysIncludeAvailableCash(t *testing.T) {
	facts := &contract.MonthlySummaryFactsDTO{
		AvailableCash:            contract.MoneyDTO{Amount: "10000", CurrencyCode: "CNY"},
		MonthlyIncome:            contract.MoneyDTO{Amount: "12000", CurrencyCode: "CNY"},
		MonthlyExpense:           contract.MoneyDTO{Amount: "6000", CurrencyCode: "CNY"},
		MonthlyDebtPayment:       contract.MoneyDTO{Amount: "2000", CurrencyCode: "CNY"},
		PrimaryPressure:          "日常支出",
		EstimatedMonthEndBalance: contract.MoneyDTO{Amount: "8000", CurrencyCode: "CNY"},
	}
	keys := factpack.BuildKeySets(facts)
	found := false
	for _, k := range keys.AllowedFactKeys {
		if k == "availableCash" {
			found = true
			break
		}
	}
	if !found {
		t.Fatalf("AllowedFactKeys=%v missing availableCash", keys.AllowedFactKeys)
	}
}

func TestBuildKeySetsMatchesSmokeAllowedKeys(t *testing.T) {
	facts := smokeCaseCFacts()
	keys := factpack.BuildKeySets(facts)
	amountKeys, factKeys, refKeys := smoke.AllowedKeys(facts)

	if len(keys.AmountKeys) != len(amountKeys) {
		t.Fatalf("amount key count mismatch")
	}
	for k, v := range amountKeys {
		got, ok := keys.AmountKeys[k]
		if !ok || got.Amount != v.Amount {
			t.Fatalf("amount key mismatch for %s", k)
		}
	}
	for k, v := range factKeys {
		got, ok := keys.FactKeys[k]
		if !ok || got != v {
			t.Fatalf("fact key mismatch for %s", k)
		}
	}
	if len(keys.RefKeys) != len(refKeys) {
		t.Fatalf("reference key count mismatch")
	}
	for k := range refKeys {
		if _, ok := keys.RefKeys[k]; !ok {
			t.Fatalf("missing ref key %s", k)
		}
	}
}

func TestDifferentSyntheticCasesProduceDifferentFactKeyEnums(t *testing.T) {
	caseC := factpack.BuildKeySets(smokeCaseCFacts())
	caseD := factpack.BuildKeySets(smokeCaseDFacts())

	has := func(list []string, key string) bool {
		for _, item := range list {
			if item == key {
				return true
			}
		}
		return false
	}
	if !has(caseC.AllowedFactKeys, "debtPaymentToIncomePercent") {
		t.Fatal("case C must include debtPaymentToIncomePercent")
	}
	if has(caseD.AllowedFactKeys, "debtPaymentToIncomePercent") {
		t.Fatal("case D must not include debtPaymentToIncomePercent")
	}
}

func TestDebtPressureLevelRegistersOnlyWhenPresent(t *testing.T) {
	without := factpack.BuildKeySets(smokeCaseDFacts())
	if _, ok := without.FactKeys["debtPressureLevel"]; ok {
		t.Fatal("debtPressureLevel must not register when absent")
	}
	if _, ok := without.RefKeys["debtPressureLevel"]; ok {
		t.Fatal("debtPressureLevel reference must not register when fact absent")
	}
	if containsString(without.AllowedFactKeys, "debtPressureLevel") {
		t.Fatal("AllowedFactKeys must exclude absent debtPressureLevel")
	}

	withLevel := smokeCaseDFacts()
	level := "high"
	withLevel.DebtPressureLevel = &level
	keys := factpack.BuildKeySets(withLevel)
	if keys.FactKeys["debtPressureLevel"] != "high" {
		t.Fatalf("FactKeys=%v", keys.FactKeys)
	}
	if _, ok := keys.RefKeys["debtPressureLevel"]; !ok {
		t.Fatal("debtPressureLevel reference must register when fact present")
	}
	if !containsString(keys.ReferenceKeyList, "debtPressureLevel") {
		t.Fatal("ReferenceKeyList must include present debtPressureLevel")
	}
}

func containsString(list []string, target string) bool {
	for _, item := range list {
		if item == target {
			return true
		}
	}
	return false
}

func smokeCaseCFacts() *contract.MonthlySummaryFactsDTO {
	pct := "40"
	return &contract.MonthlySummaryFactsDTO{
		AvailableCash:              contract.MoneyDTO{Amount: "5000", CurrencyCode: "CNY"},
		MonthlyIncome:              contract.MoneyDTO{Amount: "10000", CurrencyCode: "CNY"},
		MonthlyExpense:             contract.MoneyDTO{Amount: "5000", CurrencyCode: "CNY"},
		MonthlyDebtPayment:         contract.MoneyDTO{Amount: "4000", CurrencyCode: "CNY"},
		DebtPaymentToIncomePercent: &pct,
		PrimaryPressure:            "债务还款",
		EstimatedMonthEndBalance:   contract.MoneyDTO{Amount: "3000", CurrencyCode: "CNY"},
	}
}

func smokeCaseDFacts() *contract.MonthlySummaryFactsDTO {
	return &contract.MonthlySummaryFactsDTO{
		AvailableCash:            contract.MoneyDTO{Amount: "2000", CurrencyCode: "CNY"},
		MonthlyIncome:            contract.MoneyDTO{Amount: "5000", CurrencyCode: "CNY"},
		MonthlyExpense:           contract.MoneyDTO{Amount: "4500", CurrencyCode: "CNY"},
		MonthlyDebtPayment:       contract.MoneyDTO{Amount: "800", CurrencyCode: "CNY"},
		PrimaryPressure:          "日常支出",
		EstimatedMonthEndBalance: contract.MoneyDTO{Amount: "1500", CurrencyCode: "CNY"},
	}
}
