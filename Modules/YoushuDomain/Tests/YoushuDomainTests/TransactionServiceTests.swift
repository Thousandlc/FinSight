import Foundation
import Testing
import YoushuData
import YoushuDomain
import YoushuFoundation

@Suite("Transaction service")
struct TransactionServiceTests {
    private func makeService(store: YoushuStore) -> (TransactionService, RepositoryContainer, UUID) {
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        return (TransactionService(accounts: container.accounts, transactions: container.transactions), container, userId)
    }

    private func seedUserAndAccounts(_ container: RepositoryContainer, userId: UUID) async throws -> (Account, Account) {
        try await container.users.upsert(User(id: userId, displayName: "Test"))
        let cash = Account(userId: userId, name: "现金", type: .cash, openingBalance: Money(amount: 1000, currencyCode: "CNY"))
        let bank = Account(userId: userId, name: "银行卡", type: .bankCard, openingBalance: Money(amount: 5000, currencyCode: "CNY"))
        try await container.accounts.upsert(cash)
        try await container.accounts.upsert(bank)
        return (cash, bank)
    }

    @Test("creates expense transaction")
    func createExpense() async throws {
        let store = YoushuStore()
        let (service, container, userId) = makeService(store: store)
        let (cash, _) = try await seedUserAndAccounts(container, userId: userId)

        let tx = try await service.record(
            RecordTransactionInput(
                amount: Decimal(string: "128.50")!,
                date: Date(),
                merchant: "午餐",
                category: "餐饮",
                accountId: cash.id,
                formType: .expense
            ),
            userId: userId
        ).transaction

        #expect(tx.transactionType == .expense)
        #expect(tx.amount.amount == Decimal(string: "128.50")!)
        #expect(tx.category == "餐饮")
    }

    @Test("creates income transaction")
    func createIncome() async throws {
        let store = YoushuStore()
        let (service, container, userId) = makeService(store: store)
        let (cash, _) = try await seedUserAndAccounts(container, userId: userId)

        let tx = try await service.record(
            RecordTransactionInput(
                amount: 8000,
                merchant: "公司",
                category: "工资",
                accountId: cash.id,
                formType: .income
            ),
            userId: userId
        ).transaction

        #expect(tx.transactionType == .income)
        #expect(tx.category == "工资")
    }

    @Test("creates transfer pair and updates both account balances")
    func createTransfer() async throws {
        let store = YoushuStore()
        let (service, container, userId) = makeService(store: store)
        let (cash, bank) = try await seedUserAndAccounts(container, userId: userId)

        let pair = try await service.recordTransfer(
            RecordTransferInput(amount: 200, fromAccountId: bank.id, toAccountId: cash.id),
            userId: userId
        )

        #expect(pair.outbound.transactionType == .transfer)
        #expect(pair.inbound.transactionType == .income)
        #expect(pair.inbound.category == TransactionCategory.transfer)

        let txs = try await container.transactions.fetchAll(userId: userId)
        let accounts = try await container.accounts.fetchAll(userId: userId)
        let bankBalance = AccountBalanceEngine.balance(account: bank, transactions: txs, allAccounts: accounts)
        let cashBalance = AccountBalanceEngine.balance(account: cash, transactions: txs, allAccounts: accounts)
        #expect(bankBalance.amount == 4800)
        #expect(cashBalance.amount == 1200)
    }

    @Test("updates expense transaction")
    func updateTransaction() async throws {
        let store = YoushuStore()
        let (service, container, userId) = makeService(store: store)
        let (cash, _) = try await seedUserAndAccounts(container, userId: userId)

        let created = try await service.record(
            RecordTransactionInput(amount: 50, category: "交通", accountId: cash.id, formType: .expense),
            userId: userId
        ).transaction

        let updated = try await service.update(
            UpdateTransactionInput(
                transactionId: created.id,
                amount: 80,
                date: created.date,
                merchant: "出租车",
                category: "交通",
                accountId: cash.id,
                formType: .expense
            ),
            userId: userId
        )

        #expect(updated.amount.amount == 80)
        #expect(updated.merchant == "出租车")
    }

