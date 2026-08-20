import Foundation
import Testing
import YoushuDomain
import YoushuFoundation

@Suite("Financial risk production wiring")
struct FinancialRiskProductionWiringTests {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private let evaluatedAt = FinancialRiskPolicyVectorInputs.fixedEvaluatedAt
    private let safeBalance = Money(amount: 2_000, currencyCode: "CNY")

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func money(_ amount: Decimal) -> Money {
        Money(amount: amount, currencyCode: "CNY")
    }

    private func assess(
        accounts: [Account] = [],
        transactions: [Transaction] = [],
        debts: [Debt] = [],
        asOf: Date? = nil,
        debtInventoryLoadSucceeded: Bool = true,
        debtInventoryEstablishment: DebtInventoryEstablishmentState = .unestablished,
        debtImportInProgress: Bool = false,
        safeBalance overrideSafe: Money? = nil
    ) -> FinancialRiskAssessment {
        let userId = accounts.first?.userId
            ?? transactions.first?.userId
            ?? debts.first?.userId
            ?? UUID()
        let resolvedAccounts = accounts.isEmpty && !transactions.isEmpty
            ? [Account(userId: userId, name: "默认", type: .cash, openingBalance: money(10_000))]
            : accounts
        let source = FinancialContextBuilder.Source(
            accounts: resolvedAccounts,
            transactions: transactions,
            debts: debts,
            asOf: asOf ?? evaluatedAt,
            calendar: calendar,
            safeBalance: overrideSafe ?? safeBalance
        )
        let context = FinancialContextBuilder.build(source)
        let baseFacts = FinancialContextBuilder.monthlySummaryFacts(from: context)
        let facts = MonthlySummaryFactsEnricher.enrich(
            baseFacts,
            context: context,
            safeBalance: overrideSafe ?? safeBalance
        )
        let assembly = FinancialRiskAssessmentService.assemblyContext(
            source: source,
            context: context,
            enrichedFacts: facts,
            safeBalance: overrideSafe ?? safeBalance,
            debtInventoryLoadSucceeded: debtInventoryLoadSucceeded,
            debtInventoryEstablishment: debtInventoryEstablishment,
            debtImportInProgress: debtImportInProgress,
            evaluatedAt: source.asOf
        )
        return FinancialRiskAssessmentService.assess(assembly)
    }

    private func incomeTransaction(
        userId: UUID,
        accountId: UUID,
        amount: Decimal,
        on day: Date
    ) -> Transaction {
        Transaction(
            userId: userId,
            accountId: accountId,
            amount: money(amount),
            date: day,
            category: "工资",
            transactionType: .income
        )
    }

    private func expenseTransaction(
        userId: UUID,
        accountId: UUID,
        amount: Decimal,
        on day: Date
    ) -> Transaction {
        Transaction(
            userId: userId,
            accountId: accountId,
            amount: money(amount),
            date: day,
            category: "生活",
            transactionType: .expense
        )
    }

    private func repaymentTransaction(
        userId: UUID,
        accountId: UUID,
        amount: Decimal,
        on day: Date
    ) -> Transaction {
        Transaction(
            userId: userId,
            accountId: accountId,
            amount: money(amount),
            date: day,
            category: "还款",
            transactionType: .repayment
        )
    }

    // MARK: - P1–P10

    @Test("P1 healthy production assembly is safe")
    func p1Healthy() {
        let userId = UUID()
        let account = Account(
            userId: userId,
            name: "银行卡",
            type: .bankCard,
            openingBalance: money(25_000)
        )
        let asOf = date(2024, 6, 15)
        let debt = Debt(
            userId: userId,
            lender: "低息贷",
            outstandingBalance: money(5_000),
            installmentAmount: money(1_000),
            paymentFrequency: .monthly,
            interestRate: Decimal(string: "0.05"),
            status: .active,
            profileCompleteness: 0.9
        )
        let txs = [
            incomeTransaction(userId: userId, accountId: account.id, amount: 12_000, on: date(2024, 6, 5)),
            expenseTransaction(userId: userId, accountId: account.id, amount: 4_000, on: date(2024, 6, 8)),
        ]
        let assessment = assess(
            accounts: [account],
            transactions: txs,
            debts: [debt],
            asOf: asOf,
            debtInventoryEstablishment: .confirmedComplete
        )
        #expect(assessment.overallLevel == .safe)
        #expect(assessment.debtDataState == .knownDebt)
        #expect(assessment.signals.isEmpty)
    }

