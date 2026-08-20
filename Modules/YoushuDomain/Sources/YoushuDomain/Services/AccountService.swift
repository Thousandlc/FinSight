import Foundation
import YoushuFoundation

public struct AccountListService: AccountListProviding {
    private let accounts: any AccountRepository
    private let transactions: any TransactionRepository
    private let debts: any DebtRepository

    public init(
        accounts: any AccountRepository,
        transactions: any TransactionRepository,
        debts: any DebtRepository
    ) {
        self.accounts = accounts
        self.transactions = transactions
        self.debts = debts
    }

    public func loadSnapshot(userId: UUID) async throws -> AccountListSnapshot {
        let accountList = try await accounts.fetchAll(userId: userId).filter { !$0.isArchived }
        let txs = try await transactions.fetchAll(userId: userId)
        let summaries = accountList.map { account in
            let related = txs.filter { $0.accountId == account.id }
            let balance = AccountBalanceEngine.balance(
                account: account,
                transactions: txs,
                allAccounts: accountList
            )
            return AccountSummary(account: account, currentBalance: balance, transactionCount: related.count)
        }
        .sorted { $0.account.name < $1.account.name }

        let total = AccountBalanceEngine.availableFunds(accounts: accountList, transactions: txs)
        return AccountListSnapshot(accounts: summaries, totalAvailableFunds: total)
    }

    public func loadDetail(accountId: UUID, userId: UUID) async throws -> AccountDetailSnapshot {
        guard let account = try await accounts.fetch(id: accountId), account.userId == userId else {
            throw DomainError.notFound(entity: "Account", id: accountId)
        }
        let accountList = try await accounts.fetchAll(userId: userId)
        let txs = try await transactions.fetchAll(userId: userId)
        let balance = AccountBalanceEngine.balance(
            account: account,
            transactions: txs,
            allAccounts: accountList
        )
        let recent = txs
            .filter { $0.accountId == account.id && TransactionGrouper.shouldDisplayInList($0) }
            .sorted { $0.date > $1.date }
            .prefix(20)
        var linkedDebt: Debt?
        if let debtId = account.linkedDebtId {
            linkedDebt = try await debts.fetch(id: debtId)
        }
        return AccountDetailSnapshot(
            account: account,
            currentBalance: balance,
            recentTransactions: Array(recent),
            linkedDebt: linkedDebt
        )
    }
}

public struct AccountService: AccountManaging {
    private let accounts: any AccountRepository
    private let transactions: any TransactionRepository
    private let debts: any DebtRepository

    public init(
        accounts: any AccountRepository,
        transactions: any TransactionRepository,
        debts: any DebtRepository
    ) {
        self.accounts = accounts
        self.transactions = transactions
        self.debts = debts
    }

    public func create(_ input: CreateAccountInput, userId: UUID) async throws -> Account {
        let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw DomainError.validationFailed("账户名称不能为空")
        }
        var linkedDebtId: UUID?
        if input.type == .creditCard && input.createLinkedDebt {
            let debt = Debt(
                userId: userId,
                lender: name,
                productName: name,
                debtType: .creditCard,
                outstandingBalance: Money(amount: 0, currencyCode: input.currencyCode),
                status: .active,
                source: .userInput
            )
            try await debts.upsert(debt)
            linkedDebtId = debt.id
        }

        let account = Account(
            userId: userId,
            name: name,
            type: input.type,
            currencyCode: input.currencyCode,
            openingBalance: Money(amount: input.openingBalance, currencyCode: input.currencyCode),
            note: normalized(input.note),
            linkedDebtId: linkedDebtId
        )
        try await accounts.upsert(account)
        return account
    }

    public func update(_ input: UpdateAccountInput, userId: UUID) async throws -> Account {
        guard var account = try await accounts.fetch(id: input.accountId) else {
            throw DomainError.notFound(entity: "Account", id: input.accountId)
        }
        guard account.userId == userId else { throw DomainError.userMismatch }

        let name = input.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            throw DomainError.validationFailed("账户名称不能为空")
        }

        account.name = name
        account.type = input.type
        account.openingBalance = Money(amount: input.openingBalance, currencyCode: input.currencyCode)
        account.currencyCode = input.currencyCode.uppercased()
        account.note = normalized(input.note)
        account.updatedAt = Date()
        try await accounts.upsert(account)
        return account
    }

    public func delete(accountId: UUID, userId: UUID) async throws {
        guard let account = try await accounts.fetch(id: accountId) else {
            throw DomainError.notFound(entity: "Account", id: accountId)
        }
        guard account.userId == userId else { throw DomainError.userMismatch }

        let txs = try await transactions.fetchAll(userId: userId)
        if txs.contains(where: { $0.accountId == accountId }) {
            throw DomainError.invalidRelation("账户存在关联交易，无法删除")
        }
        try await accounts.delete(id: accountId)
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
