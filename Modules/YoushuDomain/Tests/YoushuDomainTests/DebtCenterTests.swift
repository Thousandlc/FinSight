import Foundation
import Testing
import YoushuData
import YoushuDomain
import YoushuFoundation

@Suite("Debt center calculator")
struct DebtCenterCalculatorTests {
    @Test("aggregates total debt and monthly repayment across debts")
    func multiDebtSummary() {
        let userId = UUID()
        let debts = [
            Debt(
                userId: userId,
                lender: "招行",
                debtType: .creditCard,
                outstandingBalance: Money(amount: 5000, currencyCode: "CNY"),
                installmentAmount: Money(amount: 1000, currencyCode: "CNY"),
                paymentFrequency: .monthly,
                interestRate: Decimal(string: "0.18"),
                status: .active
            ),
            Debt(
                userId: userId,
                lender: "消金",
                debtType: .consumerLoan,
                outstandingBalance: Money(amount: 3000, currencyCode: "CNY"),
                installmentAmount: Money(amount: 600, currencyCode: "CNY"),
                paymentFrequency: .monthly,
                interestRate: Decimal(string: "0.24"),
                status: .active
            ),
            Debt(
                userId: userId,
                lender: "已结清",
                outstandingBalance: Money(amount: 999, currencyCode: "CNY"),
                status: .paidOff
            ),
        ]

        #expect(DebtCenterCalculator.totalDebt(debts: debts).amount == 8000)
        #expect(DebtCenterCalculator.estimatedMonthlyRepayment(debts: debts).amount == 1600)
        #expect(DebtCenterCalculator.highCostDebts(debts: debts).count == 2)
    }

    @Test("estimates debt-free date from remaining installments")
    func debtFreeFromRemaining() {
        let asOf = Date(timeIntervalSince1970: 1_700_000_000)
        let debt = Debt(
            userId: UUID(),
            outstandingBalance: Money(amount: 6000, currencyCode: "CNY"),
            installmentAmount: Money(amount: 1000, currencyCode: "CNY"),
            paymentFrequency: .monthly,
            remainingInstallments: 6,
            status: .active
        )
        let estimate = DebtCenterCalculator.estimatePayoffDate(for: debt, asOf: asOf)
        let expected = Calendar.current.date(byAdding: .month, value: 6, to: asOf)
        #expect(estimate == expected)
    }

    @Test("uses maturity date when available")
    func maturityDate() {
        let maturity = Date(timeIntervalSince1970: 1_800_000_000)
        let debt = Debt(
            userId: UUID(),
            outstandingBalance: Money(amount: 1000, currencyCode: "CNY"),
            maturityDate: maturity,
            status: .active
        )
        #expect(DebtCenterCalculator.estimatePayoffDate(for: debt) == maturity)
    }

    @Test("next payment picks earliest due date")
    func nextPayment() {
        let sooner = Date(timeIntervalSince1970: 1_700_100_000)
        let later = Date(timeIntervalSince1970: 1_700_200_000)
        let debts = [
            Debt(
                userId: UUID(),
                lender: "B",
                outstandingBalance: Money(amount: 1, currencyCode: "CNY"),
                currentDue: Money(amount: 200, currencyCode: "CNY"),
                dueDate: later,
                status: .active
            ),
            Debt(
                userId: UUID(),
                lender: "A",
                outstandingBalance: Money(amount: 1, currencyCode: "CNY"),
                currentDue: Money(amount: 100, currencyCode: "CNY"),
                dueDate: sooner,
                status: .active
            ),
        ]
        let next = DebtCenterCalculator.nextPayment(debts: debts, asOf: Date(timeIntervalSince1970: 1_700_000_000))
        #expect(next?.debt.lender == "A")
        #expect(next?.amount.amount == 100)
    }

    @Test("pressure rises with overdue and high-cost debts")
    func pressure() {
        let low = [
            Debt(
                userId: UUID(),
                outstandingBalance: Money(amount: 1000, currencyCode: "CNY"),
                installmentAmount: Money(amount: 200, currencyCode: "CNY"),
                paymentFrequency: .monthly,
                interestRate: Decimal(string: "0.05"),
                status: .active
            ),
        ]
        let high = [
            Debt(
                userId: UUID(),
                debtType: .creditCard,
                outstandingBalance: Money(amount: 10000, currencyCode: "CNY"),
                interestRate: Decimal(string: "0.22"),
                status: .overdue
            ),
        ]
        let lowScore = DebtCenterCalculator.debtPressureScore(debts: low)
        let highScore = DebtCenterCalculator.debtPressureScore(debts: high)
        #expect(highScore > lowScore)
        #expect(DebtCenterCalculator.debtPressureLevel(score: highScore) == .high
            || DebtCenterCalculator.debtPressureLevel(score: highScore) == .critical)
    }
}