    @Test("P2 cash flow below safe balance yields warning")
    func p2CashFlowBelowSafe() {
        let userId = UUID()
        let account = Account(
            userId: userId,
            name: "银行",
            type: .bankCard,
            openingBalance: money(6_000)
        )
        let asOf = date(2024, 9, 1)
        let debt = Debt(
            userId: userId,
            lender: "分期",
            outstandingBalance: money(4_500),
            installmentAmount: money(4_500),
            dueDate: date(2024, 9, 25),
            status: .active,
            profileCompleteness: 0.9
        )
        let assessment = assess(
            accounts: [account],
            debts: [debt],
            asOf: asOf,
            debtInventoryEstablishment: .confirmedComplete
        )
        #expect(assessment.overallLevel == .warning)
        #expect(assessment.signals.map(\.reasonCode).contains(.cashFlowBelowSafeBalance))
    }

    @Test("P3 negative projected cash flow yields risk")
    func p3NegativeCashFlow() {
        let userId = UUID()
        let account = Account(
            userId: userId,
            name: "银行",
            type: .bankCard,
            openingBalance: money(7_000)
        )
        let asOf = date(2024, 9, 1)
        let debt = Debt(
            userId: userId,
            lender: "信用卡",
            outstandingBalance: money(8_000),
            installmentAmount: money(3_500),
            dueDate: date(2024, 9, 18),
            status: .active,
            profileCompleteness: 0.9
        )
        let rent = Transaction(
            userId: userId,
            accountId: account.id,
            amount: money(4_000),
            date: date(2024, 8, 18),
            merchant: "房租",
            category: "住房",
            transactionType: .expense,
            recurringRule: RecurringRule(frequency: .monthly, nextDate: date(2024, 9, 18))
        )
        let assessment = assess(
            accounts: [account],
            transactions: [rent],
            debts: [debt],
            asOf: asOf,
            debtInventoryEstablishment: .confirmedComplete
        )
        #expect(assessment.overallLevel == .risk)
        #expect(assessment.signals.map(\.reasonCode).contains(.negativeProjectedBalance))
    }

    @Test("P4 known no debt produces no debt signals")
    func p4KnownNoDebt() {
        let userId = UUID()
        let account = Account(userId: userId, name: "现金", type: .cash, openingBalance: money(8_000))
        let asOf = date(2024, 6, 10)
        let txs = [
            incomeTransaction(userId: userId, accountId: account.id, amount: 10_000, on: date(2024, 6, 3)),
            expenseTransaction(userId: userId, accountId: account.id, amount: 2_000, on: date(2024, 6, 5)),
        ]
        let assessment = assess(
            accounts: [account],
            transactions: txs,
            debts: [],
            asOf: asOf,
            debtInventoryEstablishment: .confirmedComplete
        )
        #expect(assessment.debtDataState == .knownNoDebt)
        #expect(assessment.signals.filter { $0.kind == .debt }.isEmpty)
        #expect(assessment.overallLevel == .safe)
    }

    private func completeHighCostDebt(
        userId: UUID,
        lender: String,
        outstanding: Decimal,
        installment: Decimal,
        overdue: Bool
    ) -> Debt {
        Debt(
            userId: userId,
            lender: lender,
            debtType: .creditCard,
            outstandingBalance: money(outstanding),
            installmentAmount: money(installment),
            paymentFrequency: .monthly,
            dueDate: date(2024, 6, 20),
            interestRate: Decimal(string: "0.22"),
            status: overdue ? .overdue : .active,
            profileCompleteness: 0.9
        )
    }

    @Test("P5 known debt high pressure yields warning")
    func p5KnownDebtHighPressure() {
        let userId = UUID()
        let account = Account(userId: userId, name: "现金", type: .cash, openingBalance: money(30_000))
        let asOf = date(2024, 6, 15)
        let debt = completeHighCostDebt(
            userId: userId,
            lender: "高息卡",
            outstanding: 10_000,
            installment: 1_000,
            overdue: true
        )
        let txs = [
            incomeTransaction(userId: userId, accountId: account.id, amount: 15_000, on: date(2024, 6, 5)),
        ]
        let assessment = assess(
            accounts: [account],
            transactions: txs,
            debts: [debt],
            asOf: asOf,
            debtInventoryEstablishment: .confirmedComplete
        )
        #expect(assessment.debtDataState == .knownDebt)
        #expect(assessment.overallLevel == .warning)
        #expect(assessment.signals.map(\.reasonCode).contains(.highDebtPressureScore))
    }

