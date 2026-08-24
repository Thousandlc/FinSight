import Foundation

/// Resolved summary of one previously confirmed debt for prior-scan warning UI.
public struct PriorImportedDebtSummary: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let lender: String?
    public let productName: String?
    public let outstandingBalanceText: String?

    public init(
        id: UUID,
        lender: String?,
        productName: String?,
        outstandingBalanceText: String?
    ) {
        self.id = id
        self.lender = lender
        self.productName = productName
        self.outstandingBalanceText = outstandingBalanceText
    }
}

/// Exact-source prior-scan warning state (ADR-036 Step E).
public struct DebtPriorScanWarning: Sendable, Equatable {
    public let importIdentity: DebtScanImportIdentity
    public let existingDebts: [PriorImportedDebtSummary]

    public init(importIdentity: DebtScanImportIdentity, existingDebts: [PriorImportedDebtSummary]) {
        self.importIdentity = importIdentity
        self.existingDebts = existingDebts
    }
}
