import Foundation

/// Primary Transaction persist outcome. Debt linking is secondary and may fail independently.
public struct RecordTransactionOutcome: Sendable, Equatable {
    public var transaction: Transaction
    /// User-safe message when debt linking failed after the Transaction was persisted.
    public var debtLinkingIssue: String?

    public init(transaction: Transaction, debtLinkingIssue: String? = nil) {
        self.transaction = transaction
        self.debtLinkingIssue = debtLinkingIssue
    }

    public var isFullySuccessful: Bool { debtLinkingIssue == nil }
}

public struct RecordTransactionInput: Sendable, Equatable {
    public var amount: Decimal
    public var currencyCode: String
    public var date: Date
    public var merchant: String?
    public var category: String
    public var accountId: UUID
    public var note: String?
    public var formType: TransactionFormType
    public var source: TransactionSource
    public var recognitionConfidence: Double?
    public var sourceImageId: String?
    /// Import-local idempotency key. When set, reused to upsert the same Transaction id.
    public var idempotencyKey: UUID?

    public init(
        amount: Decimal,
        currencyCode: String = "CNY",
        date: Date = Date(),
        merchant: String? = nil,
        category: String,
        accountId: UUID,
        note: String? = nil,
        formType: TransactionFormType,
        source: TransactionSource = .manual,
        recognitionConfidence: Double? = nil,
        sourceImageId: String? = nil,
        idempotencyKey: UUID? = nil
    ) {
        self.amount = amount
        self.currencyCode = currencyCode.uppercased()
        self.date = date
        self.merchant = merchant
        self.category = category
        self.accountId = accountId
        self.note = note
        self.formType = formType
        self.source = source
        self.recognitionConfidence = recognitionConfidence
        self.sourceImageId = sourceImageId
        self.idempotencyKey = idempotencyKey
    }
}

public struct RecordTransferInput: Sendable, Equatable {
    public var amount: Decimal
    public var currencyCode: String
    public var date: Date
    public var fromAccountId: UUID
    public var toAccountId: UUID
    public var note: String?

    public init(
        amount: Decimal,
        currencyCode: String = "CNY",
        date: Date = Date(),
        fromAccountId: UUID,
        toAccountId: UUID,
        note: String? = nil
    ) {
        self.amount = amount
        self.currencyCode = currencyCode.uppercased()
        self.date = date
        self.fromAccountId = fromAccountId
        self.toAccountId = toAccountId
        self.note = note
    }
}

public struct UpdateTransactionInput: Sendable, Equatable {
    public var transactionId: UUID
    public var amount: Decimal
    public var currencyCode: String
    public var date: Date
    public var merchant: String?
    public var category: String
    public var accountId: UUID
    public var note: String?
    public var formType: TransactionFormType
    /// 编辑转账时必填
    public var toAccountId: UUID?

    public init(
        transactionId: UUID,
        amount: Decimal,
        currencyCode: String = "CNY",
        date: Date,
        merchant: String? = nil,
        category: String,
        accountId: UUID,
        note: String? = nil,
        formType: TransactionFormType,
        toAccountId: UUID? = nil
    ) {
        self.transactionId = transactionId
        self.amount = amount
        self.currencyCode = currencyCode.uppercased()
        self.date = date
        self.merchant = merchant
        self.category = category
        self.accountId = accountId
        self.note = note
        self.formType = formType
        self.toAccountId = toAccountId
    }
}
