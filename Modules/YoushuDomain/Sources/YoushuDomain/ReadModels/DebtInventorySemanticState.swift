import Foundation

/// Local repository read outcome — technical load only, not semantic inventory completeness.
public enum DebtInventoryLoadState: String, Codable, Sendable, Equatable {
    case loaded
    case failed
}

/// Whether the product has sufficient evidence that the user's debt inventory is established.
public enum DebtInventoryEstablishmentState: String, Codable, Sendable, Equatable {
    /// User has not completed debt setup; empty repository cannot imply no debt.
    case unestablished
    /// Some debt data exists or import is underway; inventory completeness is not claimed.
    case partial
    /// Explicit product evidence that current persisted inventory is complete (includes confirmed no debt).
    case confirmedComplete
}

/// Explicit product events that can elevate establishment to `confirmedComplete` or `partial`.
public enum DebtInventoryEstablishmentSource: String, Codable, Sendable, Equatable {
    case userConfirmedNoDebt
    case inventoryReviewComplete
    case debtScanReviewComplete
    case firstDebtRecorded
    case importInProgress
}
