import Foundation
import Testing
import YoushuData
import YoushuDomain
import YoushuFoundation

@Suite("Debt matcher")
struct DebtMatcherTests {
    private func openDebt(
        userId: UUID,
        lender: String,
        installment: Decimal? = nil,
        currentDue: Decimal? = nil,
        dueDay: Int? = nil,
        linkedAccountId: UUID? = nil
    ) -> Debt {
        var due: Date?
        if let dueDay {
            var comps = DateComponents()
            comps.year = 2024
            comps.month = 6
            comps.day = dueDay
            due = Calendar.current.date(from: comps)
        }
        return Debt(
            userId: userId,
            lender: lender,
            productName: lender + "贷",
            debtType: .consumerLoan,
            outstandingPrincipal: Money(amount: 10_000, currencyCode: "CNY"),
            outstandingBalance: Money(amount: 10_000, currencyCode: "CNY"),
            currentDue: currentDue.map { Money(amount: $0, currencyCode: "CNY") },
            installmentAmount: installment.map { Money(amount: $0, currencyCode: "CNY") },
            paymentFrequency: .monthly,
            dueDate: due,
            remainingInstallments: 10,
            status: .active,
            linkedAccountId: linkedAccountId
        )
    }

    private func date(year: Int, month: Int, day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test("correctly matches repayment by merchant, installment, and due day")
    func correctMatch() {
        let userId = UUID()
        let debt = openDebt(userId: userId, lender: "微粒贷", installment: 800, dueDay: 15)
        let tx = Transaction(
            userId: userId,
            accountId: UUID(),
            amount: Money(amount: 800, currencyCode: "CNY"),
            date: date(year: 2024, month: 7, day: 15),
            merchant: "微粒贷还款",
            transactionType: .repayment
        )
        let result = DebtMatcher.match(
            transaction: tx,
            context: .init(debts: [debt])
        )
        #expect(result.status == .matched)
        #expect(result.matchedDebtId == debt.id)
        #expect(result.confidence >= DebtMatcher.autoLinkConfidence)
    }

    @Test("ambiguous when multiple debts share similar amounts and close scores")
    func ambiguousSimilarAmounts() {
        let userId = UUID()
        let d1 = openDebt(userId: userId, lender: "借呗", installment: 500, dueDay: 10)
        let d2 = openDebt(userId: userId, lender: "备用金", installment: 500, dueDay: 10)
        let tx = Transaction(
            userId: userId,
            accountId: UUID(),
            amount: Money(amount: 500, currencyCode: "CNY"),
            date: date(year: 2024, month: 8, day: 10),
            merchant: "还款",
            transactionType: .repayment
        )
        let result = DebtMatcher.match(
            transaction: tx,
            context: .init(debts: [d1, d2])
        )
        #expect(result.status == .ambiguous)
        #expect(result.candidateDebtIds.count >= 2)
    }

    @Test("unmatched when confidence is too low")
    func unmatched() {
        let userId = UUID()
        let debt = openDebt(userId: userId, lender: "招行信用卡", installment: 2000)
        let tx = Transaction(
            userId: userId,
            accountId: UUID(),
            amount: Money(amount: 36, currencyCode: "CNY"),
            merchant: "瑞幸咖啡",
            category: "餐饮",
            transactionType: .expense
        )
        let result = DebtMatcher.match(transaction: tx, context: .init(debts: [debt]))
        #expect(result.status == .unmatched)
    }

    @Test("historical behavior boosts confidence")
    func historyBoost() {
        let userId = UUID()
        let accountId = UUID()
        let debt = openDebt(userId: userId, lender: "消金A", installment: 600)
        let history = [
            Transaction(
                userId: userId,
                accountId: accountId,
                amount: Money(amount: 600, currencyCode: "CNY"),
                merchant: "消金A",
                transactionType: .repayment,
                relatedDebtId: debt.id
            ),
        ]
        let tx = Transaction(
            userId: userId,
            accountId: accountId,
            amount: Money(amount: 600, currencyCode: "CNY"),
            merchant: "消金A",
            transactionType: .repayment
        )
        let result = DebtMatcher.match(
            transaction: tx,
            context: .init(debts: [debt], historicalTransactions: history)
        )
        #expect(result.status == .matched)
        #expect(result.reason.contains("历史"))
    }
}

@Suite("Transaction debt linking")
struct TransactionDebtLinkingTests {
    private func makeEnv() async throws -> (
        linker: TransactionDebtLinkingService,
        txService: TransactionService,
        container: RepositoryContainer,
        userId: UUID,
        account: Account
    ) {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await container.users.upsert(User(id: userId, displayName: "T"))
        let account = Account(
            userId: userId,
            name: "银行卡",
            type: .bankCard,
            openingBalance: Money(amount: 20_000, currencyCode: "CNY")
        )
        try await container.accounts.upsert(account)

        let debtService = DebtService(
            debts: container.debts,
            events: container.debtEvents,
            accounts: container.accounts,
            transactions: container.transactions
        )
        let linker = TransactionDebtLinkingService(
            debts: container.debts,
            events: container.debtEvents,
            transactions: container.transactions,
            accounts: container.accounts,
            pendingLinks: container.pendingDebtLinks,
            suspectedDebts: container.suspectedDebts,
            debtManager: debtService
        )
        let txService = TransactionService(
            accounts: container.accounts,
            transactions: container.transactions,
            debtLinker: linker
        )
        return (linker, txService, container, userId, account)
    }

