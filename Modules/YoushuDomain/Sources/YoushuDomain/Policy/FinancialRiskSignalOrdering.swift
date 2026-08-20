import Foundation

/// Deterministic ordering for assessment signals and action destinations.
public enum FinancialRiskSignalOrdering {
    private static let kindRank: [FinancialRiskSignalKind: Int] = [
        .cashFlow: 0,
        .debt: 1,
        .incomeExpense: 2,
    ]

    public static func sortSignals(_ signals: [FinancialRiskSignal]) -> [FinancialRiskSignal] {
        signals.sorted(by: compareSignals)
    }

    public static func sortActions(_ actions: [FinancialRiskActionDestination]) -> [FinancialRiskActionDestination] {
        actions.sorted { $0.rawValue < $1.rawValue }
    }

    private static func compareSignals(_ lhs: FinancialRiskSignal, _ rhs: FinancialRiskSignal) -> Bool {
        if lhs.level.rank != rhs.level.rank {
            return lhs.level.rank > rhs.level.rank
        }
        let lk = kindRank[lhs.kind] ?? Int.max
        let rk = kindRank[rhs.kind] ?? Int.max
        if lk != rk { return lk < rk }
        if lhs.reasonCode.rawValue != rhs.reasonCode.rawValue {
            return lhs.reasonCode.rawValue < rhs.reasonCode.rawValue
        }
        let lKeys = lhs.sourceFactKeys.sorted().joined(separator: ",")
        let rKeys = rhs.sourceFactKeys.sorted().joined(separator: ",")
        return lKeys < rKeys
    }
}

extension FinancialRiskSignal {
    func withSortedActions() -> FinancialRiskSignal {
        var copy = self
        copy.recommendedActionDestinations = FinancialRiskSignalOrdering.sortActions(recommendedActionDestinations)
        return copy
    }
}
