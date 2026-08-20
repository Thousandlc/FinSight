import Foundation

/// Order-independent signal deduplication per v1 specification.
public enum FinancialRiskPolicyDedup {
    public static func apply(_ signals: [FinancialRiskSignal]) -> [FinancialRiskSignal] {
        let present = Set(signals.map(\.reasonCode))
        var suppressed = Set<FinancialRiskReasonCode>()

        if present.contains(.negativeProjectedBalance) {
            suppressed.formUnion([.cashFlowBelowSafeBalance, .monthEndBelowSafeBalance])
        }
        if present.contains(.criticalDebtPressure) {
            suppressed.formUnion([.highDebtPressureScore, .highDebtPaymentToIncome])
        } else if present.contains(.highDebtPressureScore) {
            suppressed.insert(.highDebtPaymentToIncome)
        }

        return signals.filter { !suppressed.contains($0.reasonCode) }
    }
}