    @Test("deletes transaction")
    func deleteTransaction() async throws {
        let store = YoushuStore()
        let (service, container, userId) = makeService(store: store)
        let (cash, _) = try await seedUserAndAccounts(container, userId: userId)

        let created = try await service.record(
            RecordTransactionInput(amount: 10, category: "其他", accountId: cash.id, formType: .expense),
            userId: userId
        ).transaction
        try await service.delete(transactionId: created.id, userId: userId)
        #expect(try await container.transactions.fetch(id: created.id) == nil)
    }

    @Test("deleting transfer removes both legs")
    func deleteTransferPair() async throws {
        let store = YoushuStore()
        let (service, container, userId) = makeService(store: store)
        let (cash, bank) = try await seedUserAndAccounts(container, userId: userId)

        let pair = try await service.recordTransfer(
            RecordTransferInput(amount: 100, fromAccountId: cash.id, toAccountId: bank.id),
            userId: userId
        )
        try await service.delete(transactionId: pair.outbound.id, userId: userId)
        #expect(try await container.transactions.fetchAll(userId: userId).isEmpty)
    }

    @Test("account balance reflects expense and income")
    func accountBalanceChange() async throws {
        let store = YoushuStore()
        let (service, container, userId) = makeService(store: store)
        let (cash, _) = try await seedUserAndAccounts(container, userId: userId)

        _ = try await service.record(
            RecordTransactionInput(amount: 200, category: "购物", accountId: cash.id, formType: .expense),
            userId: userId
        )
        _ = try await service.record(
            RecordTransactionInput(amount: 500, category: "工资", accountId: cash.id, formType: .income),
            userId: userId
        )

        let txs = try await container.transactions.fetchAll(userId: userId)
        let balance = AccountBalanceEngine.balance(account: cash, transactions: txs)
        #expect(balance.amount == 1300)
    }
}

@Suite("Transaction grouping")
struct TransactionGrouperTests {
    @Test("groups today and yesterday")
    func grouping() {
        let calendar = Calendar.current
        let now = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let account = Account(userId: UUID(), name: "现金", type: .cash)
        let txs = [
            Transaction(userId: account.userId, accountId: account.id, amount: .zeroCNY, date: now, transactionType: .expense),
            Transaction(userId: account.userId, accountId: account.id, amount: .zeroCNY, date: yesterday, transactionType: .expense),
        ]
        let sections = TransactionGrouper.group(transactions: txs, accounts: [account], calendar: calendar, now: now)
        #expect(sections.contains { $0.id == .today })
        #expect(sections.contains { $0.id == .yesterday })
    }

    @Test("hides transfer inbound leg from list")
    func hideInboundTransfer() {
        let accountA = UUID()
        let accountB = UUID()
        let outbound = Transaction(
            userId: UUID(),
            accountId: accountA,
            amount: Money(amount: 100, currencyCode: "CNY"),
            category: TransactionCategory.transfer,
            transactionType: .transfer,
            transferCounterpartyAccountId: accountB
        )
        let inbound = Transaction(
            userId: UUID(),
            accountId: accountB,
            amount: Money(amount: 100, currencyCode: "CNY"),
            category: TransactionCategory.transfer,
            transactionType: .income,
            transferCounterpartyAccountId: accountA
        )
        #expect(TransactionGrouper.shouldDisplayInList(outbound))
        #expect(!TransactionGrouper.shouldDisplayInList(inbound))
    }
}

@Suite("Monthly stats")
struct MonthlyStatsTests {
    @Test("computes monthly income and expense")
    func monthlyStats() {
        let userId = UUID()
        let accountId = UUID()
        let now = Date()
        let txs = [
            Transaction(userId: userId, accountId: accountId, amount: Money(amount: 100, currencyCode: "CNY"), date: now, category: "餐饮", transactionType: .expense),
            Transaction(userId: userId, accountId: accountId, amount: Money(amount: 3000, currencyCode: "CNY"), date: now, category: "工资", transactionType: .income),
        ]
        let stats = MonthlyStatsCalculator.compute(transactions: txs, month: now, currencyCode: "CNY")
        #expect(stats.expense.amount == 100)
        #expect(stats.income.amount == 3000)
        #expect(stats.net.amount == 2900)
    }
}
