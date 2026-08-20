import Foundation
import YoushuDomain
import YoushuFoundation

enum FinancialRiskTestFixtures {
    static let evaluatedAt = FinancialRiskPolicyVectorInputs.fixedEvaluatedAt

    static func safeKnownNoDebt() -> FinancialRiskAssessment {
        FinancialRiskAssessment(
            overallLevel: .safe,
            signals: [],
            dataCompleteness: FinancialDataCompleteness(
                debt: .known,
                cashFlowProjection: .known,
                income: .known,
                expense: .known,
                requiredUnknownReasonCodes: []
            ),
            debtDataState: .knownNoDebt,
            policyVersion: FinancialRiskPolicyVersion.current,
            evaluatedAt: evaluatedAt
        )
    }

    static func warningKnownDebtDTI() -> FinancialRiskAssessment {
        FinancialRiskAssessment(
            overallLevel: .warning,
            signals: [
                FinancialRiskSignal(
                    kind: .debt,
                    level: .warning,
                    reasonCode: .highDebtPaymentToIncome,
                    sourceFactKeys: ["debtPaymentToIncomePercent"],
                    recommendedActionDestinations: [.debt, .cashFlow]
                ),
            ],
            dataCompleteness: FinancialDataCompleteness(
                debt: .known,
                cashFlowProjection: .known,
                income: .known,
                expense: .known,
                requiredUnknownReasonCodes: []
            ),
            debtDataState: .knownDebt,
            policyVersion: FinancialRiskPolicyVersion.current,
            evaluatedAt: evaluatedAt
        )
    }

    static func missingDebtInventory() -> FinancialRiskAssessment {
        FinancialRiskAssessment(
            overallLevel: .safe,
            signals: [],
            dataCompleteness: FinancialDataCompleteness(
                debt: .missing,
                cashFlowProjection: .known,
                income: .known,
                expense: .known,
                requiredUnknownReasonCodes: [.debtDataMissing]
            ),
            debtDataState: .missing,
            policyVersion: FinancialRiskPolicyVersion.current,
            evaluatedAt: evaluatedAt
        )
    }

    static func riskNegativeProjectedBalance() -> FinancialRiskAssessment {
        FinancialRiskAssessment(
            overallLevel: .risk,
            signals: [
                FinancialRiskSignal(
                    kind: .cashFlow,
                    level: .risk,
                    reasonCode: .negativeProjectedBalance,
                    sourceFactKeys: ["minimumBalance"],
                    recommendedActionDestinations: [.cashFlow]
                ),
            ],
            dataCompleteness: FinancialDataCompleteness(
                debt: .known,
                cashFlowProjection: .known,
                income: .known,
                expense: .known,
                requiredUnknownReasonCodes: []
            ),
            debtDataState: .knownDebt,
            policyVersion: FinancialRiskPolicyVersion.current,
            evaluatedAt: evaluatedAt
        )
    }

    static func warningZeroIncomeWithExpenses() -> FinancialRiskAssessment {
        FinancialRiskAssessment(
            overallLevel: .warning,
            signals: [
                FinancialRiskSignal(
                    kind: .incomeExpense,
                    level: .warning,
                    reasonCode: .zeroIncomeWithExpenses,
                    sourceFactKeys: ["monthlyIncome", "monthlyExpense"],
                    recommendedActionDestinations: [.transactions, .cashFlow]
                ),
            ],
            dataCompleteness: FinancialDataCompleteness(
                debt: .known,
                cashFlowProjection: .known,
                income: .known,
                expense: .known,
                requiredUnknownReasonCodes: []
            ),
            debtDataState: .knownDebt,
            policyVersion: FinancialRiskPolicyVersion.current,
            evaluatedAt: evaluatedAt
        )
    }

    static func warningDebtPressureHigh() -> FinancialRiskAssessment {
        FinancialRiskAssessment(
            overallLevel: .warning,
            signals: [
                FinancialRiskSignal(
                    kind: .debt,
                    level: .warning,
                    reasonCode: .highDebtPressureScore,
                    sourceFactKeys: ["debtPressureLevel"],
                    recommendedActionDestinations: [.debt, .cashFlow]
                ),
            ],
            dataCompleteness: FinancialDataCompleteness(
                debt: .known,
                cashFlowProjection: .known,
                income: .known,
                expense: .known,
                requiredUnknownReasonCodes: []
            ),
            debtDataState: .knownDebt,
            policyVersion: FinancialRiskPolicyVersion.current,
            evaluatedAt: evaluatedAt
        )
    }

    static func riskDebtPressureCritical() -> FinancialRiskAssessment {
        FinancialRiskAssessment(
            overallLevel: .risk,
            signals: [
                FinancialRiskSignal(
                    kind: .debt,
                    level: .risk,
                    reasonCode: .criticalDebtPressure,
                    sourceFactKeys: ["debtPressureLevel"],
                    recommendedActionDestinations: [.debt, .cashFlow]
                ),
            ],
            dataCompleteness: FinancialDataCompleteness(
                debt: .known,
                cashFlowProjection: .known,
                income: .known,
                expense: .known,
                requiredUnknownReasonCodes: []
            ),
            debtDataState: .knownDebt,
            policyVersion: FinancialRiskPolicyVersion.current,
            evaluatedAt: evaluatedAt
        )
    }

