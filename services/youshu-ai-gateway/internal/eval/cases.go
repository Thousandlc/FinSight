package eval

import "github.com/youshu/youshu-ai-gateway/internal/contract"

func allEvaluationCases() []EvaluationCase {
	return []EvaluationCase{
		// A. 正常财务 (4)
		caseA01HealthyCashflow(),
		caseA02HighIncomeLowExpense(),
		caseA03BalancedBudget(),
		caseA04MildMonthEndPressure(),

		// B. 现金流风险 (4)
		caseB01MinimumBelowSafe(),
		caseB02MonthEndBelowSafe(),
		caseB03MonthEndNearZero(),
		caseB04ShortTermNegativeBalance(),

		// C. 债务 (6)
		caseC01NoDebt(),
		caseC02LowDebtPressure(),
		caseC03HighMonthlyPayment(),
		caseC04MultipleDebts(),
		caseC05HighDTI(),
		caseC06DebtButAdequateCashflow(),

		// D. 收支异常 (4)
		caseD01HighExpenseMonth(),
		caseD02ZeroIncomeMonth(),
		caseD03IncomeDecline(),
		caseD04ExpenseIncrease(),

		// E. 数据不足 (4)
		caseE01PartialDebtData(),
		caseE02NoCashflowProjection(),
		caseE03NoBudget(),
		caseE04PartialFactsMissing(),
		caseE05MissingDebtData(),

		// F. Edge Cases (6)
		caseF01AllAmountsZero(),
		caseF02TinyBalance(),
		caseF03LargeAmounts(),
		caseF04DecimalAmounts(),
		caseF05SameAmountMultipleFacts(),
		caseF06NoWarningExpected(),
	}
}

// --- A. 正常财务 ---

func caseA01HealthyCashflow() EvaluationCase {
	safe := money("3000")
	minBal := money("4500")
	return EvaluationCase{
		ID: "A01_healthy_cashflow", Category: CategoryHealthyFinance, Repeats: 3,
		Description: "收支健康，可用现金充足，月末结余良好",
		Envelope: envelope("eval-a01", facts(
			money("10000"), money("12000"), money("6000"), money("2000"),
			"日常支出", money("8000"), nil, nil, &safe, &minBal, nil,
			[]string{"Account", "Transaction", "Debt"},
		), ctx(money("10000"), money("8000"), money("12000"), money("6000"), money("2000"), money("20000"), money("2000"), &safe, &minBal, nil)),
		ExpectedRiskLevel: RiskLevelNone,
		AllowedActions:    []string{"cashFlow", "debt", "transactions", "accounts"},
		ForbiddenClaims:   commonForbiddenClaims(),
	}
}

func caseA02HighIncomeLowExpense() EvaluationCase {
	safe := money("5000")
	minBal := money("8000")
	return EvaluationCase{
		ID: "A02_high_income_low_expense", Category: CategoryHealthyFinance, Repeats: 1,
		Description: "高收入低支出，储蓄能力强",
		Envelope: envelope("eval-a02", facts(
			money("50000"), money("30000"), money("8000"), money("3000"),
			"日常支出", money("42000"), nil, nil, &safe, &minBal, nil,
			[]string{"Account", "Transaction", "Debt"},
		), ctx(money("50000"), money("42000"), money("30000"), money("8000"), money("3000"), money("100000"), money("3000"), &safe, &minBal, nil)),
		ExpectedRiskLevel: RiskLevelNone,
		AllowedActions:    []string{"cashFlow", "debt", "transactions", "accounts"},
		ForbiddenClaims:   commonForbiddenClaims(),
	}
}

func caseA03BalancedBudget() EvaluationCase {
	safe := money("2000")
	minBal := money("2500")
	return EvaluationCase{
		ID: "A03_balanced_budget", Category: CategoryHealthyFinance, Repeats: 1,
		Description: "收支基本平衡，略有结余",
		Envelope: envelope("eval-a03", facts(
			money("8000"), money("10000"), money("9500"), money("1500"),
			"日常支出", money("8500"), nil, nil, &safe, &minBal, nil,
			[]string{"Account", "Transaction", "Debt"},
		), ctx(money("8000"), money("8500"), money("10000"), money("9500"), money("1500"), money("30000"), money("1500"), &safe, &minBal, nil)),
		ExpectedRiskLevel: RiskLevelSafe,
		AllowedActions:    []string{"cashFlow", "debt", "transactions", "accounts"},
		ForbiddenClaims:   commonForbiddenClaims(),
	}
}