    @Test("P6 critical debt pressure yields risk")
    func p6CriticalDebt() {
        let userId = UUID()
        let account = Account(userId: userId, name: "现金", type: .cash, openingBalance: money(40_000))
        let asOf = date(2024, 6, 15)
        let debts = [
            completeHighCostDebt(
                userId: userId,
                lender: "卡A",
                outstanding: 15_000,
                installment: 1_500,
                overdue: true
            ),
            completeHighCostDebt(
                userId: userId,
                lender: "卡B",
                outstanding: 12_000,
                installment: 1_200,
                overdue: true
            ),
        ]
        let txs = [
            incomeTransaction(userId: userId, accountId: account.id, amount: 20_000, on: date(2024, 6, 5)),
        ]
        let assessment = assess(
            accounts: [account],
            transactions: txs,
            debts: debts,
            asOf: asOf,
            debtInventoryEstablishment: .confirmedComplete
        )
        #expect(assessment.debtDataState == .knownDebt)
        #expect(assessment.overallLevel == .risk)
        #expect(assessment.signals.map(\.reasonCode).contains(.criticalDebtPressure))
    }

    @Test("P7 partial debt allows DTI warning only")
    func p7PartialDebt() {
        let userId = UUID()
        let account = Account(userId: userId, name: "现金", type: .cash, openingBalance: money(12_000))
        let asOf = date(2024, 6, 15)
        let txs = [
            incomeTransaction(userId: userId, accountId: account.id, amount: 10_000, on: date(2024, 6, 5)),
            repaymentTransaction(userId: userId, accountId: account.id, amount: 2_500, on: date(2024, 6, 8)),
        ]
        let assessment = assess(accounts: [account], transactions: txs, debts: [], asOf: asOf)
        #expect(assessment.debtDataState == .partial)
        #expect(assessment.dataCompleteness.debt == .partial)
        #expect(assessment.signals.map(\.reasonCode) == [.highDebtPaymentToIncome])
        #expect(assessment.signals.filter { $0.reasonCode == .highDebtPressureScore }.isEmpty)
        #expect(assessment.signals.filter { $0.reasonCode == .criticalDebtPressure }.isEmpty)
    }

    @Test("P8 missing debt inventory records required unknown with repo success")
    func p8MissingDebt() {
        let userId = UUID()
        let account = Account(userId: userId, name: "现金", type: .cash, openingBalance: money(8_000))
        let asOf = date(2024, 6, 10)
        let txs = [
            incomeTransaction(userId: userId, accountId: account.id, amount: 10_000, on: date(2024, 6, 3)),
        ]
        let assessment = assess(
            accounts: [account],
            transactions: txs,
            debts: [],
            asOf: asOf,
            debtInventoryLoadSucceeded: true,
            debtInventoryEstablishment: .unestablished
        )
        #expect(assessment.debtDataState == .missing)
        #expect(assessment.dataCompleteness.debt == .missing)
        #expect(assessment.overallLevel == .safe)
        #expect(assessment.signals.filter { $0.kind == .debt }.isEmpty)
        #expect(assessment.dataCompleteness.requiredUnknownReasonCodes.contains(.debtDataMissing))
    }

    @Test("P9 zero income with expense yields warning")
    func p9ZeroIncomeWithExpense() {
        let userId = UUID()
        let account = Account(userId: userId, name: "现金", type: .cash, openingBalance: money(3_000))
        let asOf = date(2024, 6, 15)
        let txs = [
            expenseTransaction(userId: userId, accountId: account.id, amount: 1_500, on: date(2024, 6, 8)),
        ]
        let assessment = assess(accounts: [account], transactions: txs, debts: [], asOf: asOf)
        #expect(assessment.overallLevel == .warning)
        #expect(assessment.signals.map(\.reasonCode).contains(.zeroIncomeWithExpenses))
    }

    @Test("P10 missing cash flow projection skips CF signals and records unknown")
    func p10MissingCashFlowProjection() {
        let assessment = assess(accounts: [], transactions: [], debts: [])
        #expect(assessment.dataCompleteness.cashFlowProjection == .missing)
        #expect(assessment.dataCompleteness.requiredUnknownReasonCodes.contains(.cashFlowProjectionMissing))
        #expect(assessment.signals.filter { $0.kind == .cashFlow }.isEmpty)
    }

    // MARK: - Regressions C01 / E01 / E05