    static func warningCashFlowBelowSafe() -> FinancialRiskAssessment {
        FinancialRiskAssessment(
            overallLevel: .warning,
            signals: [
                FinancialRiskSignal(
                    kind: .cashFlow,
                    level: .warning,
                    reasonCode: .cashFlowBelowSafeBalance,
                    sourceFactKeys: ["minimumBalance", "safeBalance"],
                    recommendedActionDestinations: [.cashFlow]
                ),
            ],
            dataCompleteness: FinancialDataCompleteness(
                debt: .known,
                cashFlowProjection: .known,
                income: .known,
                expense: .known,
                requiredUnknownReasonCodes: []
            ),
            debtDataState: .knownDebt,
            policyVersion: FinancialRiskPolicyVersion.current,
            evaluatedAt: evaluatedAt
        )
    }

    static func warningMonthEndBelowSafe() -> FinancialRiskAssessment {
        FinancialRiskAssessment(
            overallLevel: .warning,
            signals: [
                FinancialRiskSignal(
                    kind: .cashFlow,
                    level: .warning,
                    reasonCode: .monthEndBelowSafeBalance,
                    sourceFactKeys: ["estimatedMonthEndBalance", "safeBalance"],
                    recommendedActionDestinations: [.cashFlow]
                ),
            ],
            dataCompleteness: FinancialDataCompleteness(
                debt: .known,
                cashFlowProjection: .known,
                income: .known,
                expense: .known,
                requiredUnknownReasonCodes: []
            ),
            debtDataState: .knownDebt,
            policyVersion: FinancialRiskPolicyVersion.current,
            evaluatedAt: evaluatedAt
        )
    }

    static func factsForDTIWarning() -> MonthlySummaryFacts {
        MonthlySummaryFacts(
            availableCash: Money(amount: 1_000, currencyCode: "CNY"),
            monthlyIncome: Money(amount: 5_000, currencyCode: "CNY"),
            monthlyExpense: Money(amount: 3_000, currencyCode: "CNY"),
            monthlyDebtPayment: Money(amount: 500, currencyCode: "CNY"),
            debtPaymentToIncomePercent: 25,
            primaryPressure: "债务还款",
            estimatedMonthEndBalance: Money(amount: 1_500, currencyCode: "CNY"),
            sourceLabels: ["Account"]
        )
    }

    static func factsForDebtPressureHigh() -> MonthlySummaryFacts {
        MonthlySummaryFacts(
            availableCash: Money(amount: 1_000, currencyCode: "CNY"),
            monthlyIncome: Money(amount: 5_000, currencyCode: "CNY"),
            monthlyExpense: Money(amount: 3_000, currencyCode: "CNY"),
            monthlyDebtPayment: Money(amount: 500, currencyCode: "CNY"),
            debtPaymentToIncomePercent: nil,
            primaryPressure: "债务还款",
            estimatedMonthEndBalance: Money(amount: 1_500, currencyCode: "CNY"),
            debtPressureLevel: .high,
            sourceLabels: ["Account", "Debt"]
        )
    }

    static func factsForNegativeProjectedBalance() -> MonthlySummaryFacts {
        MonthlySummaryFacts(
            availableCash: Money(amount: 1_000, currencyCode: "CNY"),
            monthlyIncome: Money(amount: 5_000, currencyCode: "CNY"),
            monthlyExpense: Money(amount: 3_000, currencyCode: "CNY"),
            monthlyDebtPayment: Money(amount: 500, currencyCode: "CNY"),
            debtPaymentToIncomePercent: nil,
            primaryPressure: "未来现金流风险",
            estimatedMonthEndBalance: Money(amount: 1_500, currencyCode: "CNY"),
            safeBalance: Money(amount: 2_000, currencyCode: "CNY"),
            minimumBalance: Money(amount: -100, currencyCode: "CNY"),
            sourceLabels: ["Account", "CashFlow"]
        )
    }

    static func factsForZeroIncomeWithExpenses() -> MonthlySummaryFacts {
        MonthlySummaryFacts(
            availableCash: Money(amount: 500, currencyCode: "CNY"),
            monthlyIncome: Money(amount: 0, currencyCode: "CNY"),
            monthlyExpense: Money(amount: 1_200, currencyCode: "CNY"),
            monthlyDebtPayment: Money(amount: 0, currencyCode: "CNY"),
            debtPaymentToIncomePercent: nil,
            primaryPressure: "生活支出",
            estimatedMonthEndBalance: Money(amount: -700, currencyCode: "CNY"),
            sourceLabels: ["Account", "Transaction"]
        )
    }

    static func factsForMissingDebt() -> MonthlySummaryFacts {
        MonthlySummaryFacts(
            availableCash: Money(amount: 1_000, currencyCode: "CNY"),
            monthlyIncome: Money(amount: 4_000, currencyCode: "CNY"),
            monthlyExpense: Money(amount: 2_500, currencyCode: "CNY"),
            monthlyDebtPayment: Money(amount: 0, currencyCode: "CNY"),
            debtPaymentToIncomePercent: nil,
            primaryPressure: "日常支出",
            estimatedMonthEndBalance: Money(amount: 1_500, currencyCode: "CNY"),
            sourceLabels: ["Account", "Transaction"]
        )
    }
}
