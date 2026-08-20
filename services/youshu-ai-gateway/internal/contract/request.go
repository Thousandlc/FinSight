package contract

type MoneyDTO struct {
	Amount       string `json:"amount"`
	CurrencyCode string `json:"currencyCode"`
}

type AssistantRequestDTO struct {
	Question string                      `json:"question"`
	Intent   string                      `json:"intent"`
	Context  map[string]any              `json:"context"`
}

type MonthlySummaryFactsDTO struct {
	AvailableCash              MoneyDTO `json:"availableCash"`
	MonthlyIncome              MoneyDTO `json:"monthlyIncome"`
	MonthlyExpense             MoneyDTO `json:"monthlyExpense"`
	MonthlyDebtPayment         MoneyDTO `json:"monthlyDebtPayment"`
	DebtPaymentToIncomePercent *string  `json:"debtPaymentToIncomePercent,omitempty"`
	PrimaryPressure            string   `json:"primaryPressure"`
	EstimatedMonthEndBalance   MoneyDTO `json:"estimatedMonthEndBalance"`
	CashFlowRiskExplanation    *string  `json:"cashFlowRiskExplanation,omitempty"`
	SafeBalance                *MoneyDTO `json:"safeBalance,omitempty"`
	MinimumBalance             *MoneyDTO `json:"minimumBalance,omitempty"`
	DebtPressureLevel          *string   `json:"debtPressureLevel,omitempty"`
	SourceLabels               []string `json:"sourceLabels"`
}

type RequestEnvelope struct {
	SchemaVersion           string                       `json:"schemaVersion"`
	RequestID               string                       `json:"requestId"`
	Operation               string                       `json:"operation"`
	AssistantRequest        AssistantRequestDTO          `json:"assistantRequest"`
	MonthlySummaryFacts     *MonthlySummaryFactsDTO      `json:"monthlySummaryFacts,omitempty"`
	FinancialRiskAssessment *FinancialRiskAssessmentDTO  `json:"financialRiskAssessment,omitempty"`
}

const (
	OperationMonthlySummary    = "monthlySummary"
	OperationAsk               = "ask"
	OperationInsight           = "insight"
	OperationPurchaseScenario  = "purchaseScenario"
)
