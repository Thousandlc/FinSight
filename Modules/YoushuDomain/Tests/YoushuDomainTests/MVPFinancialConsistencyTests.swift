import Foundation
import Testing
import YoushuAI
import YoushuData
import YoushuDomain
import YoushuFoundation

/// MVP 验收：指定账本数字下 Account / Transaction / Debt / DebtEvent / CashFlow / Home 一致性。
@Suite("MVP financial consistency")
struct MVPFinancialConsistencyTests {
    @Test("ledger 10000 - expense 2000 - debt 5000 - repay 1000 stays consistent")
    func goldenLedgerConsistency() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await container.users.upsert(User(id: userId, displayName: "MVP"))

        let account = Account(
            userId: userId,
            name: "现金",
            type: .cash,
            openingBalance: Money(amount: 10_000, currencyCode: "CNY")
        )
        try await container.accounts.upsert(account)

        let txService = TransactionService(
            accounts: container.accounts,
            transactions: container.transactions
        )
        let expense = try await txService.record(
            RecordTransactionInput(
                amount: 2_000,
                merchant: "生活支出",
                category: "生活",
                accountId: account.id,
                formType: .expense
            ),
            userId: userId
        ).transaction

        let debtService = DebtService(
            debts: container.debts,
            events: container.debtEvents,
            accounts: container.accounts,
            transactions: container.transactions
        )
        let debt = try await debtService.create(
            CreateDebtInput(
                lender: "测试贷款",
                approximateBalance: 5_000,
                installmentAmount: 1_000
            ),
            userId: userId
        )
        let repay = try await debtService.recordRepayment(
            RecordDebtRepaymentInput(
                debtId: debt.id,
                amount: 1_000,
                accountId: account.id
            ),
            userId: userId
        )

        // Account: 10000 - 2000 - 1000 = 7000
        let txs = try await container.transactions.fetchAll(userId: userId)
        #expect(txs.count == 2)
        #expect(txs.contains { $0.id == expense.id && $0.amount.amount == 2_000 })
        #expect(txs.contains { $0.transactionType == .repayment && $0.amount.amount == 1_000 })
        let balance = AccountBalanceEngine.balance(account: account, transactions: txs)
        #expect(balance.amount == 7_000)
        #expect(repay.outstandingBalance?.amount == 4_000)

        // Debt + DebtEvent: 5000 - 1000 = 4000
        let storedDebt = try #require(await container.debts.fetch(id: debt.id))
        #expect(storedDebt.outstandingBalance?.amount == 4_000)
        let events = try await container.debtEvents.fetchAll(debtId: debt.id)
        #expect(events.contains { $0.type == .created })
        #expect(events.contains { $0.type == .repayment })

        // CashFlow / Home Summary
        let home = OverviewServiceContainer(
            repositories: container,
            financialAssisting: MockAIProvider()
        ).home
        let overview = try await home.loadOverview(userId: userId)

        #expect(overview.availableFunds.amount == 7_000)
        #expect(overview.monthlyLivingExpense.amount == 2_000)
        #expect(overview.monthlyDebtRepayment.amount == 1_000)
        #expect(overview.cashFlowProjections.count == CashFlowHorizon.allCases.count)
        #expect(overview.cashFlowProjections.allSatisfy { $0.endingBalance.currencyCode == "CNY" })

        let summary = FinancialSummaryEngine.summarize(
            .init(accounts: [account], transactions: txs, debts: [storedDebt])
        )
        #expect(summary.availableCash.amount == overview.availableFunds.amount)
        #expect(summary.monthlyExpense.amount == overview.monthlyLivingExpense.amount)
        #expect(summary.monthlyDebtPayment.amount == overview.monthlyDebtRepayment.amount)
    }
}