func caseA04MildMonthEndPressure() EvaluationCase {
	safe := money("3000")
	minBal := money("2800")
	pct := "33"
	return EvaluationCase{
		ID: "A04_mild_month_end_pressure", Category: CategoryHealthyFinance, Repeats: 1,
		Description: "轻微月末压力，最低余额接近安全线",
		Envelope: envelope("eval-a04", facts(
			money("6000"), money("9000"), money("8500"), money("2000"),
			"日常支出", money("3200"), nil, &pct, &safe, &minBal, nil,
			[]string{"Account", "Transaction", "Debt", "CashFlow"},
		), ctx(money("6000"), money("3200"), money("9000"), money("8500"), money("2000"), money("15000"), money("2000"), &safe, &minBal, nil)),
		ExpectedRiskLevel: RiskLevelSafe,
		AllowedActions:    []string{"cashFlow", "debt"},
		ForbiddenClaims:   commonForbiddenClaims(),
	}
}

// --- B. 现金流风险 ---

func caseB01MinimumBelowSafe() EvaluationCase {
	safe := money("2000")
	minBal := money("800")
	risk := "预计本月最低余额将降至 ¥800，低于安全余额 ¥2000。"
	return EvaluationCase{
		ID: "B01_minimum_below_safe", Category: CategoryCashFlowRisk, Repeats: 3,
		Description: "minimumBalance 低于 safeBalance，存在现金流压力",
		Envelope: envelope("eval-b01", facts(
			money("3000"), money("8000"), money("7000"), money("2500"),
			"债务还款", money("1200"), &risk, nil, &safe, &minBal, nil,
			[]string{"Account", "Transaction", "Debt", "CashFlow"},
		), ctx(money("3000"), money("1200"), money("8000"), money("7000"), money("2500"), money("15000"), money("2500"), &safe, &minBal, &risk)),
		ExpectedRiskLevel: RiskLevelWarning,
		AllowedActions:    []string{"cashFlow", "debt"},
		StructuredConclusion: StructuredConclusionExpectation{
			RequiredFactKeys:          []string{"minimumBalance", "safeBalance"},
			RequiredAnyWarningSources: []string{"minimumBalance", "safeBalance", "cashFlowRiskExplanation"},
			RequireWarning:            true,
		},
		ForbiddenClaims: append(commonForbiddenClaims(), "一定会逾期"),
	}
}

func caseB02MonthEndBelowSafe() EvaluationCase {
	safe := money("5000")
	minBal := money("3000")
	pct := "22"
	risk := "预计月末结余 ¥2500 低于安全余额 ¥5000。"
	return EvaluationCase{
		ID: "B02_month_end_below_safe", Category: CategoryCashFlowRisk, Repeats: 1,
		Description: "月末结余低于安全余额",
		Envelope: envelope("eval-b02", facts(
			money("4000"), money("9000"), money("8000"), money("2000"),
			"日常支出", money("2500"), &risk, &pct, &safe, &minBal, nil,
			[]string{"Account", "Transaction", "Debt", "CashFlow"},
		), ctx(money("4000"), money("2500"), money("9000"), money("8000"), money("2000"), money("12000"), money("2000"), &safe, &minBal, &risk)),
		ExpectedRiskLevel:  RiskLevelWarning,
		AllowedActions:       []string{"cashFlow", "debt"},
		DiagnosticKeywords:   []string{"结余"},
		ForbiddenClaims:      commonForbiddenClaims(),
	}
}

func caseB03MonthEndNearZero() EvaluationCase {
	safe := money("1000")
	minBal := money("200")
	pct := "25"
	risk := "预计月末结余接近 ¥100，存在透支风险。"
	return EvaluationCase{
		ID: "B03_month_end_near_zero", Category: CategoryCashFlowRisk, Repeats: 1,
		Description: "月末结余接近 0",
		Envelope: envelope("eval-b03", facts(
			money("1500"), money("6000"), money("5800"), money("1500"),
			"债务还款", money("100"), &risk, &pct, &safe, &minBal, nil,
			[]string{"Account", "Transaction", "Debt", "CashFlow"},
		), ctx(money("1500"), money("100"), money("6000"), money("5800"), money("1500"), money("8000"), money("1500"), &safe, &minBal, &risk)),
		ExpectedRiskLevel:          RiskLevelWarning,
		AllowedActions:             []string{"cashFlow", "debt"},
		DiagnosticKeywords: []string{"结余"},
		ForbiddenClaims:    append(commonForbiddenClaims(), "一定会逾期", "确定会透支"),
	}
}

