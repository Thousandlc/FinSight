import Foundation
import YoushuDomain
import YoushuFoundation

/// Deterministic policy inputs mirroring Go eval case envelope semantics (29/29).
enum EvalCasePolicyInputs {
    static let allCaseIDs: [String] = [
        "A01_healthy_cashflow",
        "A02_high_income_low_expense",
        "A03_balanced_budget",
        "A04_mild_month_end_pressure",
        "B01_minimum_below_safe",
        "B02_month_end_below_safe",
        "B03_month_end_near_zero",
        "B04_short_term_negative_balance",
        "C01_no_debt",
        "C02_low_debt_pressure",
        "C03_high_monthly_payment",
        "C04_multiple_debts",
        "C05_high_dti",
        "C06_debt_but_adequate_cashflow",
        "D01_high_expense_month",
        "D02_zero_income_month",
        "D03_income_decline",
        "D04_expense_increase",
        "E01_partial_debt_data",
        "E02_no_cashflow_projection",
        "E03_no_budget",
        "E04_partial_facts_missing",
        "E05_missing_debt_data",
        "F01_all_amounts_zero",
        "F02_tiny_balance",
        "F03_large_amounts",
        "F04_decimal_amounts",
        "F05_same_amount_multiple_facts",
        "F06_no_warning_expected",
    ]

    static let productionWiredCaseIDs: Set<String> = [
        "C01_no_debt",
        "E01_partial_debt_data",
        "E05_missing_debt_data",
    ]

    static func policyVectorID(for caseID: String) -> String? {
        switch caseID {
        case "A01_healthy_cashflow", "F06_no_warning_expected":
            return "V1"
        case "B01_minimum_below_safe":
            return "V2"
        case "B04_short_term_negative_balance":
            return "V3"
        case "C04_multiple_debts":
            return "V5"
        case "C05_high_dti":
            return "V9"
        case "C06_debt_but_adequate_cashflow":
            return "V16"
        case "D02_zero_income_month":
            return "V10"
        case "F01_all_amounts_zero":
            return "V11"
        default:
            return nil
        }
    }

    static func generationPath(for caseID: String) -> String {
        if productionWiredCaseIDs.contains(caseID) {
            return "FinancialRiskEvaluationGoldenSupport.productionAssessment → FinancialRiskAssessmentRequestMapper.toDTO"
        }
        if caseID == "C03_high_monthly_payment" {
            return "FinancialRiskEvaluationGoldenSupport.evalC03PolicyInput → FinancialRiskPolicyEngine.evaluate → FinancialRiskAssessmentRequestMapper.toDTO"
        }
        if let vectorID = policyVectorID(for: caseID) {
            return "FinancialRiskPolicyVectorInputs.\(vectorID) → FinancialRiskPolicyEngine.evaluate → FinancialRiskAssessmentRequestMapper.toDTO"
        }
        return "EvalCasePolicyInputs.evalPolicyInput → FinancialRiskPolicyEngine.evaluate → FinancialRiskAssessmentRequestMapper.toDTO"
    }

