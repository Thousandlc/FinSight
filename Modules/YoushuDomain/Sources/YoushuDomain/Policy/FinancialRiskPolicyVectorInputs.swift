import Foundation
import YoushuFoundation

/// Deterministic inputs for V1–V16 catalog vectors (test + spec validation fixtures).
public enum FinancialRiskPolicyVectorInputs {
    public static let fixedEvaluatedAt: Date = {
        ISO8601DateFormatter().date(from: "2026-08-16T06:00:00Z")!
    }()

    public static func input(for vectorID: String) -> FinancialRiskPolicyInput? {
        switch vectorID {
        case "V1": return v1HealthyComplete
        case "V2": return v2MinBelowSafe
        case "V3": return v3MinNegative
        case "V4": return v4MinNegativeBelowSafe
        case "V5": return v5DebtHigh
        case "V6": return v6DebtCritical
        case "V7": return v7DTI199
        case "V8": return v8DTI20
        case "V9": return v9DTI55
        case "V10": return v10ZeroIncomeExpense
        case "V11": return v11ZeroIncomeZeroExpense
        case "V12": return v12KnownNoDebt
        case "V13": return v13PartialDebtDTI20
        case "V14": return v14MissingDebt
        case "V15": return v15SafeCashMissingDebt
        case "V16": return v16CriticalDebtSafeCash
        default: return nil
        }
    }

    private static func baseCompleteness(
        debt: FieldAvailability = .known,
        cashFlow: FieldAvailability = .known,
        income: FieldAvailability = .known,
        expense: FieldAvailability = .known,
        unknowns: [FinancialRiskReasonCode] = []
    ) -> FinancialDataCompleteness {
        FinancialDataCompleteness(
            debt: debt,
            cashFlowProjection: cashFlow,
            income: income,
            expense: expense,
            requiredUnknownReasonCodes: unknowns
        )
    }

    private static var v1HealthyComplete: FinancialRiskPolicyInput {
        FinancialRiskPolicyInput(
            minimumBalance: .known(money(4500)),
            safeBalance: .known(money(3000)),
            estimatedMonthEndBalance: .known(money(8000)),
            monthlyIncome: .known(money(12000)),
            monthlyExpense: .known(money(6000)),
            debtPaymentToIncomePercent: .known(10),
            debtPressureLevel: .low,
            debtDataState: .knownDebt,
            dataCompleteness: baseCompleteness(),
            evaluatedAt: fixedEvaluatedAt
        )
    }

    private static var v2MinBelowSafe: FinancialRiskPolicyInput {
        FinancialRiskPolicyInput(
            minimumBalance: .known(money(800)),
            safeBalance: .known(money(2000)),
            estimatedMonthEndBalance: .known(money(1200)),
            monthlyIncome: .known(money(8000)),
            monthlyExpense: .known(money(7000)),
            debtPaymentToIncomePercent: .known(10),
            debtDataState: .knownDebt,
            dataCompleteness: baseCompleteness(),
            evaluatedAt: fixedEvaluatedAt
        )
    }

    private static var v3MinNegative: FinancialRiskPolicyInput {
        FinancialRiskPolicyInput(
            minimumBalance: .known(money(-500)),
            safeBalance: .known(money(2000)),
            estimatedMonthEndBalance: .known(money(-200)),
            monthlyIncome: .known(money(8000)),
            monthlyExpense: .known(money(7000)),
            debtDataState: .knownDebt,
            dataCompleteness: baseCompleteness(),
            evaluatedAt: fixedEvaluatedAt
        )
    }

    private static var v4MinNegativeBelowSafe: FinancialRiskPolicyInput {
        v3MinNegative
    }

    private static var v5DebtHigh: FinancialRiskPolicyInput {
        FinancialRiskPolicyInput(
            minimumBalance: .known(money(6000)),
            safeBalance: .known(money(2000)),
            estimatedMonthEndBalance: .known(money(7000)),
            monthlyIncome: .known(money(10000)),
            monthlyExpense: .known(money(5000)),
            debtPaymentToIncomePercent: .known(25),
            debtPressureLevel: .high,
            debtDataState: .knownDebt,
            dataCompleteness: baseCompleteness(),
            evaluatedAt: fixedEvaluatedAt
        )
    }

    private static var v6DebtCritical: FinancialRiskPolicyInput {
        FinancialRiskPolicyInput(
            minimumBalance: .known(money(5000)),
            safeBalance: .known(money(2000)),
            estimatedMonthEndBalance: .known(money(6000)),
            monthlyIncome: .known(money(10000)),
            monthlyExpense: .known(money(5000)),
            debtPressureLevel: .critical,
            debtDataState: .knownDebt,
            dataCompleteness: baseCompleteness(),
            evaluatedAt: fixedEvaluatedAt
        )
    }