    @Test("C01 complete inventory with no open debt is knownNoDebt without debt pressure signals")
    func regressionC01KnownNoDebtGuard() {
        let userId = UUID()
        let account = Account(userId: userId, name: "现金", type: .cash, openingBalance: money(15_000))
        let asOf = date(2024, 6, 20)
        let paidOff = Debt(
            userId: userId,
            lender: "已结清",
            outstandingBalance: money(0),
            status: .paidOff
        )
        let txs = [
            incomeTransaction(userId: userId, accountId: account.id, amount: 12_000, on: date(2024, 6, 5)),
            expenseTransaction(userId: userId, accountId: account.id, amount: 3_000, on: date(2024, 6, 7)),
        ]
        let source = FinancialContextBuilder.Source(
            accounts: [account],
            transactions: txs,
            debts: [paidOff],
            asOf: asOf,
            calendar: calendar,
            safeBalance: safeBalance
        )
        let context = FinancialContextBuilder.build(source)
        let facts = MonthlySummaryFactsEnricher.enrich(
            FinancialContextBuilder.monthlySummaryFacts(from: context),
            context: context,
            safeBalance: safeBalance
        )
        #expect(facts.monthlyDebtPayment.amount == 0)

        let assessment = assess(
            accounts: [account],
            transactions: txs,
            debts: [paidOff],
            asOf: asOf,
            debtInventoryEstablishment: .confirmedComplete
        )
        #expect(assessment.debtDataState == .knownNoDebt)
        #expect(assessment.signals.filter { $0.kind == .debt }.isEmpty)
        #expect(assessment.overallLevel == .safe)
    }

    @Test("E01 partial debt with known repayment allows DTI warning when threshold met")
    func regressionE01PartialDebtWithRepayment() {
        let userId = UUID()
        let account = Account(userId: userId, name: "现金", type: .cash, openingBalance: money(20_000))
        let asOf = date(2024, 6, 15)
        let txs = [
            incomeTransaction(userId: userId, accountId: account.id, amount: 10_000, on: date(2024, 6, 4)),
            repaymentTransaction(userId: userId, accountId: account.id, amount: 2_500, on: date(2024, 6, 9)),
        ]
        let assessment = assess(accounts: [account], transactions: txs, debts: [], asOf: asOf)
        #expect(assessment.debtDataState == .partial)
        #expect(assessment.overallLevel == .warning)
        #expect(assessment.signals.map(\.reasonCode).contains(.highDebtPaymentToIncome))
        #expect(assessment.signals.filter { $0.reasonCode == .criticalDebtPressure }.isEmpty)
    }

    @Test("E05 missing debt inventory with repo success and unestablished inventory")
    func regressionE05MissingDebtInventory() {
        let userId = UUID()
        let account = Account(userId: userId, name: "现金", type: .cash, openingBalance: money(10_000))
        let asOf = date(2024, 6, 12)
        let txs = [
            incomeTransaction(userId: userId, accountId: account.id, amount: 8_000, on: date(2024, 6, 2)),
        ]
        let assessment = assess(
            accounts: [account],
            transactions: txs,
            debts: [],
            asOf: asOf,
            debtInventoryLoadSucceeded: true,
            debtInventoryEstablishment: .unestablished
        )
        #expect(assessment.debtDataState == .missing)
        #expect(assessment.overallLevel == .safe)
        #expect(assessment.dataCompleteness.requiredUnknownReasonCodes.contains(.debtDataMissing))
        #expect(assessment.signals.isEmpty)
    }

    // MARK: - Builder mapping smoke

    @Test("production input builder maps assembly without duplicating policy rules")
    func inputBuilderMapsFromAssemblyContext() {
        let userId = UUID()
        let account = Account(userId: userId, name: "现金", type: .cash, openingBalance: money(10_000))
        let asOf = date(2024, 6, 10)
        let source = FinancialContextBuilder.Source(
            accounts: [account],
            transactions: [
                incomeTransaction(userId: userId, accountId: account.id, amount: 8_000, on: date(2024, 6, 3)),
            ],
            debts: [],
            asOf: asOf,
            calendar: calendar,
            safeBalance: safeBalance
        )
        let context = FinancialContextBuilder.build(source)
        let facts = MonthlySummaryFactsEnricher.enrich(
            FinancialContextBuilder.monthlySummaryFacts(from: context),
            context: context,
            safeBalance: safeBalance
        )
        let assembly = FinancialRiskAssessmentService.assemblyContext(
            source: source,
            context: context,
            enrichedFacts: facts,
            safeBalance: safeBalance,
            debtInventoryLoadSucceeded: true,
            debtInventoryEstablishment: .confirmedComplete,
            evaluatedAt: asOf
        )
        let input = FinancialRiskPolicyInputBuilder.build(assembly)
        #expect(input.evaluatedAt == asOf)
        #expect(input.debtDataState == .knownNoDebt)
        #expect(input.monthlyIncome.isKnown)
        #expect(input.dataCompleteness.income == .known)
    }
}
