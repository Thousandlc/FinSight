import Foundation

public protocol TransactionManaging: Sendable {
    func record(_ input: RecordTransactionInput, userId: UUID) async throws -> RecordTransactionOutcome
    func recordTransfer(_ input: RecordTransferInput, userId: UUID) async throws -> (outbound: Transaction, inbound: Transaction)
    func update(_ input: UpdateTransactionInput, userId: UUID) async throws -> Transaction
    func delete(transactionId: UUID, userId: UUID) async throws
}