func caseB04ShortTermNegativeBalance() EvaluationCase {
	safe := money("3000")
	minBal := money("-500")
	risk := "未来 30 天内预计出现负余额 ¥500。"
	return EvaluationCase{
		ID: "B04_short_term_negative_balance", Category: CategoryCashFlowRisk, Repeats: 1,
		Description: "未来 30 天短期负余额",
		Envelope: envelope("eval-b04", facts(
			money("2000"), money("7000"), money("6500"), money("3000"),
			"债务还款", money("500"), &risk, nil, &safe, &minBal, nil,
			[]string{"Account", "Transaction", "Debt", "CashFlow"},
		), ctx(money("2000"), money("500"), money("7000"), money("6500"), money("3000"), money("20000"), money("3000"), &safe, &minBal, &risk)),
		ExpectedRiskLevel:          RiskLevelWarning,
		AllowedActions:             []string{"cashFlow", "debt"},
		DiagnosticKeywords: []string{"现金流"},
		ForbiddenClaims:    append(commonForbiddenClaims(), "一定会逾期"),
	}
}

// --- C. 债务 ---

func caseC01NoDebt() EvaluationCase {
	return EvaluationCase{
		ID: "C01_no_debt", Category: CategoryDebt, Repeats: 1,
		Description: "无债务，月供为 0",
		Envelope: envelope("eval-c01", facts(
			money("15000"), money("12000"), money("6000"), money("0"),
			"日常支出", money("12000"), nil, nil, nil, nil, nil,
			[]string{"Account", "Transaction"},
		), ctx(money("15000"), money("12000"), money("12000"), money("6000"), money("0"), money("0"), money("0"), nil, nil, nil)),
		ExpectedRiskLevel: RiskLevelNone,
		AllowedActions:    []string{"cashFlow", "transactions", "accounts"},
		ForbiddenClaims:   append(commonForbiddenClaims(), "债务压力", "还款压力"),
		ForbiddenFactKeys: []string{"monthlyDebtPayment"}, // legacy combined semantics
		ForbiddenKeyFactSources: []string{"monthlyDebtPayment"},
		ForbiddenCitationFactKeys: nil,
	}
}

func caseC02LowDebtPressure() EvaluationCase {
	pct := "10"
	return EvaluationCase{
		ID: "C02_low_debt_pressure", Category: CategoryDebt, Repeats: 1,
		Description: "低债务压力，DTI 约 10%",
		Envelope: envelope("eval-c02", facts(
			money("20000"), money("15000"), money("8000"), money("1500"),
			"日常支出", money("18000"), nil, &pct, nil, nil, nil,
			[]string{"Account", "Transaction", "Debt"},
		), ctx(money("20000"), money("18000"), money("15000"), money("8000"), money("1500"), money("50000"), money("1500"), nil, nil, nil)),
		ExpectedRiskLevel: RiskLevelSafe,
		AllowedActions:    []string{"cashFlow", "debt", "transactions"},
		ForbiddenClaims:   commonForbiddenClaims(),
	}
}

func caseC03HighMonthlyPayment() EvaluationCase {
	pct := "40"
	return EvaluationCase{
		ID: "C03_high_monthly_payment", Category: CategoryDebt, Repeats: 3,
		Description: "高月供压力，DTI 40%",
		Envelope: envelope("eval-c03", facts(
			money("5000"), money("10000"), money("5000"), money("4000"),
			"债务还款", money("3000"), nil, &pct, nil, nil, nil,
			[]string{"Account", "Transaction", "Debt"},
		), ctx(money("5000"), money("3000"), money("10000"), money("5000"), money("4000"), money("60000"), money("4000"), nil, nil, nil)),
		ExpectedRiskLevel:          RiskLevelWarning,
		AllowedActions:             []string{"cashFlow", "debt"},
		DiagnosticKeywords: []string{"债务"},
		ForbiddenClaims:    append(commonForbiddenClaims(), "一定会逾期", "确定会违约"),
	}
}

