import Foundation

/// Suppresses debt-pressure risk signals when canonical debt state is knownNoDebt.
/// Does not forbid neutral citation of `monthlyDebtPayment` facts (including zero).
/// Suppression is reason-code scoped — not by `FinancialRiskSignalKind.debt` alone.
public enum FinancialRiskKnownZeroGuard {
    /// Reason codes that must not appear when debt inventory confirms no debt.
    public static let suppressedReasonCodes: Set<FinancialRiskReasonCode> = [
        .highDebtPaymentToIncome,
        .criticalDebtPaymentToIncome,
        .highDebtPressureScore,
        .criticalDebtPressure,
        .repaymentConcern,
    ]

    public static func isDebtPressureReasonCode(_ code: FinancialRiskReasonCode) -> Bool {
        suppressedReasonCodes.contains(code)
    }

    public static func isDebtPressureSignal(_ signal: FinancialRiskSignal) -> Bool {
        isDebtPressureReasonCode(signal.reasonCode)
    }

    public static func allowsSignal(_ signal: FinancialRiskSignal, debtState: DebtDataState) -> Bool {
        guard debtState == .knownNoDebt else { return true }
        return !isDebtPressureSignal(signal)
    }

    public static func filterSignals(
        _ signals: [FinancialRiskSignal],
        debtState: DebtDataState
    ) -> [FinancialRiskSignal] {
        signals.filter { allowsSignal($0, debtState: debtState) }
    }
}
