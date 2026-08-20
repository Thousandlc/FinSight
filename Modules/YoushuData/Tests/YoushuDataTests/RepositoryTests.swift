import Foundation
import Testing
import YoushuData
import YoushuDomain
import YoushuFoundation

@Suite("Repository persistence")
struct RepositoryPersistenceTests {
    @Test("creates and fetches transaction")
    func createTransaction() async throws {
        let container = RepositoryContainer.inMemory()
        let user = User(displayName: "Tester")
        let account = Account(userId: user.id, name: "招行储蓄", type: .bankCard)
        try await container.users.upsert(user)
        try await container.accounts.upsert(account)

        let tx = Transaction(
            userId: user.id,
            accountId: account.id,
            amount: Money(amount: 36, currencyCode: "CNY"),
            merchant: "地铁",
            category: "交通",
            transactionType: .expense,
            source: .shortcut
        )
        try await container.transactions.upsert(tx)

        let loaded = try await container.transactions.fetch(id: tx.id)
        #expect(loaded?.merchant == "地铁")
        #expect(loaded?.transactionType == .expense)
    }

    @Test("creates debt and debt events")
    func createDebtAndEvents() async throws {
        let container = RepositoryContainer.inMemory()
        let user = User(displayName: "Tester")
        try await container.users.upsert(user)

        let debt = Debt(
            userId: user.id,
            lender: "蚂蚁借呗",
            productName: "借呗",
            debtType: .consumerLoan,
            outstandingBalance: Money(amount: 5000, currencyCode: "CNY"),
            status: .active,
            source: .userInput
        )
        try await container.debts.upsert(debt)

        let event = DebtEvent(
            debtId: debt.id,
            userId: user.id,
            type: .created,
            amount: Money(amount: 5000, currencyCode: "CNY")
        )
        try await container.debtEvents.upsert(event)

        let debts = try await container.debts.fetchAll(userId: user.id)
        let events = try await container.debtEvents.fetchAll(debtId: debt.id)
        #expect(debts.count == 1)
        #expect(events.count == 1)
        #expect(events.first?.type == .created)
    }

    @Test("associates repayment transaction with debt")
    func associateTransactionAndDebt() async throws {
        let container = RepositoryContainer.inMemory()
        let user = User(displayName: "Tester")
        let account = Account(userId: user.id, name: "工资卡", type: .bankCard)
        try await container.users.upsert(user)
        try await container.accounts.upsert(account)

        let debt = Debt(
            userId: user.id,
            lender: "银行",
            outstandingBalance: Money(amount: 3000, currencyCode: "CNY"),
            status: .active
        )
        try await container.debts.upsert(debt)

        let tx = Transaction(
            userId: user.id,
            accountId: account.id,
            amount: Money(amount: 500, currencyCode: "CNY"),
            transactionType: .repayment,
            relatedDebtId: debt.id,
            source: .manual
        )
        try await container.transactions.upsert(tx)

        let linked = try await container.transactions.fetchAll(relatedDebtId: debt.id)
        #expect(linked.count == 1)
        #expect(linked.first?.id == tx.id)
    }

    @Test("deletes debt and cascades events while detaching transactions")
    func deleteDebt() async throws {
        let container = RepositoryContainer.inMemory()
        let user = User(displayName: "Tester")
        let account = Account(userId: user.id, name: "卡", type: .bankCard)
        try await container.users.upsert(user)
        try await container.accounts.upsert(account)

        let debt = Debt(userId: user.id, lender: "X", outstandingBalance: Money(amount: 1, currencyCode: "CNY"))
        try await container.debts.upsert(debt)
        try await container.debtEvents.upsert(
            DebtEvent(debtId: debt.id, userId: user.id, type: .created, amount: Money(amount: 1, currencyCode: "CNY"))
        )
        let tx = Transaction(
            userId: user.id,
            accountId: account.id,
            amount: Money(amount: 1, currencyCode: "CNY"),
            transactionType: .repayment,
            relatedDebtId: debt.id
        )
        try await container.transactions.upsert(tx)

        try await container.debts.delete(id: debt.id)

        #expect(try await container.debts.fetch(id: debt.id) == nil)
        #expect(try await container.debtEvents.fetchAll(debtId: debt.id).isEmpty)
        let kept = try await container.transactions.fetch(id: tx.id)
        #expect(kept != nil)
        #expect(kept?.relatedDebtId == nil)
    }

    @Test("persists snapshot to disk and reloads")
    func persistenceRoundTrip() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("youshu-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("store.json")
        defer { try? FileManager.default.removeItem(at: dir) }

        let user = User(displayName: "持久化用户")
        let account = Account(userId: user.id, name: "现金", type: .cash)
        let debt = Debt(
            userId: user.id,
            lender: "京东白条",
            outstandingBalance: Money(amount: 1200, currencyCode: "CNY"),
            status: .active,
            source: .screenshot
        )

        do {
            let container = RepositoryContainer.fileBacked(url: fileURL)
            try await container.users.upsert(user)
            try await container.accounts.upsert(account)
            try await container.debts.upsert(debt)
            try await container.transactions.upsert(
                Transaction(
                    userId: user.id,
                    accountId: account.id,
                    amount: Money(amount: 20, currencyCode: "CNY"),
                    transactionType: .expense,
                    relatedDebtId: nil,
                    source: .manual
                )
            )
            try await container.store.persist()
        }

        let reloaded = try await YoushuStore.load(from: fileURL)
        let reloadedContainer = RepositoryContainer(store: reloaded)
        #expect(try await reloadedContainer.users.fetch(id: user.id)?.displayName == "持久化用户")
        #expect(try await reloadedContainer.accounts.fetchAll(userId: user.id).count == 1)
        #expect(try await reloadedContainer.debts.fetch(id: debt.id)?.lender == "京东白条")
        #expect(try await reloadedContainer.transactions.fetchAll(userId: user.id).count == 1)
    }

    @Test("rejects transaction for unknown account")
    func rejectInvalidRelation() async throws {
        let container = RepositoryContainer.inMemory()
        let user = User(displayName: "Tester")
        try await container.users.upsert(user)

        let tx = Transaction(
            userId: user.id,
            accountId: UUID(),
            amount: Money(amount: 1, currencyCode: "CNY"),
            transactionType: .expense
        )

        await #expect(throws: DataError.self) {
            try await container.transactions.upsert(tx)
        }
    }
}
