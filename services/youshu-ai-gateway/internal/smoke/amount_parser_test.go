package smoke

import (
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
)

func TestExtractYuanAmountPlainNumber(t *testing.T) {
	got := extractYuanAmounts("当前余额为 ¥3000")
	if len(got) != 1 || got[0] != "3000" {
		t.Fatalf("¥3000 => %v want [3000]", got)
	}
}

func TestExtractYuanAmountThousandsSeparator(t *testing.T) {
	cases := map[string]string{
		"当前余额为 ¥3,000":   "3000",
		"收入 ¥10,000":       "10000",
		"支出 ¥12,000":       "12000",
		"还款 ¥2,500":        "2500",
		"结余 ¥1,200":        "1200",
		"最低 ¥800":          "800",
		"可用 ¥ 3,000":       "3000",
		"精确 ¥3,000.50":     "3000.5",
		"小数 ¥1234.56":      "1234.56",
	}
	for narrative, want := range cases {
		got := extractYuanAmounts(narrative)
		if len(got) != 1 {
			t.Fatalf("%q => %v want one amount", narrative, got)
		}
		if got[0] != want {
			t.Fatalf("%q => %q want %q", narrative, got[0], want)
		}
	}
}

func TestExtractYuanAmountIgnoresNonMoneyTokens(t *testing.T) {
	narrative := "未来3个月预计30天内还款60%，2026年需关注7天缓冲"
	if got := extractYuanAmounts(narrative); len(got) != 0 {
		t.Fatalf("non-money narrative must not extract amounts: %v", got)
	}
}

func TestDiagnoseFactsThousandSeparatorNarrativePasses(t *testing.T) {
	facts := &contract.MonthlySummaryFactsDTO{
		AvailableCash:            contract.MoneyDTO{Amount: "3000", CurrencyCode: "CNY"},
		MonthlyIncome:            contract.MoneyDTO{Amount: "8000", CurrencyCode: "CNY"},
		MonthlyExpense:           contract.MoneyDTO{Amount: "7000", CurrencyCode: "CNY"},
		MonthlyDebtPayment:       contract.MoneyDTO{Amount: "2500", CurrencyCode: "CNY"},
		PrimaryPressure:          "债务还款",
		EstimatedMonthEndBalance: contract.MoneyDTO{Amount: "1200", CurrencyCode: "CNY"},
	}
	draft := validFactDraft(facts)
	draft.Body = "当前可用资金约 ¥3,000，预计月底结余 ¥1,200。"
	draft.Answer = draft.Body
	diag := DiagnoseFacts(draft, facts)
	if !diag.AmountFactsValid || !diag.Passed {
		t.Fatalf("thousand-separated narrative must pass, invented=%d rules=%s",
			diag.InventedFactCount, diag.FailureRulesSummary())
	}
}

func TestDiagnoseFactsInventedAmountStillFails(t *testing.T) {
	facts := &contract.MonthlySummaryFactsDTO{
		AvailableCash:            contract.MoneyDTO{Amount: "3000", CurrencyCode: "CNY"},
		MonthlyIncome:            contract.MoneyDTO{Amount: "8000", CurrencyCode: "CNY"},
		MonthlyExpense:           contract.MoneyDTO{Amount: "7000", CurrencyCode: "CNY"},
		MonthlyDebtPayment:       contract.MoneyDTO{Amount: "2500", CurrencyCode: "CNY"},
		PrimaryPressure:          "债务还款",
		EstimatedMonthEndBalance: contract.MoneyDTO{Amount: "1200", CurrencyCode: "CNY"},
	}
	draft := validFactDraft(facts)
	draft.Body = "当前余额为 ¥3,001"
	draft.Answer = draft.Body
	diag := DiagnoseFacts(draft, facts)
	if diag.AmountFactsValid || diag.Passed {
		t.Fatal("invented ¥3,001 must fail when fact pack only allows 3000")
	}
	if !containsRule(diag, FactRuleInventedAmount) {
		t.Fatalf("expected inventedAmount rule, got %s", diag.FailureRulesSummary())
	}
}

func TestThousandSeparatorBugRegression(t *testing.T) {
	// Documents the pre-fix false positive: ¥3,000 was parsed as 3.
	got := extractYuanAmounts("¥3,000")
	if len(got) != 1 || got[0] == "3" {
		t.Fatalf("¥3,000 must not parse as 3, got %v", got)
	}
	if got[0] != "3000" {
		t.Fatalf("¥3,000 => %q want 3000", got[0])
	}
}

func TestExtractYuanAmountMultipleMatches(t *testing.T) {
	got := extractYuanAmounts("可用 ¥3,000，收入 ¥10,000")
	if len(got) != 2 {
		t.Fatalf("want 2 amounts, got %v", got)
	}
	for _, want := range []string{"3000", "10000"} {
		found := false
		for _, item := range got {
			if item == want {
				found = true
				break
			}
		}
		if !found {
			t.Fatalf("missing %s in %v", want, got)
		}
	}
}

func TestExtractYuanAmountDoesNotMatchPartialCommaGroup(t *testing.T) {
	// Ensure we do not treat malformed comma groups as multiple tiny amounts.
	narrative := "约 ¥3,000,000"
	got := extractYuanAmounts(narrative)
	if len(got) != 1 || got[0] != "3000000" {
		t.Fatalf("got %v", got)
	}
}