@Suite("Debt service")
struct DebtServiceTests {
    private func makeEnv() async throws -> (
        service: DebtService,
        container: RepositoryContainer,
        userId: UUID,
        account: Account
    ) {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await container.users.upsert(User(id: userId, displayName: "Tester"))
        let account = Account(userId: userId, name: "现金", type: .cash, openingBalance: Money(amount: 5000, currencyCode: "CNY"))
        try await container.accounts.upsert(account)
        let service = DebtService(
            debts: container.debts,
            events: container.debtEvents,
            accounts: container.accounts,
            transactions: container.transactions
        )
        return (service, container, userId, account)
    }

    @Test("creates debt with only lender and approximate balance")
    func createMinimal() async throws {
        let env = try await makeEnv()
        let debt = try await env.service.create(
            CreateDebtInput(lender: "朋友借支", approximateBalance: 2000),
            userId: env.userId
        )
        #expect(debt.lender == "朋友借支")
        #expect(debt.outstandingBalance?.amount == 2000)
        #expect(debt.productName == nil)
        #expect(debt.status == .active)
        #expect(debt.profileCompleteness > 0)
        #expect(debt.profileCompleteness < 0.5)

        let events = try await env.container.debtEvents.fetchAll(debtId: debt.id)
        #expect(events.count == 1)
        #expect(events[0].type == .created)
    }

    @Test("updates debt and records manual edit event")
    func updateDebt() async throws {
        let env = try await makeEnv()
        let created = try await env.service.create(
            CreateDebtInput(lender: "消金A", approximateBalance: 3000, debtType: .consumerLoan),
            userId: env.userId
        )
        let updated = try await env.service.update(
            UpdateDebtInput(
                debtId: created.id,
                lender: "消金A",
                approximateBalance: 2500,
                productName: "随借随还",
                debtType: .consumerLoan,
                installmentAmount: 500,
                paymentFrequency: .monthly,
                remainingInstallments: 5,
                status: .active
            ),
            userId: env.userId
        )
        #expect(updated.outstandingBalance?.amount == 2500)
        #expect(updated.productName == "随借随还")
        #expect(updated.remainingInstallments == 5)

        let events = try await env.container.debtEvents.fetchAll(debtId: created.id)
        #expect(events.contains { $0.type == .manualEdit })
    }

    @Test("deletes debt and cascades events")
    func deleteDebt() async throws {
        let env = try await makeEnv()
        let debt = try await env.service.create(
            CreateDebtInput(lender: "X", approximateBalance: 100),
            userId: env.userId
        )
        try await env.service.delete(debtId: debt.id, userId: env.userId)
        let fetched = try await env.container.debts.fetch(id: debt.id)
        #expect(fetched == nil)
        let events = try await env.container.debtEvents.fetchAll(debtId: debt.id)
        #expect(events.isEmpty)
    }

    @Test("repayment reduces principal and remaining installments")
    func repayment() async throws {
        let env = try await makeEnv()
        let debt = try await env.service.create(
            CreateDebtInput(
                lender: "银行贷",
                approximateBalance: 1000,
                debtType: .bankLoan,
                installmentAmount: 250,
                paymentFrequency: .monthly,
                remainingInstallments: 4
            ),
            userId: env.userId
        )
        let after = try await env.service.recordRepayment(
            RecordDebtRepaymentInput(debtId: debt.id, amount: 250, accountId: env.account.id),
            userId: env.userId
        )
        #expect(after.outstandingBalance?.amount == 750)
        #expect(after.outstandingPrincipal?.amount == 750)
        #expect(after.remainingInstallments == 3)
        #expect(after.status == .active)

        let events = try await env.container.debtEvents.fetchAll(debtId: debt.id)
        #expect(events.contains { $0.type == .repayment })

        let txs = try await env.container.transactions.fetchAll(relatedDebtId: debt.id)
        #expect(txs.count == 1)
        #expect(txs[0].transactionType == .repayment)
    }

