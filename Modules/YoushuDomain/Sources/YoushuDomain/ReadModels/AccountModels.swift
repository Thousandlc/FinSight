import Foundation
import YoushuFoundation

public struct AccountSummary: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let account: Account
    public let currentBalance: Money
    public let transactionCount: Int

    public init(account: Account, currentBalance: Money, transactionCount: Int) {
        self.id = account.id
        self.account = account
        self.currentBalance = currentBalance
        self.transactionCount = transactionCount
    }
}

public struct AccountListSnapshot: Equatable, Sendable {
    public var accounts: [AccountSummary]
    public var totalAvailableFunds: Money

    public var isEmpty: Bool { accounts.isEmpty }

    public init(accounts: [AccountSummary] = [], totalAvailableFunds: Money = .zeroCNY) {
        self.accounts = accounts
        self.totalAvailableFunds = totalAvailableFunds
    }
}

public struct AccountDetailSnapshot: Equatable, Sendable {
    public var account: Account
    public var currentBalance: Money
    public var recentTransactions: [Transaction]
    public var linkedDebt: Debt?

    public init(
        account: Account,
        currentBalance: Money,
        recentTransactions: [Transaction] = [],
        linkedDebt: Debt? = nil
    ) {
        self.account = account
        self.currentBalance = currentBalance
        self.recentTransactions = recentTransactions
        self.linkedDebt = linkedDebt
    }
}

public struct CreateAccountInput: Sendable, Equatable {
    public var name: String
    public var type: AccountType
    public var openingBalance: Decimal
    public var currencyCode: String
    public var note: String?
    public var createLinkedDebt: Bool

    public init(
        name: String,
        type: AccountType,
        openingBalance: Decimal = 0,
        currencyCode: String = "CNY",
        note: String? = nil,
        createLinkedDebt: Bool = true
    ) {
        self.name = name
        self.type = type
        self.openingBalance = openingBalance
        self.currencyCode = currencyCode.uppercased()
        self.note = note
        self.createLinkedDebt = createLinkedDebt
    }
}

public struct UpdateAccountInput: Sendable, Equatable {
    public var accountId: UUID
    public var name: String
    public var type: AccountType
    public var openingBalance: Decimal
    public var currencyCode: String
    public var note: String?

    public init(
        accountId: UUID,
        name: String,
        type: AccountType,
        openingBalance: Decimal,
        currencyCode: String = "CNY",
        note: String? = nil
    ) {
        self.accountId = accountId
        self.name = name
        self.type = type
        self.openingBalance = openingBalance
        self.currencyCode = currencyCode.uppercased()
        self.note = note
    }
}
