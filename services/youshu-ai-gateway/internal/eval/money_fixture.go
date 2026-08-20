package eval

import "fmt"

// MoneyAvailability describes evaluation-only money field semantics.
// "0" = known zero; non-zero = known value; MoneyMissing = genuinely absent/unavailable.
type MoneyAvailability string
const (
	MoneyKnownValue MoneyAvailability = "knownValue"
	MoneyKnownZero  MoneyAvailability = "knownZero"
	MoneyMissing    MoneyAvailability = "missing"
)

// EvalMoneyField tracks evaluation-only availability for a money fact.
type EvalMoneyField struct {
	Availability MoneyAvailability
}

// EvalFactOverlay holds evaluation-only fact availability overrides.
// Production MonthlySummaryFacts DTO cannot express optional money fields;
// overlay is the source of truth for semantics checkers.
type EvalFactOverlay struct {
	MonthlyDebtPayment EvalMoneyField
}

// ResolveDebtPaymentAvailability returns the evaluation semantics for monthly debt payment.
func ResolveDebtPaymentAvailability(c EvaluationCase) MoneyAvailability {
	if c.FactOverlay.MonthlyDebtPayment.Availability != "" {
		return c.FactOverlay.MonthlyDebtPayment.Availability
	}
	if c.Envelope.MonthlySummaryFacts == nil {
		return MoneyMissing
	}
	amount := c.Envelope.MonthlySummaryFacts.MonthlyDebtPayment.Amount
	if isKnownZeroAmount(amount) {
		return MoneyKnownZero
	}
	return MoneyKnownValue
}

// ValidateMoneyOverlay ensures overlay semantics match stored fixture values.
func ValidateMoneyOverlay(c EvaluationCase) error {
	if c.Envelope.MonthlySummaryFacts == nil {
		return nil
	}
	avail := ResolveDebtPaymentAvailability(c)
	amount := c.Envelope.MonthlySummaryFacts.MonthlyDebtPayment.Amount

	if c.FactOverlay.MonthlyDebtPayment.Availability == "" && amount == "" {
		return fmt.Errorf("case %s: absent debt amount must use MoneyMissing overlay", c.ID)
	}

	switch avail {
	case MoneyMissing:
		if amount != "" {
			return fmt.Errorf("case %s: missing debt overlay must not set a known amount", c.ID)
		}
	case MoneyKnownZero:
		if !isKnownZeroAmount(amount) {
			return fmt.Errorf("case %s: known-zero debt overlay requires amount 0", c.ID)
		}
	case MoneyKnownValue:
		if amount == "" || isKnownZeroAmount(amount) {
			return fmt.Errorf("case %s: known-value debt overlay requires non-zero amount", c.ID)
		}
	}
	return nil
}