    private func dueOn(day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2024, month: 6, day: day))!
    }

    private func onDay(_ day: Int, month: Int = 7) -> Date {
        Calendar.current.date(from: DateComponents(year: 2024, month: month, day: day))!
    }

    /// 还款类型 + 商户 + 金额 + 还款日 → 达到自动关联阈值。
    private func linkableRepayment(
        userId: UUID,
        accountId: UUID,
        amount: Decimal,
        merchant: String,
        day: Int,
        month: Int = 7
    ) -> Transaction {
        Transaction(
            userId: userId,
            accountId: accountId,
            amount: Money(amount: amount, currencyCode: "CNY"),
            date: onDay(day, month: month),
            merchant: merchant,
            transactionType: .repayment
        )
    }

    @Test("single repayment updates debt via DebtEvent chain")
    func singleRepayment() async throws {
        let env = try await makeEnv()
        let debt = Debt(
            userId: env.userId,
            lender: "微粒贷",
            outstandingPrincipal: Money(amount: 5000, currencyCode: "CNY"),
            outstandingBalance: Money(amount: 5000, currencyCode: "CNY"),
            currentDue: Money(amount: 800, currencyCode: "CNY"),
            installmentAmount: Money(amount: 800, currencyCode: "CNY"),
            dueDate: dueOn(day: 15),
            remainingInstallments: 6,
            status: .active
        )
        try await env.container.debts.upsert(debt)

        let tx = linkableRepayment(
            userId: env.userId,
            accountId: env.account.id,
            amount: 800,
            merchant: "微粒贷还款",
            day: 15
        )
        try await env.container.transactions.upsert(tx)
        let outcome = try await env.linker.processNewTransaction(tx, userId: env.userId)
        guard case .autoLinked(let debtId, let eventId) = outcome else {
            Issue.record("Expected auto link, got \(outcome)")
            return
        }
        #expect(debtId == debt.id)

        let refreshedTx = try await env.container.transactions.fetch(id: tx.id)
        let refreshedDebt = try await env.container.debts.fetch(id: debt.id)
        let events = try await env.container.debtEvents.fetchAll(debtId: debt.id)

        #expect(refreshedTx?.relatedDebtId == debt.id)
        #expect(refreshedDebt?.outstandingBalance?.amount == 4200)
        #expect(refreshedDebt?.outstandingPrincipal?.amount == 4200)
        #expect(refreshedDebt?.currentDue?.amount == 0)
        #expect(refreshedDebt?.remainingInstallments == 5)
        let repaymentEvents = events.filter {
            $0.id == eventId && $0.type == DebtEventType.repayment && $0.relatedTransactionId == tx.id
        }
        #expect(repaymentEvents.count == 1)
    }

    @Test("continuous repayments reduce balance stepwise")
    func continuousRepayments() async throws {
        let env = try await makeEnv()
        let debt = Debt(
            userId: env.userId,
            lender: "借呗",
            outstandingPrincipal: Money(amount: 2400, currencyCode: "CNY"),
            outstandingBalance: Money(amount: 2400, currencyCode: "CNY"),
            installmentAmount: Money(amount: 800, currencyCode: "CNY"),
            dueDate: dueOn(day: 8),
            remainingInstallments: 3,
            status: .active
        )
        try await env.container.debts.upsert(debt)

        for month in 7...8 {
            let tx = linkableRepayment(
                userId: env.userId,
                accountId: env.account.id,
                amount: 800,
                merchant: "借呗还款",
                day: 8,
                month: month
            )
            try await env.container.transactions.upsert(tx)
            let outcome = try await env.linker.processNewTransaction(tx, userId: env.userId)
            guard case .autoLinked = outcome else {
                Issue.record("Expected auto link for month \(month), got \(outcome)")
                return
            }
        }

        let refreshed = try await env.container.debts.fetch(id: debt.id)
        #expect(refreshed?.outstandingBalance?.amount == 800)
        #expect(refreshed?.remainingInstallments == 1)
        let events = try await env.container.debtEvents.fetchAll(debtId: debt.id)
        #expect(events.filter { $0.type == DebtEventType.repayment }.count == 2)
    }

    @Test("overpayment clears debt to paid off")
    func overpaymentPayoff() async throws {
        let env = try await makeEnv()
        // 余额 500，但按每期 800 还款 → 超额清偿
        let debt = Debt(
            userId: env.userId,
            lender: "消费贷",
            outstandingPrincipal: Money(amount: 500, currencyCode: "CNY"),
            outstandingBalance: Money(amount: 500, currencyCode: "CNY"),
            installmentAmount: Money(amount: 800, currencyCode: "CNY"),
            dueDate: dueOn(day: 20),
            remainingInstallments: 1,
            status: .active
        )
        try await env.container.debts.upsert(debt)

        let tx = linkableRepayment(
            userId: env.userId,
            accountId: env.account.id,
            amount: 800,
            merchant: "消费贷还款",
            day: 20
        )
        try await env.container.transactions.upsert(tx)
        let outcome = try await env.linker.processNewTransaction(tx, userId: env.userId)
        guard case .autoLinked = outcome else {
            Issue.record("Expected auto link, got \(outcome)")
            return
        }

        let refreshed = try await env.container.debts.fetch(id: debt.id)
        #expect(refreshed?.status == .paidOff)
        #expect(refreshed?.outstandingBalance?.amount == 0)
        #expect(refreshed?.outstandingPrincipal?.amount == 0)
        #expect(refreshed?.remainingInstallments == 0)
    }

    @Test("exact balance repayment marks paid off")
    func exactPayoff() async throws {
        let env = try await makeEnv()
        let debt = Debt(
            userId: env.userId,
            lender: "结清贷",
            outstandingPrincipal: Money(amount: 1200, currencyCode: "CNY"),
            outstandingBalance: Money(amount: 1200, currencyCode: "CNY"),
            installmentAmount: Money(amount: 1200, currencyCode: "CNY"),
            dueDate: dueOn(day: 5),
            remainingInstallments: 1,
            status: .active
        )
        try await env.container.debts.upsert(debt)

        let tx = linkableRepayment(
            userId: env.userId,
            accountId: env.account.id,
            amount: 1200,
            merchant: "结清贷还款",
            day: 5
        )
        try await env.container.transactions.upsert(tx)
        _ = try await env.linker.processNewTransaction(tx, userId: env.userId)

        let refreshed = try await env.container.debts.fetch(id: debt.id)
        #expect(refreshed?.status == .paidOff)
        #expect(refreshed?.outstandingBalance?.amount == 0)
    }

    @Test("ambiguous match goes to pending confirmation then updates on confirm")
    func pendingOnAmbiguous() async throws {
        let env = try await makeEnv()
        let d1 = Debt(
            userId: env.userId,
            lender: "平台A",
            outstandingBalance: Money(amount: 3000, currencyCode: "CNY"),
            installmentAmount: Money(amount: 500, currencyCode: "CNY"),
            dueDate: dueOn(day: 10),
            status: .active
        )
        let d2 = Debt(
            userId: env.userId,
            lender: "平台B",
            outstandingBalance: Money(amount: 4000, currencyCode: "CNY"),
            installmentAmount: Money(amount: 500, currencyCode: "CNY"),
            dueDate: dueOn(day: 10),
            status: .active
        )
        try await env.container.debts.upsert(d1)
        try await env.container.debts.upsert(d2)

        let tx = linkableRepayment(
            userId: env.userId,
            accountId: env.account.id,
            amount: 500,
            merchant: "还款",
            day: 10
        )
        try await env.container.transactions.upsert(tx)
        let outcome = try await env.linker.processNewTransaction(tx, userId: env.userId)

        guard case .pendingConfirmation(let pending) = outcome else {
            Issue.record("Expected pending, got \(outcome)")
            return
        }
        #expect(pending.status == .pending)

        let before = try await env.container.debts.fetch(id: d1.id)
        #expect(before?.outstandingBalance?.amount == 3000)

        let confirmed = try await env.linker.confirmPendingLink(
            pendingId: pending.id,
            debtId: d1.id,
            userId: env.userId
        )
        #expect(confirmed.outstandingBalance?.amount == 2500)
        let linkedTx = try await env.container.transactions.fetch(id: tx.id)
        #expect(linkedTx?.relatedDebtId == d1.id)
        let events = try await env.container.debtEvents.fetchAll(debtId: d1.id)
        #expect(events.contains { $0.type == DebtEventType.repayment && $0.relatedTransactionId == tx.id })
    }

    @Test("wrong debt is not auto-selected when merchant points elsewhere")
    func wrongMatchAvoided() async throws {
        let env = try await makeEnv()
        let target = Debt(
            userId: env.userId,
            lender: "微粒贷",
            outstandingBalance: Money(amount: 2000, currencyCode: "CNY"),
            installmentAmount: Money(amount: 500, currencyCode: "CNY"),
            dueDate: dueOn(day: 12),
            status: .active
        )
        let other = Debt(
            userId: env.userId,
            lender: "借呗",
            outstandingBalance: Money(amount: 2000, currencyCode: "CNY"),
            installmentAmount: Money(amount: 500, currencyCode: "CNY"),
            dueDate: dueOn(day: 12),
            status: .active
        )
        try await env.container.debts.upsert(target)
        try await env.container.debts.upsert(other)

        let tx = linkableRepayment(
            userId: env.userId,
            accountId: env.account.id,
            amount: 500,
            merchant: "微粒贷",
            day: 12
        )
        try await env.container.transactions.upsert(tx)
        let outcome = try await env.linker.processNewTransaction(tx, userId: env.userId)

        // 商户指向微粒贷时：自动关联目标，或待确认且建议为目标
        switch outcome {
        case .autoLinked(let debtId, _):
            #expect(debtId == target.id)
        case .pendingConfirmation(let pending):
            #expect(pending.suggestedDebtId == target.id)
        default:
            Issue.record("Unexpected outcome \(outcome)")
        }
        let otherDebt = try await env.container.debts.fetch(id: other.id)
        #expect(otherDebt?.outstandingBalance?.amount == 2000)
    }

    @Test("unmatched coffee spend does not touch debt")
    func unmatchedDoesNotUpdate() async throws {
        let env = try await makeEnv()
        let debt = Debt(
            userId: env.userId,
            lender: "招行信用卡",
            outstandingBalance: Money(amount: 9000, currencyCode: "CNY"),
            installmentAmount: Money(amount: 2000, currencyCode: "CNY"),
            status: .active
        )
        try await env.container.debts.upsert(debt)

        let tx = try await env.txService.record(
            RecordTransactionInput(
                amount: 36,
                merchant: "瑞幸咖啡",
                category: "餐饮",
                accountId: env.account.id,
                formType: .expense
            ),
            userId: env.userId
        ).transaction
        #expect(tx.relatedDebtId == nil)
        let refreshed = try await env.container.debts.fetch(id: debt.id)
        #expect(refreshed?.outstandingBalance?.amount == 9000)
        let events = try await env.container.debtEvents.fetchAll(debtId: debt.id)
        #expect(events.filter { $0.type == DebtEventType.repayment }.isEmpty)
    }

    @Test("detects suspected recurring loan repayments")
    func suspectedRecurring() async throws {
        let env = try await makeEnv()
        let calendar = Calendar.current
        for month in 1...3 {
            let date = calendar.date(from: DateComponents(year: 2024, month: month, day: 12))!
            try await env.container.transactions.upsert(
                Transaction(
                    userId: env.userId,
                    accountId: env.account.id,
                    amount: Money(amount: 999, currencyCode: "CNY"),
                    date: date,
                    merchant: "某消金平台",
                    category: "生活",
                    transactionType: .expense
                )
            )
        }

        let suspected = try await env.linker.refreshSuspectedDebts(userId: env.userId)
        #expect(suspected.count >= 1)
        #expect(suspected[0].merchant == "某消金平台")
        #expect(suspected[0].occurrenceCount == 3)

        let debt = try await env.linker.confirmSuspectedDebt(
            suspectedId: suspected[0].id,
            userId: env.userId
        )
        #expect(debt.lender == suspected[0].merchant)
        #expect(debt.source == .transactionInference)
        #expect(debt.installmentAmount?.amount == 999)

        let txs = try await env.container.transactions.fetchAll(userId: env.userId)
        #expect(txs.filter { $0.relatedDebtId == debt.id }.count == 3)
        let events = try await env.container.debtEvents.fetchAll(debtId: debt.id)
        #expect(events.contains { $0.type == DebtEventType.created })
        #expect(events.filter { $0.type == DebtEventType.repayment }.isEmpty)
    }
}