func caseC04MultipleDebts() EvaluationCase {
	pct := "35"
	pressure := "high"
	return EvaluationCase{
		ID: "C04_multiple_debts", Category: CategoryDebt, Repeats: 1,
		Description: "多笔债务，合计月供较高",
		Envelope: envelope("eval-c04", facts(
			money("8000"), money("12000"), money("7000"), money("4200"),
			"债务还款", money("4000"), nil, &pct, nil, nil, &pressure,
			[]string{"Account", "Transaction", "Debt"},
		), ctx(money("8000"), money("4000"), money("12000"), money("7000"), money("4200"), money("80000"), money("4200"), nil, nil, nil)),
		ExpectedRiskLevel:          RiskLevelWarning,
		AllowedActions:             []string{"cashFlow", "debt"},
		DiagnosticKeywords: []string{"债务"},
		ForbiddenClaims:    append(commonForbiddenClaims(), "一定会逾期"),
	}
}

func caseC05HighDTI() EvaluationCase {
	pct := "55"
	return EvaluationCase{
		ID: "C05_high_dti", Category: CategoryDebt, Repeats: 1,
		Description: "高 DTI 55%，债务收入比过高",
		Envelope: envelope("eval-c05", facts(
			money("3000"), money("8000"), money("5000"), money("4400"),
			"债务还款", money("1500"), nil, &pct, nil, nil, nil,
			[]string{"Account", "Transaction", "Debt"},
		), ctx(money("3000"), money("1500"), money("8000"), money("5000"), money("4400"), money("100000"), money("4400"), nil, nil, nil)),
		ExpectedRiskLevel:          RiskLevelWarning,
		AllowedActions:             []string{"cashFlow", "debt"},
		DiagnosticKeywords: []string{"债务"},
		ForbiddenClaims:    append(commonForbiddenClaims(), "一定会逾期", "确定会破产"),
	}
}

func caseC06DebtButAdequateCashflow() EvaluationCase {
	pct := "25"
	pressure := "critical"
	safe := money("5000")
	minBal := money("6000")
	return EvaluationCase{
		ID: "C06_debt_but_adequate_cashflow", Category: CategoryDebt, Repeats: 1,
		Description: "有债务但现金流充足",
		Envelope: envelope("eval-c06", facts(
			money("30000"), money("20000"), money("8000"), money("5000"),
			"债务还款", money("25000"), nil, &pct, &safe, &minBal, &pressure,
			[]string{"Account", "Transaction", "Debt", "CashFlow"},
		), ctx(money("30000"), money("25000"), money("20000"), money("8000"), money("5000"), money("80000"), money("5000"), &safe, &minBal, nil)),
		ExpectedRiskLevel: RiskLevelSafe,
		AllowedActions:    []string{"cashFlow", "debt"},
		ForbiddenClaims:   append(commonForbiddenClaims(), "一定会逾期"),
	}
}

// --- D. 收支异常 ---

func caseD01HighExpenseMonth() EvaluationCase {
	pct := "20"
	return EvaluationCase{
		ID: "D01_high_expense_month", Category: CategoryIncomeExpense, Repeats: 1,
		Description: "高支出月，支出接近收入",
		Envelope: envelope("eval-d01", facts(
			money("5000"), money("10000"), money("9800"), money("2000"),
			"日常支出", money("1200"), nil, &pct, nil, nil, nil,
			[]string{"Account", "Transaction", "Debt"},
		), ctx(money("5000"), money("1200"), money("10000"), money("9800"), money("2000"), money("15000"), money("2000"), nil, nil, nil)),
		ExpectedRiskLevel:          RiskLevelWarning,
		AllowedActions:             []string{"cashFlow", "debt", "transactions"},
		DiagnosticKeywords: []string{"支出"},
		ForbiddenClaims:    commonForbiddenClaims(),
	}
}

func caseD02ZeroIncomeMonth() EvaluationCase {
	return EvaluationCase{
		ID: "D02_zero_income_month", Category: CategoryIncomeExpense, Repeats: 1,
		Description: "零收入月，仅靠储蓄维持",
		Envelope: envelope("eval-d02", facts(
			money("8000"), money("0"), money("4500"), money("1500"),
			"日常支出", money("6500"), nil, nil, nil, nil, nil,
			[]string{"Account", "Transaction", "Debt"},
		), ctx(money("8000"), money("6500"), money("0"), money("4500"), money("1500"), money("10000"), money("1500"), nil, nil, nil)),
		ExpectedRiskLevel:          RiskLevelWarning,
		AllowedActions:             []string{"cashFlow", "debt"},
		DiagnosticKeywords:     []string{"收入"},
		ForbiddenClaims:        commonForbiddenClaims(),
		ManualReviewRequired:   true,
	}
}