    private static var v7DTI199: FinancialRiskPolicyInput {
        FinancialRiskPolicyInput(
            minimumBalance: .known(money(5000)),
            safeBalance: .known(money(2000)),
            estimatedMonthEndBalance: .known(money(6000)),
            monthlyIncome: .known(money(10000)),
            monthlyExpense: .known(money(5000)),
            debtPaymentToIncomePercent: .known(Decimal(string: "19.9")!),
            debtDataState: .knownDebt,
            dataCompleteness: baseCompleteness(),
            evaluatedAt: fixedEvaluatedAt
        )
    }

    private static var v8DTI20: FinancialRiskPolicyInput {
        FinancialRiskPolicyInput(
            minimumBalance: .known(money(5000)),
            safeBalance: .known(money(2000)),
            estimatedMonthEndBalance: .known(money(6000)),
            monthlyIncome: .known(money(10000)),
            monthlyExpense: .known(money(5000)),
            debtPaymentToIncomePercent: .known(20),
            debtDataState: .knownDebt,
            dataCompleteness: baseCompleteness(),
            evaluatedAt: fixedEvaluatedAt
        )
    }

    private static var v9DTI55: FinancialRiskPolicyInput {
        FinancialRiskPolicyInput(
            minimumBalance: .known(money(5000)),
            safeBalance: .known(money(2000)),
            estimatedMonthEndBalance: .known(money(6000)),
            monthlyIncome: .known(money(10000)),
            monthlyExpense: .known(money(5000)),
            debtPaymentToIncomePercent: .known(55),
            debtPressureLevel: .medium,
            debtDataState: .knownDebt,
            dataCompleteness: baseCompleteness(),
            evaluatedAt: fixedEvaluatedAt
        )
    }

    private static var v10ZeroIncomeExpense: FinancialRiskPolicyInput {
        FinancialRiskPolicyInput(
            minimumBalance: .known(money(8000)),
            safeBalance: .known(money(2000)),
            estimatedMonthEndBalance: .known(money(6500)),
            monthlyIncome: .known(money(0)),
            monthlyExpense: .known(money(4500)),
            debtDataState: .knownDebt,
            dataCompleteness: baseCompleteness(),
            evaluatedAt: fixedEvaluatedAt
        )
    }

    private static var v11ZeroIncomeZeroExpense: FinancialRiskPolicyInput {
        FinancialRiskPolicyInput(
            minimumBalance: .known(money(8000)),
            safeBalance: .known(money(2000)),
            estimatedMonthEndBalance: .known(money(8000)),
            monthlyIncome: .known(money(0)),
            monthlyExpense: .known(money(0)),
            debtDataState: .knownDebt,
            dataCompleteness: baseCompleteness(),
            evaluatedAt: fixedEvaluatedAt
        )
    }

    private static var v12KnownNoDebt: FinancialRiskPolicyInput {
        FinancialRiskPolicyInput(
            minimumBalance: .known(money(10000)),
            safeBalance: .known(money(3000)),
            estimatedMonthEndBalance: .known(money(12000)),
            monthlyIncome: .known(money(12000)),
            monthlyExpense: .known(money(6000)),
            debtPaymentToIncomePercent: .known(50),
            debtPressureLevel: .critical,
            debtDataState: .knownNoDebt,
            dataCompleteness: baseCompleteness(debt: .known),
            evaluatedAt: fixedEvaluatedAt
        )
    }

    private static var v13PartialDebtDTI20: FinancialRiskPolicyInput {
        FinancialRiskPolicyInput(
            minimumBalance: .known(money(2000)),
            safeBalance: .known(money(2000)),
            estimatedMonthEndBalance: .known(money(2200)),
            monthlyIncome: .known(money(5000)),
            monthlyExpense: .known(money(4500)),
            debtPaymentToIncomePercent: .known(20),
            debtDataState: .partial,
            dataCompleteness: baseCompleteness(debt: .partial),
            evaluatedAt: fixedEvaluatedAt
        )
    }

    private static var v14MissingDebt: FinancialRiskPolicyInput {
        FinancialRiskPolicyInput(
            minimumBalance: .known(money(2500)),
            safeBalance: .known(money(2000)),
            estimatedMonthEndBalance: .known(money(2200)),
            monthlyIncome: .known(money(6000)),
            monthlyExpense: .known(money(4800)),
            debtPaymentToIncomePercent: .missing,
            debtDataState: .missing,
            dataCompleteness: baseCompleteness(debt: .missing),
            evaluatedAt: fixedEvaluatedAt
        )
    }

    private static var v15SafeCashMissingDebt: FinancialRiskPolicyInput {
        v14MissingDebt
    }

    private static var v16CriticalDebtSafeCash: FinancialRiskPolicyInput {
        FinancialRiskPolicyInput(
            minimumBalance: .known(money(15000)),
            safeBalance: .known(money(5000)),
            estimatedMonthEndBalance: .known(money(18000)),
            monthlyIncome: .known(money(15000)),
            monthlyExpense: .known(money(8000)),
            debtPressureLevel: .critical,
            debtDataState: .knownDebt,
            dataCompleteness: baseCompleteness(),
            evaluatedAt: fixedEvaluatedAt
        )
    }

    private static func money(_ amount: Decimal, currency: String = "CNY") -> Money {
        Money(amount: amount, currencyCode: currency)
    }
}
