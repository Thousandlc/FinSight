import Foundation

/// v1 deduplication and conflict resolution specification (no engine implementation).
public enum FinancialRiskPolicyDedupSpecification {
    public struct Rule: Equatable, Sendable, Identifiable {
        public var id: String
        public var description: String
        public var retainedReasonCode: FinancialRiskReasonCode
        public var suppressedReasonCodes: [FinancialRiskReasonCode]

        public init(
            id: String,
            description: String,
            retainedReasonCode: FinancialRiskReasonCode,
            suppressedReasonCodes: [FinancialRiskReasonCode]
        ) {
            self.id = id
            self.description = description
            self.retainedReasonCode = retainedReasonCode
            self.suppressedReasonCodes = suppressedReasonCodes
        }
    }

    public static let rules: [Rule] = [
        Rule(
            id: "DEDUP-1",
            description: "Negative projected balance supersedes below-safe warning on same fact chain.",
            retainedReasonCode: .negativeProjectedBalance,
            suppressedReasonCodes: [.cashFlowBelowSafeBalance, .monthEndBelowSafeBalance]
        ),
        Rule(
            id: "DEDUP-2",
            description: "When DebtPressureLevel high/critical signal exists, omit duplicate DTI warning.",
            retainedReasonCode: .highDebtPressureScore,
            suppressedReasonCodes: [.highDebtPaymentToIncome]
        ),
        Rule(
            id: "DEDUP-3",
            description: "Critical debt pressure supersedes high debt pressure and DTI warnings.",
            retainedReasonCode: .criticalDebtPressure,
            suppressedReasonCodes: [.highDebtPressureScore, .highDebtPaymentToIncome]
        ),
    ]

    /// Conflict examples documented for v1 policy review.
    public static let conflictExamples: [(id: String, summary: String, expectedOverall: FinancialRiskLevel)] = [
        ("A", "healthy cash + high DTI → warning", .warning),
        ("B", "negative cash projection + knownNoDebt → risk (cashFlow only)", .risk),
        ("C", "zero income + large cash buffer → warning (buffer does not cancel)", .warning),
        ("D", "debt missing + safe cash flow → overall safe + debt completeness missing", .safe),
        ("E", "critical debt pressure + safe cash flow → risk", .risk),
        ("F", "minimumBalance < 0 and below safe → only negativeProjectedBalance risk", .risk),
    ]
}
