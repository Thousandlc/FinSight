import Foundation

/// Pure aggregation contract for financial risk signals.
/// v1: highest severity wins; no numeric priority scores; completeness excluded.
public enum FinancialRiskAggregation {
    public static func aggregateOverallLevel(from signals: [FinancialRiskSignal]) -> FinancialRiskLevel {
        guard !signals.isEmpty else { return .safe }
        return FinancialRiskLevel.highest(signals.map(\.level))
    }

    public static func aggregateOverallLevel(
        signals: [FinancialRiskSignal],
        debtState: DebtDataState
    ) -> FinancialRiskLevel {
        let filtered = FinancialRiskKnownZeroGuard.filterSignals(signals, debtState: debtState)
        return aggregateOverallLevel(from: filtered)
    }
}

/// Assembles a `FinancialRiskAssessment` from pre-built signals (no rule engine).
public enum FinancialRiskAssessmentAssembly {
    public static let defaultPolicyVersion = FinancialRiskPolicyVersion.current

    public static func assemble(
        signals: [FinancialRiskSignal],
        dataCompleteness: FinancialDataCompleteness,
        debtState: DebtDataState,
        policyVersion: String = defaultPolicyVersion,
        evaluatedAt: Date
    ) -> FinancialRiskAssessment {
        let filtered = FinancialRiskKnownZeroGuard.filterSignals(signals, debtState: debtState)
        let overall = FinancialRiskAggregation.aggregateOverallLevel(from: filtered)
        return FinancialRiskAssessment(
            overallLevel: overall,
            signals: filtered,
            dataCompleteness: dataCompleteness,
            debtDataState: debtState,
            policyVersion: policyVersion,
            evaluatedAt: evaluatedAt
        )
    }
}
