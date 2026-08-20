import Foundation
import YoushuFoundation

/// Pure deterministic v1 financial risk policy engine.
public enum FinancialRiskPolicyEngine {
    public static func evaluate(_ input: FinancialRiskPolicyInput) -> FinancialRiskAssessment {
        var signals = evaluateRules(input)
        signals = FinancialRiskPolicyDedup.apply(signals)
        signals = FinancialRiskKnownZeroGuard.filterSignals(signals, debtState: input.debtDataState)
        signals = signals.map { $0.withSortedActions() }
        signals = FinancialRiskSignalOrdering.sortSignals(signals)

        let completeness = mergedCompleteness(input)
        let overall = FinancialRiskAggregation.aggregateOverallLevel(from: signals)

        return FinancialRiskAssessment(
            overallLevel: overall,
            signals: signals,
            dataCompleteness: completeness,
            debtDataState: input.debtDataState,
            policyVersion: FinancialRiskPolicyVersion.current,
            evaluatedAt: input.evaluatedAt
        )
    }

    // MARK: - Rule evaluation

    private static func evaluateRules(_ input: FinancialRiskPolicyInput) -> [FinancialRiskSignal] {
        var signals: [FinancialRiskSignal] = []
        signals.append(contentsOf: cashFlowSignals(input))
        signals.append(contentsOf: debtSignals(input))
        signals.append(contentsOf: incomeExpenseSignals(input))
        return signals
    }

    // MARK: - Cash flow

    private static func cashFlowSignals(_ input: FinancialRiskPolicyInput) -> [FinancialRiskSignal] {
        guard input.dataCompleteness.cashFlowProjection != .missing else { return [] }

        if input.minimumBalance.isKnown, let minimum = input.minimumBalance.value {
            if minimum.amount < 0 {
                return [
                    FinancialRiskSignal(
                        kind: .cashFlow,
                        level: .risk,
                        reasonCode: .negativeProjectedBalance,
                        sourceFactKeys: ["minimumBalance"],
                        recommendedActionDestinations: [.cashFlow]
                    ),
                ]
            }
            if minimum.amount >= 0,
               input.safeBalance.isKnown,
               let safe = input.safeBalance.value,
               minimum.amount < safe.amount {
                return [
                    FinancialRiskSignal(
                        kind: .cashFlow,
                        level: .warning,
                        reasonCode: .cashFlowBelowSafeBalance,
                        sourceFactKeys: ["minimumBalance", "safeBalance"],
                        recommendedActionDestinations: [.cashFlow]
                    ),
                ]
            }
            return []
        }

        guard input.estimatedMonthEndBalance.isKnown,
              let monthEnd = input.estimatedMonthEndBalance.value else {
            return []
        }

        if monthEnd.amount < 0 {
            return [
                FinancialRiskSignal(
                    kind: .cashFlow,
                    level: .risk,
                    reasonCode: .negativeProjectedBalance,
                    sourceFactKeys: ["estimatedMonthEndBalance"],
                    recommendedActionDestinations: [.cashFlow]
                ),
            ]
        }

        if monthEnd.amount >= 0,
           input.safeBalance.isKnown,
           let safe = input.safeBalance.value,
           monthEnd.amount < safe.amount {
            return [
                FinancialRiskSignal(
                    kind: .cashFlow,
                    level: .warning,
                    reasonCode: .monthEndBelowSafeBalance,
                    sourceFactKeys: ["estimatedMonthEndBalance", "safeBalance"],
                    recommendedActionDestinations: [.cashFlow]
                ),
            ]
        }

        return []
    }

    // MARK: - Debt

    private static func debtSignals(_ input: FinancialRiskPolicyInput) -> [FinancialRiskSignal] {
        switch input.debtDataState {
        case .knownNoDebt, .missing:
            return []
        case .partial:
            return dtiSignal(input)
        case .knownDebt:
            var signals: [FinancialRiskSignal] = []
            if let level = input.debtPressureLevel {
                switch level {
                case .low, .medium:
                    break
                case .high:
                    signals.append(
                        FinancialRiskSignal(
                            kind: .debt,
                            level: .warning,
                            reasonCode: .highDebtPressureScore,
                            sourceFactKeys: ["debtPressureLevel"],
                            recommendedActionDestinations: [.debt, .cashFlow]
                        )
                    )
                case .critical:
                    signals.append(
                        FinancialRiskSignal(
                            kind: .debt,
                            level: .risk,
                            reasonCode: .criticalDebtPressure,
                            sourceFactKeys: ["debtPressureLevel"],
                            recommendedActionDestinations: [.debt, .cashFlow]
                        )
                    )
                }
            }
            if let dti = dtiSignal(input).first {
                signals.append(dti)
            }
            return signals
        }
    }

    private static func dtiSignal(_ input: FinancialRiskPolicyInput) -> [FinancialRiskSignal] {
        guard input.debtDataState != .missing, input.debtDataState != .knownNoDebt else { return [] }
        guard input.debtPaymentToIncomePercent.isKnown,
              let dti = input.debtPaymentToIncomePercent.value else { return [] }
        guard input.monthlyIncome.isKnown,
              let income = input.monthlyIncome.value,
              income.amount > 0 else { return [] }
        guard FinancialRiskPolicyThresholdRegistry.isDTIWarningEligible(percent: dti, monthlyIncomeKnown: true) else {
            return []
        }
        return [
            FinancialRiskSignal(
                kind: .debt,
                level: .warning,
                reasonCode: .highDebtPaymentToIncome,
                sourceFactKeys: ["debtPaymentToIncomePercent"],
                recommendedActionDestinations: [.debt, .cashFlow]
            ),
        ]
    }

    // MARK: - Income / expense

    private static func incomeExpenseSignals(_ input: FinancialRiskPolicyInput) -> [FinancialRiskSignal] {
        guard input.dataCompleteness.income == .known,
              input.dataCompleteness.expense == .known,
              input.monthlyIncome.isKnown,
              input.monthlyExpense.isKnown,
              let income = input.monthlyIncome.value,
              let expense = input.monthlyExpense.value else {
            return []
        }
        guard income.amount == 0, expense.amount > 0 else { return [] }
        return [
            FinancialRiskSignal(
                kind: .incomeExpense,
                level: .warning,
                reasonCode: .zeroIncomeWithExpenses,
                sourceFactKeys: ["monthlyIncome", "monthlyExpense"],
                recommendedActionDestinations: [.transactions, .cashFlow]
            ),
        ]
    }

    // MARK: - Completeness

    private static func mergedCompleteness(_ input: FinancialRiskPolicyInput) -> FinancialDataCompleteness {
        var unknowns = input.dataCompleteness.requiredUnknownReasonCodes
        if input.debtDataState == .missing {
            appendUnknown(.debtDataMissing, to: &unknowns)
        }
        if input.dataCompleteness.cashFlowProjection == .missing {
            appendUnknown(.cashFlowProjectionMissing, to: &unknowns)
        }
        var copy = input.dataCompleteness
        copy.requiredUnknownReasonCodes = sortedUnique(unknowns)
        return copy
    }

    private static func appendUnknown(_ code: FinancialRiskReasonCode, to list: inout [FinancialRiskReasonCode]) {
        if !list.contains(code) {
            list.append(code)
        }
    }

    private static func sortedUnique(_ codes: [FinancialRiskReasonCode]) -> [FinancialRiskReasonCode] {
        var seen = Set<String>()
        return codes.filter { seen.insert($0.rawValue).inserted }
            .sorted { $0.rawValue < $1.rawValue }
    }
}
