package eval

import (
	"fmt"
	"strconv"
	"strings"

	"github.com/youshu/youshu-ai-gateway/internal/contract"
	"github.com/youshu/youshu-ai-gateway/internal/factpack"
)

// Production E01 scenario mirrors FinancialRiskEvaluationGoldenSupport.productionE01Assessment:
// income 10_000, repayment 2_500 → DTI 25% via FinancialContextBuilder formula.
const (
	e01ProductionMonthlyIncome      = "10000"
	e01ProductionMonthlyDebtPayment = "2500"
	e01ProductionDTIPercent         = "25"
)

// ProductionLikeMonthlySummaryFacts returns request facts aligned with golden assessment provenance.
func ProductionLikeMonthlySummaryFacts(c EvaluationCase) (*contract.MonthlySummaryFactsDTO, error) {
	if c.Envelope.MonthlySummaryFacts == nil {
		return nil, fmt.Errorf("case %s missing monthlySummaryFacts", c.ID)
	}
	facts := *c.Envelope.MonthlySummaryFacts
	switch c.ID {
	case E01DiagnosticCaseID:
		if err := validateE01DTIParity(&facts); err != nil {
			return nil, err
		}
	}
	if err := factpack.ValidateRiskSourceFactAvailability(&c.Assessment, &facts); err != nil {
		return nil, fmt.Errorf("case %s production-like facts: %w", c.ID, err)
	}
	return &facts, nil
}

// CanonicalDTIPercentString computes DTI using the same formula as FinancialContextBuilder:
// (monthlyDebtPayment * 100) / monthlyIncome when income > 0.
func CanonicalDTIPercentString(monthlyDebtPayment, monthlyIncome string) (string, bool) {
	payment, err := parseMoneyAmount(monthlyDebtPayment)
	if err != nil {
		return "", false
	}
	income, err := parseMoneyAmount(monthlyIncome)
	if err != nil || income <= 0 {
		return "", false
	}
	ratio := (payment * 100) / income
	if ratio <= 0 {
		return "", false
	}
	formatted := strconv.FormatFloat(ratio, 'f', -1, 64)
	return formatted, true
}

func validateE01DTIParity(facts *contract.MonthlySummaryFactsDTO) error {
	if facts.MonthlyIncome.Amount != e01ProductionMonthlyIncome {
		return fmt.Errorf("E01 income=%s want %s", facts.MonthlyIncome.Amount, e01ProductionMonthlyIncome)
	}
	if facts.MonthlyDebtPayment.Amount != e01ProductionMonthlyDebtPayment {
		return fmt.Errorf("E01 debtPayment=%s want %s", facts.MonthlyDebtPayment.Amount, e01ProductionMonthlyDebtPayment)
	}
	want, ok := CanonicalDTIPercentString(facts.MonthlyDebtPayment.Amount, facts.MonthlyIncome.Amount)
	if !ok {
		return fmt.Errorf("E01 canonical DTI unavailable from income/debt payment")
	}
	if want != e01ProductionDTIPercent {
		return fmt.Errorf("E01 canonical DTI=%s want %s", want, e01ProductionDTIPercent)
	}
	if facts.DebtPaymentToIncomePercent == nil {
		return fmt.Errorf("E01 missing debtPaymentToIncomePercent fact registration")
	}
	if strings.TrimSpace(*facts.DebtPaymentToIncomePercent) != e01ProductionDTIPercent {
		return fmt.Errorf("E01 fact DTI=%s want %s", strings.TrimSpace(*facts.DebtPaymentToIncomePercent), e01ProductionDTIPercent)
	}
	return nil
}

func parseMoneyAmount(raw string) (float64, error) {
	return strconv.ParseFloat(strings.TrimSpace(raw), 64)
}
