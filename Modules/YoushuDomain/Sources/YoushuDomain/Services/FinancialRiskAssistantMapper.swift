import Foundation

/// Boundary mapper: Core Financial Risk Domain → Assistant presentation contract.
/// Lives separately from core risk models so policy code does not depend on Assistant DTOs.
public enum FinancialRiskAssistantMapper {
    public static func mapLevel(_ level: FinancialRiskLevel) -> AssistantWarningSeverity {
        switch level {
        case .safe: return .safe
        case .warning: return .warning
        case .risk: return .risk
        }
    }

    public static func mapActionDestination(_ destination: FinancialRiskActionDestination) -> AssistantActionDestination {
        switch destination {
        case .cashFlow: return .cashFlow
        case .debt: return .debt
        case .transactions: return .transactions
        case .accounts: return .accounts
        }
    }

    public static func mapActionDestinations(
        _ destinations: [FinancialRiskActionDestination]
    ) -> [AssistantActionDestination] {
        destinations.map(mapActionDestination)
    }
}
