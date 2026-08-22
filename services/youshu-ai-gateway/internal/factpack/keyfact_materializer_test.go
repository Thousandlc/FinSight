package factpack_test

import (
	"errors"
	"strings"
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/factpack"
)

func sampleFacts() *contract.MonthlySummaryFactsDTO {
	pct := "25"
	level := "high"
	return &contract.MonthlySummaryFactsDTO{
		AvailableCash:              contract.MoneyDTO{Amount: "10000", CurrencyCode: "CNY"},
		MonthlyIncome:              contract.MoneyDTO{Amount: "12000", CurrencyCode: "CNY"},
		MonthlyExpense:             contract.MoneyDTO{Amount: "6000", CurrencyCode: "CNY"},
		MonthlyDebtPayment:         contract.MoneyDTO{Amount: "2000", CurrencyCode: "CNY"},
		PrimaryPressure:            "日常支出",
		EstimatedMonthEndBalance:   contract.MoneyDTO{Amount: "8000", CurrencyCode: "CNY"},
		DebtPaymentToIncomePercent: &pct,
		DebtPressureLevel:          &level,
	}
}

func TestMaterializeKeyFactMoney(t *testing.T) {
	facts := sampleFacts()
	got, err := factpack.MaterializeKeyFact("monthlyIncome", "收入", "income", facts)
	if err != nil {
		t.Fatal(err)
	}
	if got.Value.Type != "money" || got.Value.Amount == nil || *got.Value.Amount != 12000 {
		t.Fatalf("money materialization=%+v", got.Value)
	}
}

func TestMaterializeKeyFactPercent(t *testing.T) {
	facts := sampleFacts()
	got, err := factpack.MaterializeKeyFact("debtPaymentToIncomePercent", "DTI", "debt", facts)
	if err != nil {
		t.Fatal(err)
	}
	if got.Value.Type != "percent" || got.Value.PercentValue == nil || *got.Value.PercentValue != 25 {
		t.Fatalf("percent materialization=%+v", got.Value)
	}
}

func TestMaterializeKeyFactText(t *testing.T) {
	facts := sampleFacts()
	got, err := factpack.MaterializeKeyFact("debtPressureLevel", "压力", "other", facts)
	if err != nil {
		t.Fatal(err)
	}
	if got.Value.Type != "text" || got.Value.TextValue == nil || *got.Value.TextValue != "high" {
		t.Fatalf("text materialization=%+v", got.Value)
	}
}

func TestMaterializeKeyFactUnregisteredFails(t *testing.T) {
	facts := sampleFacts()
	_, err := factpack.MaterializeKeyFact("totalDebt", "x", "other", facts)
	if err == nil {
		t.Fatal("unregistered source must fail")
	}
	var mat *factpack.MaterializationError
	if !errors.As(err, &mat) || mat.Code != factpack.CodeUnknownFactSource {
		t.Fatalf("err=%v", err)
	}
	if err.Error() != factpack.CodeUnknownFactSource {
		t.Fatalf("Error() leaked payload: %q", err.Error())
	}
}

func TestMaterializeKeyFactInvalidAmountIsStable(t *testing.T) {
	facts := sampleFacts()
	facts.AvailableCash.Amount = "FINANCIAL_SECRET_CANARY"
	_, err := factpack.MaterializeKeyFact("availableCash", "可用资金", "balance", facts)
	if err == nil {
		t.Fatal("invalid amount must fail")
	}
	var mat *factpack.MaterializationError
	if !errors.As(err, &mat) || mat.Code != factpack.CodeMaterializationFailure {
		t.Fatalf("err=%v", err)
	}
	if strings.Contains(err.Error(), "FINANCIAL_SECRET_CANARY") {
		t.Fatalf("amount leaked: %q", err.Error())
	}
}

func TestKnownNoDebtForbiddenKeyFactSource(t *testing.T) {
	facts := sampleFacts()
	assessment := &contract.FinancialRiskAssessmentDTO{DebtDataState: "knownNoDebt"}
	keys := factpack.BuildKeySetsForRequest(facts, assessment)
	if contains(keys.AllowedKeyFactKeys, "monthlyDebtPayment") {
		t.Fatal("monthlyDebtPayment must not be allowed keyFact for knownNoDebt")
	}
	if !contains(keys.AllowedFactKeys, "monthlyDebtPayment") {
		t.Fatal("monthlyDebtPayment must remain in AllowedFactKeys")
	}
}

func TestKnownDebtAllowsMonthlyDebtPaymentKeyFact(t *testing.T) {
	facts := sampleFacts()
	assessment := &contract.FinancialRiskAssessmentDTO{DebtDataState: "knownDebt"}
	keys := factpack.BuildKeySetsForRequest(facts, assessment)
	if !contains(keys.AllowedKeyFactKeys, "monthlyDebtPayment") {
		t.Fatal("monthlyDebtPayment must remain allowed keyFact for knownDebt")
	}
}

func contains(list []string, target string) bool {
	for _, item := range list {
		if item == target {
			return true
		}
	}
	return false
}
