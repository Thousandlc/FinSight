package factpack_test

import (
	"testing"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/factpack"
)

func TestValidateRiskSourceFactAvailabilityE01Pass(t *testing.T) {
	pct := "25"
	facts := &contract.MonthlySummaryFactsDTO{
		AvailableCash:              contract.MoneyDTO{Amount: "20000", CurrencyCode: "CNY"},
		MonthlyIncome:              contract.MoneyDTO{Amount: "10000", CurrencyCode: "CNY"},
		MonthlyExpense:             contract.MoneyDTO{Amount: "4500", CurrencyCode: "CNY"},
		MonthlyDebtPayment:           contract.MoneyDTO{Amount: "2500", CurrencyCode: "CNY"},
		DebtPaymentToIncomePercent:   &pct,
		PrimaryPressure:            "债务还款",
		EstimatedMonthEndBalance:   contract.MoneyDTO{Amount: "18000", CurrencyCode: "CNY"},
		SourceLabels:               []string{"Account"},
	}
	assessment := &contract.FinancialRiskAssessmentDTO{
		OverallLevel:  "warning",
		PolicyVersion: "v1",
		DebtDataState: "partial",
		Signals: []contract.FinancialRiskSignalDTO{{
			Kind: "debt", Level: "warning", ReasonCode: "highDebtPaymentToIncome",
			SourceFactKeys: []string{"debtPaymentToIncomePercent"},
		}},
	}
	if err := factpack.ValidateRiskSourceFactAvailability(assessment, facts); err != nil {
		t.Fatal(err)
	}
}

func TestValidateRiskSourceFactAvailabilityMismatchFails(t *testing.T) {
	facts := &contract.MonthlySummaryFactsDTO{
		AvailableCash:    contract.MoneyDTO{Amount: "2000", CurrencyCode: "CNY"},
		MonthlyIncome:    contract.MoneyDTO{Amount: "5000", CurrencyCode: "CNY"},
		MonthlyExpense:   contract.MoneyDTO{Amount: "4500", CurrencyCode: "CNY"},
		MonthlyDebtPayment: contract.MoneyDTO{Amount: "800", CurrencyCode: "CNY"},
	}
	assessment := &contract.FinancialRiskAssessmentDTO{
		OverallLevel:  "warning",
		PolicyVersion: "v1",
		DebtDataState: "partial",
		Signals: []contract.FinancialRiskSignalDTO{{
			Kind: "debt", Level: "warning", ReasonCode: "highDebtPaymentToIncome",
			SourceFactKeys: []string{"debtPaymentToIncomePercent"},
		}},
	}
	err := factpack.ValidateRiskSourceFactAvailability(assessment, facts)
	if err == nil {
		t.Fatal("expected mismatch failure")
	}
	if factpack.ParseRiskSourceFactAvailabilityFailureCode(err) != factpack.RiskSourceFactUnavailableCode {
		t.Fatalf("code=%s", factpack.ParseRiskSourceFactAvailabilityFailureCode(err))
	}
}

func TestValidateRiskSourceFactAvailabilityE05MissingDTIPass(t *testing.T) {
	facts := &contract.MonthlySummaryFactsDTO{
		AvailableCash:  contract.MoneyDTO{Amount: "2500", CurrencyCode: "CNY"},
		MonthlyIncome:  contract.MoneyDTO{Amount: "6000", CurrencyCode: "CNY"},
		MonthlyExpense: contract.MoneyDTO{Amount: "4800", CurrencyCode: "CNY"},
	}
	assessment := &contract.FinancialRiskAssessmentDTO{
		OverallLevel:  "safe",
		PolicyVersion: "v1",
		DebtDataState: "missing",
		Signals:       nil,
		DataCompleteness: contract.FinancialDataCompletenessDTO{
			Debt: "missing", CashFlowProjection: "known", Income: "known", Expense: "known",
			RequiredUnknownReasonCodes: []string{"debtDataMissing"},
		},
	}
	if err := factpack.ValidateRiskSourceFactAvailability(assessment, facts); err != nil {
		t.Fatal(err)
	}
}

func TestValidateRiskSourceFactAvailabilityZeroIncomeRegistered(t *testing.T) {
	facts := &contract.MonthlySummaryFactsDTO{
		AvailableCash:    contract.MoneyDTO{Amount: "8000", CurrencyCode: "CNY"},
		MonthlyIncome:    contract.MoneyDTO{Amount: "0", CurrencyCode: "CNY"},
		MonthlyExpense:   contract.MoneyDTO{Amount: "4500", CurrencyCode: "CNY"},
		MonthlyDebtPayment: contract.MoneyDTO{Amount: "1500", CurrencyCode: "CNY"},
	}
	assessment := &contract.FinancialRiskAssessmentDTO{
		OverallLevel:  "warning",
		PolicyVersion: "v1",
		DebtDataState: "knownDebt",
		Signals: []contract.FinancialRiskSignalDTO{{
			Kind: "incomeExpense", Level: "warning", ReasonCode: "zeroIncomeWithExpenses",
			SourceFactKeys: []string{"monthlyIncome", "monthlyExpense"},
		}},
	}
	if err := factpack.ValidateRiskSourceFactAvailability(assessment, facts); err != nil {
		t.Fatal(err)
	}
}

func TestStandardReferenceKeysDoesNotIncludeDTI(t *testing.T) {
	for _, key := range factpack.StandardReferenceKeys {
		if key == "debtPaymentToIncomePercent" {
			t.Fatal("DTI must remain dynamic fact-backed, not StandardReferenceKeys")
		}
	}
}