func caseD03IncomeDecline() EvaluationCase {
	pct := "40"
	return EvaluationCase{
		ID: "D03_income_decline", Category: CategoryIncomeExpense, Repeats: 1,
		Description: "收入明显下降（对比历史）",
		Envelope: envelope("eval-d03", facts(
			money("6000"), money("5000"), money("5500"), money("2000"),
			"日常支出", money("4500"), nil, &pct, nil, nil, nil,
			[]string{"Account", "Transaction", "Debt"},
		), ctx(money("6000"), money("4500"), money("5000"), money("5500"), money("2000"), money("12000"), money("2000"), nil, nil, nil)),
		ExpectedRiskLevel:    RiskLevelWarning,
		AllowedActions:       []string{"cashFlow", "debt", "transactions"},
		ForbiddenClaims:      commonForbiddenClaims(),
		ManualReviewRequired: true,
	}
}

func caseD04ExpenseIncrease() EvaluationCase {
	pct := "20"
	return EvaluationCase{
		ID: "D04_expense_increase", Category: CategoryIncomeExpense, Repeats: 1,
		Description: "支出明显增加",
		Envelope: envelope("eval-d04", facts(
			money("7000"), money("10000"), money("9500"), money("2000"),
			"日常支出", money("5500"), nil, &pct, nil, nil, nil,
			[]string{"Account", "Transaction", "Debt"},
		), ctx(money("7000"), money("5500"), money("10000"), money("9500"), money("2000"), money("15000"), money("2000"), nil, nil, nil)),
		ExpectedRiskLevel:    RiskLevelWarning,
		AllowedActions:       []string{"cashFlow", "debt", "transactions"},
		ForbiddenClaims:      commonForbiddenClaims(),
		ManualReviewRequired: true,
	}
}

// --- E. 数据不足 ---

func caseE01PartialDebtData() EvaluationCase {
	dti := e01ProductionDTIPercent
	return EvaluationCase{
		ID: "E01_partial_debt_data", Category: CategoryInsufficientData, Repeats: 3,
		Description: "部分债务数据：repayment+income 已知，DTI genuinely known (25%)，Debt inventory 不完整",
		Envelope: envelope("eval-e01", facts(
			money("20000"), money(e01ProductionMonthlyIncome), money("4500"), money(e01ProductionMonthlyDebtPayment),
			"债务还款", money("18000"), nil, &dti, nil, nil, nil,
			[]string{"Account"},
		), ctx(money("20000"), money("18000"), money(e01ProductionMonthlyIncome), money("4500"), money(e01ProductionMonthlyDebtPayment), money("0"), money("18000"), nil, nil, nil)),
		UnknownExpectation: UnknownNotRequired,
		ExpectedRiskLevel:  RiskLevelNone,
		AllowedActions:     []string{"cashFlow", "accounts", "transactions"},
		ForbiddenClaims:    append(commonForbiddenClaims(), "一定会逾期", "确定存在风险"),
		ForbiddenFactKeys:  []string{"totalDebt", "estimatedDebtFreeDate"},
		ForbiddenKeyFactSources:   []string{"totalDebt", "estimatedDebtFreeDate"},
		ForbiddenCitationFactKeys: []string{"totalDebt", "estimatedDebtFreeDate"},
	}
}

func caseE05MissingDebtData() EvaluationCase {
	return EvaluationCase{
		ID: "E05_missing_debt_data", Category: CategoryInsufficientData, Repeats: 1,
		Description: "债务数据 genuinely missing：无 debt payment、无 Debt source",
		Envelope: envelope("eval-e05", factsWithoutMonthlyDebtPayment(
			money("2500"), money("6000"), money("4800"),
			"日常支出", money("2200"), nil, nil, nil, nil,
			[]string{"Account"},
		), ctxWithoutDebt(money("2500"), money("2200"), money("6000"), money("4800"))),
		FactOverlay: EvalFactOverlay{
			MonthlyDebtPayment: EvalMoneyField{Availability: MoneyMissing},
		},
		UnknownExpectation: UnknownRequired,
		ExpectedRiskLevel:  RiskLevelNone,
		AllowedActions:     []string{"cashFlow", "accounts", "transactions"},
		ForbiddenClaims: append(commonForbiddenClaims(),
			"债务压力", "一定会逾期", "确定存在风险", "无债务", "没有债务", "不存在债务"),
		ForbiddenFactKeys: []string{
			"debtPaymentToIncomePercent", "totalDebt", "estimatedDebtFreeDate", "monthlyDebtPayment",
		},
		ForbiddenKeyFactSources: []string{
			"debtPaymentToIncomePercent", "totalDebt", "estimatedDebtFreeDate", "monthlyDebtPayment",
		},
		ForbiddenCitationFactKeys: []string{
			"debtPaymentToIncomePercent", "totalDebt", "estimatedDebtFreeDate", "monthlyDebtPayment",
		},
	}
}

