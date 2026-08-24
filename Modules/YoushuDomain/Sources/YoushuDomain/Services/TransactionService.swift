import Foundation
import YoushuFoundation

/// CRUD for manual transactions. Transfer creates paired legs.
/// 可选 TransactionDebtLinking：创建后尝试关联债务（自动或待确认）。
public struct TransactionService: TransactionManaging {
    private let accounts: any AccountRepository
    private let transactions: any TransactionRepository
    private let debtLinker: (any TransactionDebtLinking)?

    public init(
        accounts: any AccountRepository,
        transactions: any TransactionRepository,
        debtLinker: (any TransactionDebtLinking)? = nil
    ) {
        self.accounts = accounts
        self.transactions = transactions
        self.debtLinker = debtLinker
    }

    public func record(_ input: RecordTransactionInput, userId: UUID) async throws -> RecordTransactionOutcome {
        try validateAmount(input.amount)
        guard input.formType != .transfer else {
            throw DomainError.validationFailed("Use recordTransfer for transfer type")
        }
        guard TransactionCategory.isValid(input.category, for: input.formType.transactionType) else {
            throw DomainError.validationFailed("Invalid category for transaction type")
        }
        try await requireAccount(input.accountId, userId: userId)

        let money = Money(amount: input.amount, currencyCode: input.currencyCode)
        var tx = Transaction(
            id: input.idempotencyKey ?? UUID(),
            userId: userId,
            accountId: input.accountId,
            amount: money,
            date: input.date,
            merchant: normalized(input.merchant),
            category: input.category,
            transactionType: input.formType.transactionType,
            note: normalized(input.note),
            sourceImageId: input.sourceImageId,
            recognitionConfidence: input.recognitionConfidence,
            source: input.source
        )
        try await transactions.upsert(tx)

        var linkingIssue: String?
        if let debtLinker {
            do {
                _ = try await debtLinker.processNewTransaction(tx, userId: userId)
                if let refreshed = try await transactions.fetch(id: tx.id) {
                    tx = refreshed
                }
            } catch {
                linkingIssue = PrivacySafeErrorMapper.userMessage(for: error)
            }
        }
        return RecordTransactionOutcome(transaction: tx, debtLinkingIssue: linkingIssue)
    }

    public func recordTransfer(_ input: RecordTransferInput, userId: UUID) async throws -> (outbound: Transaction, inbound: Transaction) {
        try validateAmount(input.amount)
        guard input.fromAccountId != input.toAccountId else {
            throw DomainError.validationFailed("Transfer accounts must differ")
        }
        try await requireAccount(input.fromAccountId, userId: userId)
        try await requireAccount(input.toAccountId, userId: userId)

        let money = Money(amount: input.amount, currencyCode: input.currencyCode)
        let groupId = UUID()
        let now = Date()

        let outbound = Transaction(
            id: groupId,
            userId: userId,
            accountId: input.fromAccountId,
            amount: money,
            date: input.date,
            merchant: "转账",
            category: TransactionCategory.transfer,
            transactionType: .transfer,
            note: normalized(input.note),
            transferCounterpartyAccountId: input.toAccountId,
            source: .manual,
            createdAt: now,
            updatedAt: now
        )

        let inbound = Transaction(
            id: UUID(),
            userId: userId,
            accountId: input.toAccountId,
            amount: money,
            date: input.date,
            merchant: "转账",
            category: TransactionCategory.transfer,
            transactionType: .income,
            note: normalized(input.note),
            transferCounterpartyAccountId: input.fromAccountId,
            source: .manual,
            createdAt: now,
            updatedAt: now
        )

        try await transactions.upsert(outbound)
        try await transactions.upsert(inbound)
        return (outbound, inbound)
    }