    static func evalPolicyInput(for caseID: String) -> FinancialRiskPolicyInput? {
        if productionWiredCaseIDs.contains(caseID) || caseID == "C03_high_monthly_payment" {
            return nil
        }
        if let vectorID = policyVectorID(for: caseID),
           let input = FinancialRiskPolicyVectorInputs.input(for: vectorID) {
            return input
        }
        switch caseID {
        case "A02_high_income_low_expense":
            return input(
                minimum: 8000, safe: 5000, monthEnd: 30000,
                income: 50000, expense: 8000, dti: 6,
                debtPressure: nil, debtState: .knownDebt
            )
        case "A03_balanced_budget":
            return input(
                minimum: 2500, safe: 2000, monthEnd: 8500,
                income: 8000, expense: 9500, dti: 19,
                debtPressure: nil, debtState: .knownDebt
            )
        case "A04_mild_month_end_pressure":
            return input(
                minimum: 2800, safe: 3000, monthEnd: 9000,
                income: 6000, expense: 8500, dti: 33,
                debtPressure: nil, debtState: .knownDebt
            )
        case "B02_month_end_below_safe":
            return input(
                minimum: 3000, safe: 5000, monthEnd: 2500,
                income: 9000, expense: 8000, dti: 22,
                debtPressure: nil, debtState: .knownDebt
            )
        case "B03_month_end_near_zero":
            return input(
                minimum: 200, safe: 1000, monthEnd: 100,
                income: 6000, expense: 5800, dti: 25,
                debtPressure: nil, debtState: .knownDebt
            )
        case "C02_low_debt_pressure":
            return input(
                minimum: 15000, safe: nil, monthEnd: 18000,
                income: 15000, expense: 8000, dti: 10,
                debtPressure: nil, debtState: .knownDebt
            )
        case "D01_high_expense_month":
            return input(
                minimum: nil, safe: nil, monthEnd: 1200,
                income: 10000, expense: 9800, dti: 20,
                debtPressure: nil, debtState: .knownDebt
            )
        case "D03_income_decline":
            return input(
                minimum: nil, safe: nil, monthEnd: 4500,
                income: 5000, expense: 5500, dti: 40,
                debtPressure: nil, debtState: .knownDebt
            )
        case "D04_expense_increase":
            return input(
                minimum: nil, safe: nil, monthEnd: 5500,
                income: 10000, expense: 9500, dti: 20,
                debtPressure: nil, debtState: .knownDebt
            )
        case "E02_no_cashflow_projection":
            return FinancialRiskPolicyInput(
                minimumBalance: .missing(),
                safeBalance: .known(money(2000)),
                estimatedMonthEndBalance: .missing(),
                monthlyIncome: .known(money(8000)),
                monthlyExpense: .known(money(6000)),
                debtDataState: .knownDebt,
                dataCompleteness: completeness(
                    debt: .known,
                    cashFlow: .missing,
                    unknowns: [.cashFlowProjectionMissing]
                ),
                evaluatedAt: evaluatedAt
            )
        case "E03_no_budget":
            return input(
                minimum: nil, safe: nil, monthEnd: 1500,
                income: 7000, expense: 6500, dti: 21,
                debtPressure: nil, debtState: .knownDebt
            )
        case "E04_partial_facts_missing":
            return FinancialRiskPolicyInput(
                minimumBalance: .missing(),
                safeBalance: .missing(),
                estimatedMonthEndBalance: .known(money(1000)),
                monthlyIncome: .known(money(6000)),
                monthlyExpense: .known(money(5500)),
                debtPaymentToIncomePercent: .known(17),
                debtDataState: .knownDebt,
                dataCompleteness: completeness(debt: .known, cashFlow: .known),
                evaluatedAt: evaluatedAt
            )
        case "F02_tiny_balance":
            return input(
                minimum: nil, safe: nil, monthEnd: Decimal(string: "0.01")!,
                income: 100, expense: Decimal(string: "99.99")!, dti: nil,
                debtPressure: nil, debtState: .knownDebt
            )
        case "F03_large_amounts":
            return input(
                minimum: 800000, safe: 500000, monthEnd: 900000,
                income: 500000, expense: 200000, dti: 20,
                debtPressure: nil, debtState: .knownDebt
            )
        case "F04_decimal_amounts":
            return input(
                minimum: nil, safe: nil, monthEnd: Decimal(string: "1111.11")!,
                income: Decimal(string: "5678.90")!, expense: Decimal(string: "3456.78")!, dti: 2,
                debtPressure: nil, debtState: .knownDebt
            )
        case "F05_same_amount_multiple_facts":
            return input(
                minimum: nil, safe: nil, monthEnd: 5000,
                income: 5000, expense: 3000, dti: 40,
                debtPressure: nil, debtState: .knownDebt
            )
        default:
            return nil
        }
    }

    private static var evaluatedAt: Date {
        FinancialRiskPolicyVectorInputs.fixedEvaluatedAt
    }

    private static func money(_ amount: Decimal) -> Money {
        Money(amount: amount, currencyCode: "CNY")
    }

    private static func completeness(
        debt: FieldAvailability = .known,
        cashFlow: FieldAvailability = .known,
        unknowns: [FinancialRiskReasonCode] = []
    ) -> FinancialDataCompleteness {
        FinancialDataCompleteness(
            debt: debt,
            cashFlowProjection: cashFlow,
            income: .known,
            expense: .known,
            requiredUnknownReasonCodes: unknowns
        )
    }

    private static func input(
        minimum: Decimal?,
        safe: Decimal?,
        monthEnd: Decimal,
        income: Decimal,
        expense: Decimal,
        dti: Decimal?,
        debtPressure: DebtPressureLevel?,
        debtState: DebtDataState
    ) -> FinancialRiskPolicyInput {
        FinancialRiskPolicyInput(
            minimumBalance: balanceField(minimum),
            safeBalance: balanceField(safe),
            estimatedMonthEndBalance: .known(money(monthEnd)),
            monthlyIncome: .known(money(income)),
            monthlyExpense: .known(money(expense)),
            debtPaymentToIncomePercent: dti.map { .known($0) } ?? .missing,
            debtPressureLevel: debtPressure,
            debtDataState: debtState,
            dataCompleteness: completeness(debt: debtState == .partial ? .partial : .known),
            evaluatedAt: evaluatedAt
        )
    }

    private static func balanceField(_ amount: Decimal?) -> PolicyMoneyField {
        guard let amount else {
            return .missing()
        }
        return .known(money(amount))
    }
}