func caseE02NoCashflowProjection() EvaluationCase {
	return EvaluationCase{
		ID: "E02_no_cashflow_projection", Category: CategoryInsufficientData, Repeats: 1,
		Description: "无 cashFlow projection 数据",
		Envelope: envelope("eval-e02", facts(
			money("5000"), money("8000"), money("6000"), money("2000"),
			"日常支出", money("5500"), nil, nil, nil, nil, nil,
			[]string{"Account", "Transaction", "Debt"},
		), ctx(money("5000"), money("5500"), money("8000"), money("6000"), money("2000"), money("10000"), money("2000"), nil, nil, nil)),
		UnknownExpectation: UnknownRequired,
		ExpectedRiskLevel:  RiskLevelNone,
		AllowedActions:    []string{"cashFlow", "debt", "transactions"},
		ForbiddenClaims:   append(commonForbiddenClaims(), "最低余额", "安全余额"),
	}
}

func caseE03NoBudget() EvaluationCase {
	pct := "21"
	return EvaluationCase{
		ID: "E03_no_budget", Category: CategoryInsufficientData, Repeats: 1,
		Description: "预算不在 MonthlySummaryFacts 合约内（not applicable），不应要求 unknowns",
		Envelope: envelope("eval-e03", facts(
			money("3000"), money("7000"), money("6500"), money("1500"),
			"日常支出", money("2800"), nil, &pct, nil, nil, nil,
			[]string{"Account", "Transaction"},
		), ctx(money("3000"), money("2800"), money("7000"), money("6500"), money("1500"), money("0"), money("1500"), nil, nil, nil)),
		UnknownExpectation: UnknownNotRequired,
		ExpectedRiskLevel:  RiskLevelNone,
		AllowedActions:    []string{"cashFlow", "transactions", "accounts"},
		ForbiddenClaims:   append(commonForbiddenClaims(), "超出预算", "预算不足"),
	}
}

func caseE04PartialFactsMissing() EvaluationCase {
	return EvaluationCase{
		ID: "E04_partial_facts_missing", Category: CategoryInsufficientData, Repeats: 1,
		Description: "optional safeBalance/minimumBalance 缺失；核心 monthly facts 完整",
		Envelope: envelope("eval-e04", facts(
			money("4000"), money("6000"), money("5500"), money("1000"),
			"日常支出", money("3500"), nil, nil, nil, nil, nil,
			[]string{"Account", "Transaction"},
		), ctx(money("4000"), money("3500"), money("6000"), money("5500"), money("1000"), money("0"), money("1000"), nil, nil, nil)),
		UnknownExpectation: UnknownNotRequired,
		ExpectedRiskLevel:  RiskLevelNone,
		AllowedActions:    []string{"cashFlow", "transactions", "accounts"},
		ForbiddenClaims:   append(commonForbiddenClaims(), "安全余额"),
		ForbiddenFactKeys: []string{"safeBalance", "minimumBalance"},
		ForbiddenKeyFactSources:   []string{"safeBalance", "minimumBalance"},
		ForbiddenCitationFactKeys: []string{"safeBalance", "minimumBalance"},
	}
}

// --- F. Edge Cases ---

func caseF01AllAmountsZero() EvaluationCase {
	zero := money("0")
	return EvaluationCase{
		ID: "F01_all_amounts_zero", Category: CategoryEdgeCase, Repeats: 1,
		Description: "所有金额为 0",
		Envelope: envelope("eval-f01", facts(
			zero, zero, zero, zero,
			"日常支出", zero, nil, nil, nil, nil, nil,
			[]string{"Account"},
		), ctx(zero, zero, zero, zero, zero, zero, zero, nil, nil, nil)),
		ExpectedRiskLevel: RiskLevelSafe,
		AllowedActions:    []string{"cashFlow", "accounts", "transactions"},
		ForbiddenClaims:   commonForbiddenClaims(),
		ManualReviewRequired: true,
	}
}