    public func update(_ input: UpdateTransactionInput, userId: UUID) async throws -> Transaction {
        try validateAmount(input.amount)
        guard let existing = try await transactions.fetch(id: input.transactionId) else {
            throw DomainError.notFound(entity: "Transaction", id: input.transactionId)
        }
        guard existing.userId == userId else { throw DomainError.userMismatch }

        if isTransferLeg(existing) {
            return try await updateTransferLeg(existing, input: input, userId: userId)
        }

        guard TransactionCategory.isValid(input.category, for: input.formType.transactionType) else {
            throw DomainError.validationFailed("Invalid category")
        }
        try await requireAccount(input.accountId, userId: userId)

        var updated = existing
        updated.amount = Money(amount: input.amount, currencyCode: input.currencyCode)
        updated.date = input.date
        updated.merchant = normalized(input.merchant)
        updated.category = input.category
        updated.accountId = input.accountId
        updated.note = normalized(input.note)
        updated.transactionType = input.formType.transactionType
        updated.currencyCode = input.currencyCode.uppercased()
        updated.updatedAt = Date()
        try await transactions.upsert(updated)
        return updated
    }

    public func delete(transactionId: UUID, userId: UUID) async throws {
        guard let existing = try await transactions.fetch(id: transactionId) else {
            throw DomainError.notFound(entity: "Transaction", id: transactionId)
        }
        guard existing.userId == userId else { throw DomainError.userMismatch }

        if isTransferLeg(existing) {
            try await deleteTransferPair(existing, userId: userId)
            return
        }
        try await transactions.delete(id: transactionId)
    }

    // MARK: - Private

    private func updateTransferLeg(
        _ existing: Transaction,
        input: UpdateTransactionInput,
        userId: UUID
    ) async throws -> Transaction {
        guard let toAccountId = input.toAccountId else {
            throw DomainError.validationFailed("Transfer requires destination account")
        }
        guard input.formType == .transfer else {
            throw DomainError.validationFailed("Cannot change transfer to non-transfer type")
        }
        try await requireAccount(input.accountId, userId: userId)
        try await requireAccount(toAccountId, userId: userId)

        let pair = try await findTransferPair(for: existing, userId: userId)
        let money = Money(amount: input.amount, currencyCode: input.currencyCode)
        let now = Date()

        var outbound = pair.outbound
        outbound.amount = money
        outbound.date = input.date
        outbound.note = normalized(input.note)
        outbound.accountId = input.accountId
        outbound.transferCounterpartyAccountId = toAccountId
        outbound.updatedAt = now

        var inbound = pair.inbound
        inbound.amount = money
        inbound.date = input.date
        inbound.note = normalized(input.note)
        inbound.accountId = toAccountId
        inbound.transferCounterpartyAccountId = input.accountId
        inbound.updatedAt = now

        try await transactions.upsert(outbound)
        try await transactions.upsert(inbound)
        return existing.id == outbound.id ? outbound : inbound
    }

    private func deleteTransferPair(_ existing: Transaction, userId: UUID) async throws {
        let pair = try await findTransferPair(for: existing, userId: userId)
        try await transactions.delete(id: pair.outbound.id)
        try await transactions.delete(id: pair.inbound.id)
    }

    private func findTransferPair(for tx: Transaction, userId: UUID) async throws -> (outbound: Transaction, inbound: Transaction) {
        guard let counterparty = tx.transferCounterpartyAccountId else {
            throw DomainError.invalidRelation("Transfer missing counterparty")
        }
        let all = try await transactions.fetchAll(userId: userId)
        let partner = all.first { candidate in
            candidate.id != tx.id
                && candidate.transferCounterpartyAccountId == tx.accountId
                && candidate.accountId == counterparty
                && candidate.category == TransactionCategory.transfer
                && candidate.amount == tx.amount
        }
        guard let partner else {
            throw DomainError.invalidRelation("Transfer pair not found")
        }

        if tx.transactionType == .transfer {
            return (tx, partner)
        }
        return (partner, tx)
    }

    private func isTransferLeg(_ tx: Transaction) -> Bool {
        tx.category == TransactionCategory.transfer && tx.transferCounterpartyAccountId != nil
    }

    private func requireAccount(_ accountId: UUID, userId: UUID) async throws {
        guard let account = try await accounts.fetch(id: accountId), account.userId == userId else {
            throw DomainError.invalidRelation("Account not found for user")
        }
    }

    private func validateAmount(_ amount: Decimal) throws {
        guard amount > 0 else {
            throw DomainError.validationFailed("Amount must be positive")
        }
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
