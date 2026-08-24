import Foundation
import Testing
import YoushuData
import YoushuDomain
import YoushuFoundation

@Suite("Account balance engine")
struct AccountBalanceEngineTests {
    private func account(_ type: AccountType, opening: Decimal = 1000) -> Account {
        Account(userId: UUID(), name: "测试", type: type, openingBalance: Money(amount: opening, currencyCode: "CNY"))
    }

    @Test("income increases asset balance")
    func income() {
        let acc = account(.cash)
        let tx = Transaction(
            userId: acc.userId, accountId: acc.id,
            amount: Money(amount: 500, currencyCode: "CNY"),
            transactionType: .income
        )
        let balance = AccountBalanceEngine.balance(account: acc, transactions: [tx])
        #expect(balance.amount == 1500)
    }

    @Test("expense decreases asset balance")
    func expense() {
        let acc = account(.cash)
        let tx = Transaction(
            userId: acc.userId, accountId: acc.id,
            amount: Money(amount: 200, currencyCode: "CNY"),
            category: "餐饮", transactionType: .expense
        )
        let balance = AccountBalanceEngine.balance(account: acc, transactions: [tx])
        #expect(balance.amount == 800)
    }

    @Test("transfer decreases source and increases target")
    func transfer() {
        let bank = account(.bankCard, opening: 5000)
        let cash = account(.cash, opening: 0)
        let accounts = [bank, cash]
        let outbound = Transaction(
            userId: bank.userId, accountId: bank.id,
            amount: Money(amount: 300, currencyCode: "CNY"),
            category: TransactionCategory.transfer, transactionType: .transfer,
            transferCounterpartyAccountId: cash.id
        )
        let inbound = Transaction(
            userId: cash.userId, accountId: cash.id,
            amount: Money(amount: 300, currencyCode: "CNY"),
            category: TransactionCategory.transfer, transactionType: .income,
            transferCounterpartyAccountId: bank.id
        )
        let txs = [outbound, inbound]
        let bankBal = AccountBalanceEngine.balance(account: bank, transactions: txs, allAccounts: accounts)
        let cashBal = AccountBalanceEngine.balance(account: cash, transactions: txs, allAccounts: accounts)
        #expect(bankBal.amount == 4700)
        #expect(cashBal.amount == 300)
    }

    @Test("credit card expense increases liability on account")
    func creditCardPayment() {
        let cc = account(.creditCard, opening: 0)
        let tx = Transaction(
            userId: cc.userId, accountId: cc.id,
            amount: Money(amount: 800, currencyCode: "CNY"),
            category: "购物", transactionType: .expense
        )
        let balance = AccountBalanceEngine.balance(account: cc, transactions: [tx])
        #expect(balance.amount == -800)
    }

    @Test("credit card repayment improves account balance")
    func creditCardRepayment() {
        let cc = account(.creditCard, opening: -800)
        let tx = Transaction(
            userId: cc.userId, accountId: cc.id,
            amount: Money(amount: 500, currencyCode: "CNY"),
            transactionType: .repayment
        )
        let balance = AccountBalanceEngine.balance(account: cc, transactions: [tx])
        #expect(balance.amount == -300)
    }

    @Test("bank repayment reduces payer balance")
    func bankRepayment() {
        let bank = account(.bankCard, opening: 3000)
        let tx = Transaction(
            userId: bank.userId, accountId: bank.id,
            amount: Money(amount: 500, currencyCode: "CNY"),
            transactionType: .repayment
        )
        let balance = AccountBalanceEngine.balance(account: bank, transactions: [tx])
        #expect(balance.amount == 2500)
    }

    @Test("available funds excludes credit card liability account")
    func availableFundsExcludesCreditCard() {
        let cash = account(.cash, opening: 1000)
        let cc = account(.creditCard, opening: 0)
        let accounts = [cash, cc]
        let ccTx = Transaction(
            userId: cc.userId, accountId: cc.id,
            amount: Money(amount: 500, currencyCode: "CNY"),
            transactionType: .expense
        )
        let txs = [ccTx]
        let total = AccountBalanceEngine.availableFunds(accounts: accounts, transactions: txs)
        #expect(total.amount == 1000)
    }

    @Test("deleting transaction rolls back balance")
    func deleteRollback() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await container.users.upsert(User(id: userId, displayName: "T"))
        let cash = Account(userId: userId, name: "现金", type: .cash, openingBalance: Money(amount: 1000, currencyCode: "CNY"))
        try await container.accounts.upsert(cash)

        let service = TransactionService(accounts: container.accounts, transactions: container.transactions)
        let created = try await service.record(
            RecordTransactionInput(amount: 100, category: "餐饮", accountId: cash.id, formType: .expense),
            userId: userId
        ).transaction
        var txs = try await container.transactions.fetchAll(userId: userId)
        var balance = AccountBalanceEngine.balance(account: cash, transactions: txs)
        #expect(balance.amount == 900)

        try await service.delete(transactionId: created.id, userId: userId)
        txs = try await container.transactions.fetchAll(userId: userId)
        balance = AccountBalanceEngine.balance(account: cash, transactions: txs)
        #expect(balance.amount == 1000)
    }
}

@Suite("Account service")
struct AccountServiceTests {
    @Test("creates credit card with linked debt")
    func createCreditCard() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await container.users.upsert(User(id: userId, displayName: "T"))
        let service = AccountService(
            accounts: container.accounts,
            transactions: container.transactions,
            debts: container.debts
        )
        let account = try await service.create(
            CreateAccountInput(name: "招行信用卡", type: .creditCard),
            userId: userId
        )
        #expect(account.linkedDebtId != nil)
        let debt = try await container.debts.fetch(id: account.linkedDebtId!)
        #expect(debt?.debtType == .creditCard)
    }

    @Test("cannot delete account with transactions")
    func deleteWithTransactions() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await container.users.upsert(User(id: userId, displayName: "T"))
        let cash = Account(userId: userId, name: "现金", type: .cash)
        try await container.accounts.upsert(cash)
        try await container.transactions.upsert(
            Transaction(userId: userId, accountId: cash.id, amount: Money(amount: 1, currencyCode: "CNY"), transactionType: .expense)
        )
        let service = AccountService(
            accounts: container.accounts,
            transactions: container.transactions,
            debts: container.debts
        )
        await #expect(throws: DomainError.self) {
            try await service.delete(accountId: cash.id, userId: userId)
        }
    }
}