func caseF02TinyBalance() EvaluationCase {
	return EvaluationCase{
		ID: "F02_tiny_balance", Category: CategoryEdgeCase, Repeats: 1,
		Description: "极小余额 ¥0.01",
		Envelope: envelope("eval-f02", facts(
			money("0.01"), money("100"), money("99.99"), money("0"),
			"日常支出", money("0.01"), nil, nil, nil, nil, nil,
			[]string{"Account", "Transaction"},
		), ctx(money("0.01"), money("0.01"), money("100"), money("99.99"), money("0"), money("0"), money("0"), nil, nil, nil)),
		ExpectedRiskLevel: RiskLevelWarning,
		AllowedActions:    []string{"cashFlow", "transactions"},
		ForbiddenClaims:   commonForbiddenClaims(),
	}
}

func caseF03LargeAmounts() EvaluationCase {
	pct := "20"
	safe := money("500000")
	minBal := money("800000")
	return EvaluationCase{
		ID: "F03_large_amounts", Category: CategoryEdgeCase, Repeats: 1,
		Description: "大金额（百万级）",
		Envelope: envelope("eval-f03", facts(
			money("1000000"), money("500000"), money("200000"), money("100000"),
			"日常支出", money("900000"), nil, &pct, &safe, &minBal, nil,
			[]string{"Account", "Transaction", "Debt", "CashFlow"},
		), ctx(money("1000000"), money("900000"), money("500000"), money("200000"), money("100000"), money("2000000"), money("100000"), &safe, &minBal, nil)),
		ExpectedRiskLevel: RiskLevelNone,
		AllowedActions:    []string{"cashFlow", "debt", "transactions", "accounts"},
		ForbiddenClaims:   commonForbiddenClaims(),
	}
}

func caseF04DecimalAmounts() EvaluationCase {
	return EvaluationCase{
		ID: "F04_decimal_amounts", Category: CategoryEdgeCase, Repeats: 1,
		Description: "小数金额",
		Envelope: envelope("eval-f04", facts(
			money("1234.56"), money("5678.90"), money("3456.78"), money("123.45"),
			"日常支出", money("1111.11"), nil, nil, nil, nil, nil,
			[]string{"Account", "Transaction", "Debt"},
		), ctx(money("1234.56"), money("1111.11"), money("5678.90"), money("3456.78"), money("123.45"), money("5000.00"), money("123.45"), nil, nil, nil)),
		ExpectedRiskLevel: RiskLevelSafe,
		AllowedActions:    []string{"cashFlow", "debt", "transactions"},
		ForbiddenClaims:   commonForbiddenClaims(),
	}
}

func caseF05SameAmountMultipleFacts() EvaluationCase {
	amount := money("5000")
	pct := "40"
	return EvaluationCase{
		ID: "F05_same_amount_multiple_facts", Category: CategoryEdgeCase, Repeats: 1,
		Description: "同金额对应多个 facts（5000 重复出现）",
		Envelope: envelope("eval-f05", facts(
			amount, amount, money("3000"), money("2000"),
			"日常支出", amount, nil, &pct, nil, nil, nil,
			[]string{"Account", "Transaction", "Debt"},
		), ctx(amount, amount, amount, money("3000"), money("2000"), money("10000"), money("2000"), nil, nil, nil)),
		ExpectedRiskLevel: RiskLevelSafe,
		AllowedActions:    []string{"cashFlow", "debt", "transactions"},
		ForbiddenClaims:   commonForbiddenClaims(),
	}
}

func caseF06NoWarningExpected() EvaluationCase {
	safe := money("10000")
	minBal := money("15000")
	return EvaluationCase{
		ID: "F06_no_warning_expected", Category: CategoryEdgeCase, Repeats: 1,
		Description: "财务非常健康，不应生成 risk warning",
		Envelope: envelope("eval-f06", facts(
			money("50000"), money("30000"), money("10000"), money("2000"),
			"日常支出", money("45000"), nil, nil, &safe, &minBal, nil,
			[]string{"Account", "Transaction", "Debt", "CashFlow"},
		), ctx(money("50000"), money("45000"), money("30000"), money("10000"), money("2000"), money("50000"), money("2000"), &safe, &minBal, nil)),
		ExpectedRiskLevel: RiskLevelNone,
		AllowedActions:    []string{"cashFlow"},
		ForbiddenClaims:   commonForbiddenClaims(),
	}
}

// --- helpers ---

func commonForbiddenClaims() []string {
	return []string{
		"一定会逾期",
		"贷款利率",
		"确定会违约",
		"确定会破产",
	}
}

func money(amount string) contract.MoneyDTO {
	return contract.MoneyDTO{Amount: amount, CurrencyCode: "CNY"}
}

