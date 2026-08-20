package contract

type FinancialRiskSignalDTO struct {
	Kind                          string   `json:"kind"`
	Level                         string   `json:"level"`
	ReasonCode                    string   `json:"reasonCode"`
	SourceFactKeys                []string `json:"sourceFactKeys"`
	RecommendedActionDestinations []string `json:"recommendedActionDestinations"`
}

type FinancialDataCompletenessDTO struct {
	Debt                       string   `json:"debt"`
	CashFlowProjection         string   `json:"cashFlowProjection"`
	Income                     string   `json:"income"`
	Expense                    string   `json:"expense"`
	RequiredUnknownReasonCodes []string `json:"requiredUnknownReasonCodes"`
}

type FinancialRiskAssessmentDTO struct {
	OverallLevel    string                       `json:"overallLevel"`
	PolicyVersion   string                       `json:"policyVersion"`
	DebtDataState   string                       `json:"debtDataState"`
	Signals         []FinancialRiskSignalDTO     `json:"signals"`
	DataCompleteness FinancialDataCompletenessDTO `json:"dataCompleteness"`
}

// AllowedRiskReasonCodes mirrors FinancialRiskReasonCode.allCases in Swift Domain.
var AllowedRiskReasonCodes = []string{
	"cashFlowBelowSafeBalance",
	"negativeProjectedBalance",
	"monthEndBelowSafeBalance",
	"healthyCashBuffer",
	"highDebtPaymentToIncome",
	"criticalDebtPaymentToIncome",
	"highDebtPressureScore",
	"criticalDebtPressure",
	"repaymentConcern",
	"zeroIncomeWithExpenses",
	"expenseExceedsIncomeWithLowBuffer",
	"debtDataMissing",
	"debtDataPartial",
	"cashFlowProjectionMissing",
	"budgetNotApplicable",
}

// AllowedRiskSignalReasonCodes are reason codes that may appear on transport signals.
var AllowedRiskSignalReasonCodes = []string{
	"cashFlowBelowSafeBalance",
	"negativeProjectedBalance",
	"monthEndBelowSafeBalance",
	"healthyCashBuffer",
	"highDebtPaymentToIncome",
	"criticalDebtPaymentToIncome",
	"highDebtPressureScore",
	"criticalDebtPressure",
	"repaymentConcern",
	"zeroIncomeWithExpenses",
	"expenseExceedsIncomeWithLowBuffer",
}

// AllowedRiskSignalReasonCodesByPolicyVersion lists reason codes each policy version may emit as signals.
// Mirrors Swift FinancialRiskPolicySpecification.v1EmittedSignalReasonCodeRawValues — transport metadata only.
var AllowedRiskSignalReasonCodesByPolicyVersion = map[string][]string{
	"v1": {
		"cashFlowBelowSafeBalance",
		"negativeProjectedBalance",
		"monthEndBelowSafeBalance",
		"highDebtPaymentToIncome",
		"highDebtPressureScore",
		"criticalDebtPressure",
		"zeroIncomeWithExpenses",
	},
}

// KnownNoDebtIncompatibleSignalReasonCodes must not appear when debtDataState=knownNoDebt.
var KnownNoDebtIncompatibleSignalReasonCodes = []string{
	"highDebtPaymentToIncome",
	"criticalDebtPaymentToIncome",
	"highDebtPressureScore",
	"criticalDebtPressure",
	"repaymentConcern",
}

var AllowedRiskOverallLevels = []string{"safe", "warning", "risk"}
var AllowedRiskSignalLevels = []string{"warning", "risk"}
var AllowedRiskSignalKinds = []string{"cashFlow", "debt", "incomeExpense"}
var AllowedDebtDataStates = []string{"knownNoDebt", "knownDebt", "partial", "missing"}
var AllowedFieldAvailability = []string{"known", "partial", "missing", "notApplicable"}
var AllowedRiskActionDestinations = []string{"cashFlow", "debt", "transactions", "accounts"}

var DebtDataStateToCompletenessDebt = map[string]string{
	"knownNoDebt": "known",
	"knownDebt":   "known",
	"partial":     "partial",
	"missing":     "missing",
}
