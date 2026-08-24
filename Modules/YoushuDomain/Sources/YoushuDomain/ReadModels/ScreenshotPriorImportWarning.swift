import Foundation

/// Resolved summary of one previously confirmed transaction for prior-import warning UI.
public struct PriorImportedTransactionSummary: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let merchant: String?
    public let amountText: String
    public let date: Date

    public init(id: UUID, merchant: String?, amountText: String, date: Date) {
        self.id = id
        self.merchant = merchant
        self.amountText = amountText
        self.date = date
    }
}

/// Exact-source prior-import warning state (ADR-036 Step D).
///
/// Does not contain financial heuristics; only cryptographic identity and resolvable entity refs.
public struct ScreenshotPriorImportWarning: Sendable, Equatable {
    public let importIdentity: TransactionScreenshotImportIdentity
    public let existingTransactions: [PriorImportedTransactionSummary]

    public init(
        importIdentity: TransactionScreenshotImportIdentity,
        existingTransactions: [PriorImportedTransactionSummary]
    ) {
        self.importIdentity = importIdentity
        self.existingTransactions = existingTransactions
    }
}