func factsWithoutMonthlyDebtPayment(
	availableCash, income, expense contract.MoneyDTO,
	primaryPressure string,
	monthEnd contract.MoneyDTO,
	riskExplanation *string,
	debtPct *string,
	safeBalance, minimumBalance *contract.MoneyDTO,
	sourceLabels []string,
) *contract.MonthlySummaryFactsDTO {
	return &contract.MonthlySummaryFactsDTO{
		AvailableCash:              availableCash,
		MonthlyIncome:              income,
		MonthlyExpense:             expense,
		DebtPaymentToIncomePercent: debtPct,
		PrimaryPressure:            primaryPressure,
		EstimatedMonthEndBalance:   monthEnd,
		CashFlowRiskExplanation:    riskExplanation,
		SafeBalance:                safeBalance,
		MinimumBalance:             minimumBalance,
		SourceLabels:               sourceLabels,
	}
}

func facts(
	availableCash, income, expense, debtPayment contract.MoneyDTO,
	primaryPressure string,
	monthEnd contract.MoneyDTO,
	riskExplanation *string,
	debtPct *string,
	safeBalance, minimumBalance *contract.MoneyDTO,
	debtPressureLevel *string,
	sourceLabels []string,
) *contract.MonthlySummaryFactsDTO {
	return &contract.MonthlySummaryFactsDTO{
		AvailableCash:              availableCash,
		MonthlyIncome:              income,
		MonthlyExpense:             expense,
		MonthlyDebtPayment:         debtPayment,
		DebtPaymentToIncomePercent: debtPct,
		PrimaryPressure:            primaryPressure,
		EstimatedMonthEndBalance:   monthEnd,
		CashFlowRiskExplanation:    riskExplanation,
		SafeBalance:                safeBalance,
		MinimumBalance:             minimumBalance,
		DebtPressureLevel:          debtPressureLevel,
		SourceLabels:               sourceLabels,
	}
}

func envelope(requestID string, monthlyFacts *contract.MonthlySummaryFactsDTO, assistant contract.AssistantRequestDTO) contract.RequestEnvelope {
	return contract.RequestEnvelope{
		SchemaVersion:       "v1",
		RequestID:             requestID,
		Operation:             contract.OperationMonthlySummary,
		AssistantRequest:      assistant,
		MonthlySummaryFacts:   monthlyFacts,
	}
}

func ctx(
	availableCash, estimatedMonthEnd contract.MoneyDTO,
	income, expense, debtPayment contract.MoneyDTO,
	totalDebt, estimatedRepayment contract.MoneyDTO,
	safeBalance, minimumBalance *contract.MoneyDTO,
	riskExplanation *string,
) contract.AssistantRequestDTO {
	contextMap := map[string]any{
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
		contextMap["cashFlow30"] = map[string]any{
			"endingBalance":      map[string]any{"amount": estimatedMonthEnd.Amount, "currencyCode": "CNY"},
			"minimumBalance":     map[string]any{"amount": minimumBalance.Amount, "currencyCode": "CNY"},
			"minimumBalanceDate": "2026-08-15T00:00:00Z",
			"isBelowSafeBalance": true,
			"safeBalance":        map[string]any{"amount": safeBalance.Amount, "currencyCode": "CNY"},
		}
	}
	_ = riskExplanation
	return contract.AssistantRequestDTO{
		Question: "",
		Intent:   "unknown",
		Context:  contextMap,
	}
}

func ctxWithoutDebt(
	availableCash, estimatedMonthEnd contract.MoneyDTO,
	income, expense contract.MoneyDTO,
) contract.AssistantRequestDTO {
	return contract.AssistantRequestDTO{
		Question: "",
		Intent:   "unknown",
		Context: map[string]any{
			"meta": map[string]any{"currencyCode": "CNY"},
			"balance": map[string]any{
				"availableCash":     map[string]any{"amount": availableCash.Amount, "currencyCode": "CNY"},
				"estimatedMonthEnd": map[string]any{"amount": estimatedMonthEnd.Amount, "currencyCode": "CNY"},
			},
			"monthly": map[string]any{
				"income":  map[string]any{"amount": income.Amount, "currencyCode": "CNY"},
				"expense": map[string]any{"amount": expense.Amount, "currencyCode": "CNY"},
			},
			"spending": map[string]any{"topCategories": []any{}},
			"goals":    []any{},
			"budgets":  []any{},
		},
	}
}
