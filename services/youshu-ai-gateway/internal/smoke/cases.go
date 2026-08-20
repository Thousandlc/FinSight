package smoke

import "github.com/youshu/youshu-ai-gateway/internal/contract"

// SyntheticCase defines a live smoke scenario with fully synthetic financial data.
type SyntheticCase struct {
	Name     string
	Envelope contract.RequestEnvelope
	Repeats  int
}

// AllCases returns the four P0-4.3A synthetic acceptance scenarios.
func AllCases() []SyntheticCase {
	return []SyntheticCase{
		{Name: "CaseA_HealthyCashFlow", Envelope: caseA(), Repeats: 3},
		{Name: "CaseB_CashFlowRisk", Envelope: caseB(), Repeats: 3},
		{Name: "CaseC_DebtPressure", Envelope: caseC(), Repeats: 1},
		{Name: "CaseD_InsufficientData", Envelope: caseD(), Repeats: 1},
	}
}

func caseA() contract.RequestEnvelope {
	safe := money("3000")
	minBal := money("4500")
	return contract.RequestEnvelope{
		SchemaVersion: "v1",
		RequestID:     "smoke-case-a",
		Operation:     contract.OperationMonthlySummary,
		AssistantRequest: assistantContext(
			money("10000"), money("8000"),
			money("12000"), money("6000"), money("2000"),
			money("20000"), money("2000"),
			&safe, &minBal, nil,
		),
		MonthlySummaryFacts: &contract.MonthlySummaryFactsDTO{
			AvailableCash:            money("10000"),
			MonthlyIncome:              money("12000"),
			MonthlyExpense:             money("6000"),
			MonthlyDebtPayment:         money("2000"),
			PrimaryPressure:            "日常支出",
			EstimatedMonthEndBalance:   money("8000"),
			SafeBalance:                &safe,
			MinimumBalance:             &minBal,
			SourceLabels:               []string{"Account", "Transaction", "Debt"},
		},
	}
}

func caseB() contract.RequestEnvelope {
	safe := money("2000")
	minBal := money("800")
	risk := "预计本月最低余额将降至 ¥800，低于安全余额 ¥2000。"
	return contract.RequestEnvelope{
		SchemaVersion: "v1",
		RequestID:     "smoke-case-b",
		Operation:     contract.OperationMonthlySummary,
		AssistantRequest: assistantContext(
			money("3000"), money("1200"),
			money("8000"), money("7000"), money("2500"),
			money("15000"), money("2500"),
			&safe, &minBal, &risk,
		),
		MonthlySummaryFacts: &contract.MonthlySummaryFactsDTO{
			AvailableCash:              money("3000"),
			MonthlyIncome:              money("8000"),
			MonthlyExpense:             money("7000"),
			MonthlyDebtPayment:         money("2500"),
			PrimaryPressure:            "债务还款",
			EstimatedMonthEndBalance:   money("1200"),
			CashFlowRiskExplanation:    &risk,
			SafeBalance:                &safe,
			MinimumBalance:             &minBal,
			SourceLabels:               []string{"Account", "Transaction", "Debt", "CashFlow"},
		},
	}
}

func caseC() contract.RequestEnvelope {
	pct := "40"
	return contract.RequestEnvelope{
		SchemaVersion: "v1",
		RequestID:     "smoke-case-c",
		Operation:     contract.OperationMonthlySummary,
		AssistantRequest: assistantContext(
			money("5000"), money("3000"),
			money("10000"), money("5000"), money("4000"),
			money("60000"), money("4000"),
			nil, nil, nil,
		),
		MonthlySummaryFacts: &contract.MonthlySummaryFactsDTO{
			AvailableCash:              money("5000"),
			MonthlyIncome:              money("10000"),
			MonthlyExpense:             money("5000"),
			MonthlyDebtPayment:         money("4000"),
			DebtPaymentToIncomePercent: &pct,
			PrimaryPressure:            "债务还款",
			EstimatedMonthEndBalance:   money("3000"),
			SourceLabels:               []string{"Account", "Transaction", "Debt"},
		},
	}
}

func caseD() contract.RequestEnvelope {
	return contract.RequestEnvelope{
		SchemaVersion: "v1",
		RequestID:     "smoke-case-d",
		Operation:     contract.OperationMonthlySummary,
		AssistantRequest: assistantContext(
			money("2000"), money("1500"),
			money("5000"), money("4500"), money("800"),
			money("0"), money("800"),
			nil, nil, nil,
		),
		MonthlySummaryFacts: &contract.MonthlySummaryFactsDTO{
			AvailableCash:            money("2000"),
			MonthlyIncome:            money("5000"),
			MonthlyExpense:           money("4500"),
			MonthlyDebtPayment:       money("800"),
			PrimaryPressure:          "日常支出",
			EstimatedMonthEndBalance: money("1500"),
			SourceLabels:             []string{"Account"},
		},
	}
}

func money(amount string) contract.MoneyDTO {
	return contract.MoneyDTO{Amount: amount, CurrencyCode: "CNY"}
}

func assistantContext(
	availableCash, estimatedMonthEnd contract.MoneyDTO,
	income, expense, debtPayment contract.MoneyDTO,
	totalDebt, estimatedRepayment contract.MoneyDTO,
	safeBalance, minimumBalance *contract.MoneyDTO,
	riskExplanation *string,
) contract.AssistantRequestDTO {
	ctx := map[string]any{
		"meta": map[string]any{"currencyCode": "CNY"},
		"balance": map[string]any{
			"availableCash":     map[string]any{"amount": availableCash.Amount, "currencyCode": "CNY"},
			"estimatedMonthEnd": map[string]any{"amount": estimatedMonthEnd.Amount, "currencyCode": "CNY"},
		},
		"monthly": map[string]any{
			"income":      map[string]any{"amount": income.Amount, "currencyCode": "CNY"},
			"expense":     map[string]any{"amount": expense.Amount, "currencyCode": "CNY"},
			"debtPayment": map[string]any{"amount": debtPayment.Amount, "currencyCode": "CNY"},
		},
		"debt": map[string]any{
			"totalOutstanding":          map[string]any{"amount": totalDebt.Amount, "currencyCode": "CNY"},
			"estimatedMonthlyRepayment": map[string]any{"amount": estimatedRepayment.Amount, "currencyCode": "CNY"},
		},
		"spending": map[string]any{"topCategories": []any{}},
		"goals":    []any{},
		"budgets":  []any{},
	}
	if safeBalance != nil && minimumBalance != nil {
		ctx["cashFlow30"] = map[string]any{
			"endingBalance":        map[string]any{"amount": estimatedMonthEnd.Amount, "currencyCode": "CNY"},
			"minimumBalance":       map[string]any{"amount": minimumBalance.Amount, "currencyCode": "CNY"},
			"minimumBalanceDate":   "2026-08-15T00:00:00Z",
			"isBelowSafeBalance":   true,
			"safeBalance":          map[string]any{"amount": safeBalance.Amount, "currencyCode": "CNY"},
		}
	}
	_ = riskExplanation
	return contract.AssistantRequestDTO{
		Question: "",
		Intent:   "unknown",
		Context:  ctx,
	}
}
