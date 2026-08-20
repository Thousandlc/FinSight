import Foundation
import Testing
import YoushuDomain
import YoushuFoundation

@Suite("Transaction model")
struct TransactionModelTests {
    @Test("creates transaction with required fields and types")
    func createTransaction() {
        let userId = UUID()
        let accountId = UUID()
        let tx = Transaction(
            userId: userId,
            accountId: accountId,
            amount: Money(amount: Decimal(string: "128.50")!, currencyCode: "CNY"),
            merchant: "瑞幸咖啡",
            category: "餐饮",
            transactionType: .expense,
            tags: ["咖啡"],
            sourceImageId: "img-1",
            recognitionConfidence: 0.91,
            source: .screenshot
        )

        #expect(tx.amount.amount == Decimal(string: "128.50")!)
        #expect(tx.merchant == "瑞幸咖啡")
        #expect(tx.transactionType == .expense)
        #expect(tx.source == .screenshot)
        #expect(tx.recognitionConfidence == 0.91)
        #expect(tx.currencyCode == "CNY")
    }

    @Test("supports all MVP transaction types")
    func allTypes() {
        let expected: [TransactionType] = [
            .expense, .income, .transfer, .refund, .reimbursement,
            .borrowing, .repayment, .investmentBuy, .investmentSell,
        ]
        #expect(TransactionType.allCases == expected)
    }

    @Test("clamps recognition confidence to 0...1")
    func clampConfidence() {
        let userId = UUID()
        let accountId = UUID()
        let high = Transaction(
            userId: userId,
            accountId: accountId,
            amount: .zeroCNY,
            transactionType: .income,
            recognitionConfidence: 1.5
        )
        let low = Transaction(
            userId: userId,
            accountId: accountId,
            amount: .zeroCNY,
            transactionType: .income,
            recognitionConfidence: -0.2
        )
        #expect(high.recognitionConfidence == 1)
        #expect(low.recognitionConfidence == 0)
    }
}

@Suite("Debt model")
struct DebtModelTests {
    @Test("creates debt with amounts and progressive profile score")
    func createDebt() {
        let debt = Debt(
            userId: UUID(),
            lender: "招商银行",
            productName: "信用卡",
            debtType: .creditCard,
            originalAmount: Money(amount: 10000, currencyCode: "CNY"),
            outstandingPrincipal: Money(amount: 8000, currencyCode: "CNY"),
            outstandingBalance: Money(amount: 8200, currencyCode: "CNY"),
            currentDue: Money(amount: 500, currencyCode: "CNY"),
            minimumDue: Money(amount: 200, currencyCode: "CNY"),
            installmentAmount: Money(amount: 500, currencyCode: "CNY"),
            paymentFrequency: .monthly,
            dueDate: Date(),
            remainingInstallments: 12,
            interestRate: Decimal(string: "0.18"),
            status: .active,
            source: .screenshot
        )

        #expect(debt.lender == "招商银行")
        #expect(debt.status == .active)
        #expect(debt.source == .screenshot)
        #expect(debt.profileCompleteness > 0.8)
    }

    @Test("computes total outstanding from debts")
    func debtBalances() {
        let userId = UUID()
        let debts = [
            Debt(
                userId: userId,
                outstandingBalance: Money(amount: 1000, currencyCode: "CNY"),
                status: .active
            ),
            Debt(
                userId: userId,
                outstandingBalance: Money(amount: 2500, currencyCode: "CNY"),
                status: .overdue
            ),
            Debt(
                userId: userId,
                outstandingBalance: Money(amount: 9999, currencyCode: "CNY"),
                status: .paidOff
            ),
        ]

        let total = DebtBalanceCalculator.totalOutstanding(debts: debts)
        #expect(total.amount == 3500)
    }

    @Test("applies repayment debt events to outstanding balance")
    func debtEvents() {
        let userId = UUID()
        var debt = Debt(
            userId: userId,
            originalAmount: Money(amount: 1000, currencyCode: "CNY"),
            outstandingPrincipal: Money(amount: 1000, currencyCode: "CNY"),
            outstandingBalance: Money(amount: 1000, currencyCode: "CNY"),
            remainingInstallments: 2,
            status: .active,
            source: .userInput
        )

        let events = [
            DebtEvent(
                debtId: debt.id,
                userId: userId,
                type: .repayment,
                amount: Money(amount: 400, currencyCode: "CNY")
            ),
            DebtEvent(
                debtId: debt.id,
                userId: userId,
                type: .repayment,
                amount: Money(amount: 600, currencyCode: "CNY")
            ),
        ]

        debt = DebtBalanceCalculator.apply(events: events, to: debt)
        #expect(debt.outstandingBalance?.amount == 0)
        #expect(debt.status == .paidOff)
        #expect(debt.remainingInstallments == 0)
    }

    @Test("links transaction to debt via relatedDebtId")
    func transactionDebtLink() {
        let userId = UUID()
        let accountId = UUID()
        let debtId = UUID()
        let tx = Transaction(
            userId: userId,
            accountId: accountId,
            amount: Money(amount: 500, currencyCode: "CNY"),
            transactionType: .repayment,
            relatedDebtId: debtId,
            source: .manual
        )
        #expect(tx.relatedDebtId == debtId)
        #expect(tx.transactionType == .repayment)
    }
}

@Suite("Account balance")
struct AccountBalanceTests {
    @Test("derives balance from opening + transactions")
    func deriveBalance() {
        let userId = UUID()
        let account = Account(
            userId: userId,
            name: "现金",
            type: .cash,
            openingBalance: Money(amount: 1000, currencyCode: "CNY")
        )
        let txs = [
            Transaction(
                userId: userId,
                accountId: account.id,
                amount: Money(amount: 200, currencyCode: "CNY"),
                transactionType: .expense
            ),
            Transaction(
                userId: userId,
                accountId: account.id,
                amount: Money(amount: 50, currencyCode: "CNY"),
                transactionType: .income
            ),
        ]
        let balance = AccountBalanceEngine.balance(account: account, transactions: txs)
        #expect(balance.amount == 850)
    }
}