    @Test("continuous repayments via debt service do not double-count")
    func continuousRepaymentsNoDoubleCount() async throws {
        let env = try await makeEnv()
        let debt = try await env.service.create(
            CreateDebtInput(
                lender: "分期贷",
                approximateBalance: 2400,
                installmentAmount: 800,
                remainingInstallments: 3
            ),
            userId: env.userId
        )
        _ = try await env.service.recordRepayment(
            RecordDebtRepaymentInput(debtId: debt.id, amount: 800),
            userId: env.userId
        )
        let afterSecond = try await env.service.recordRepayment(
            RecordDebtRepaymentInput(debtId: debt.id, amount: 800),
            userId: env.userId
        )
        #expect(afterSecond.outstandingBalance?.amount == 800)
        #expect(afterSecond.remainingInstallments == 1)
        let events = try await env.container.debtEvents.fetchAll(debtId: debt.id)
        #expect(events.filter { $0.type == .repayment }.count == 2)
    }

    @Test("full repayment marks paid off and zero remaining installments")
    func payoff() async throws {
        let env = try await makeEnv()
        let debt = try await env.service.create(
            CreateDebtInput(lender: "卡", approximateBalance: 400, remainingInstallments: 2),
            userId: env.userId
        )
        let after = try await env.service.recordRepayment(
            RecordDebtRepaymentInput(debtId: debt.id, amount: 400),
            userId: env.userId
        )
        #expect(after.outstandingBalance?.amount == 0)
        #expect(after.status == .paidOff)
        #expect(after.remainingInstallments == 0)
    }

    @Test("debt list snapshot includes center metrics")
    func listSnapshot() async throws {
        let env = try await makeEnv()
        _ = try await env.service.create(
            CreateDebtInput(
                lender: "招行",
                approximateBalance: 5000,
                debtType: .creditCard,
                installmentAmount: 1000,
                paymentFrequency: .monthly,
                dueDate: Date().addingTimeInterval(86400 * 3),
                remainingInstallments: 5,
                interestRate: Decimal(string: "0.18")
            ),
            userId: env.userId
        )
        _ = try await env.service.recordRepayment(
            RecordDebtRepaymentInput(debtId: (try await env.container.debts.fetchAll(userId: env.userId))[0].id, amount: 1000),
            userId: env.userId
        )

        let listService = DebtListService(debts: env.container.debts, events: env.container.debtEvents)
        let snapshot = try await listService.loadSnapshot(userId: env.userId)
        #expect(snapshot.totalOutstanding.amount == 4000)
        #expect(snapshot.estimatedMonthlyRepayment.amount == 1000)
        #expect(snapshot.lastRepaymentAmount?.amount == 1000)
        #expect(snapshot.debtFreeEstimate != nil)
        #expect(!snapshot.highCostDebts.isEmpty)
    }

    @Test("filters debts by type status and lender")
    func filters() {
        let userId = UUID()
        let debts = [
            Debt(userId: userId, lender: "招商银行", debtType: .creditCard, outstandingBalance: Money(amount: 1, currencyCode: "CNY"), status: .active),
            Debt(userId: userId, lender: "微粒贷", debtType: .consumerLoan, outstandingBalance: Money(amount: 1, currencyCode: "CNY"), status: .overdue),
            Debt(userId: userId, lender: "朋友", debtType: .personalLoan, outstandingBalance: Money(amount: 1, currencyCode: "CNY"), status: .paidOff),
        ]
        let byType = DebtListService.filtered(debts, sort: .type, typeFilter: .creditCard)
        #expect(byType.count == 1)
        #expect(byType[0].lender == "招商银行")

        let byStatus = DebtListService.filtered(debts, sort: .status, statusFilter: .overdue)
        #expect(byStatus.count == 1)

        let byLender = DebtListService.filtered(debts, sort: .lender, lenderQuery: "朋友")
        #expect(byLender.count == 1)
    }

    @Test("applies bill update overdue and installment completed events")
    func eventTypes() {
        var debt = Debt(
            userId: UUID(),
            outstandingBalance: Money(amount: 1000, currencyCode: "CNY"),
            remainingInstallments: 2,
            status: .active
        )
        let events = [
            DebtEvent(debtId: debt.id, userId: debt.userId, type: .billUpdated, amount: Money(amount: 1200, currencyCode: "CNY")),
            DebtEvent(debtId: debt.id, userId: debt.userId, type: .overdue),
            DebtEvent(debtId: debt.id, userId: debt.userId, type: .installmentCompleted),
        ]
        debt = DebtBalanceCalculator.apply(events: events, to: debt)
        #expect(debt.outstandingBalance?.amount == 1200)
        #expect(debt.status == .overdue)
        #expect(debt.remainingInstallments == 0)
    }
}
