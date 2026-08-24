import Foundation
import Testing
import YoushuDomain
import YoushuFoundation

@Suite("Debt derived completeness downstream")
struct DebtDerivedCompletenessTests {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    @Test("context builder marks all-unknown outstanding and monthly as missing")
    func contextBuilderUnknownDerivedDebt() {
        let userId = UUID()
        let account = Account(
            userId: userId,
            name: "银行",
            type: .bankCard,
            openingBalance: Money(amount: 1_000, currencyCode: "CNY")
        )
        let debts = [
            Debt(userId: userId, outstandingBalance: nil, dueDate: date(2024, 9, 18), status: .active),
        ]
        let context = FinancialContextBuilder.build(
            .init(
                accounts: [account],
                transactions: [],
                debts: debts,
                asOf: date(2024, 9, 1),
                calendar: calendar
            )
        )
        #expect(context.totalDebtAvailability == .missing)
        #expect(context.estimatedMonthlyRepaymentAvailability == .missing)
        #expect(context.totalDebt.amount == 0)
        #expect(context.estimatedMonthlyRepayment.amount == 0)
    }

    @Test("assistant fact pack omits invented zero debt amounts")
    func factPackOmitsUnknownZeros() {
        let context = FinancialContext(
            totalDebt: .zeroCNY,
            totalDebtAvailability: .missing,
            estimatedMonthlyRepayment: .zeroCNY,
            estimatedMonthlyRepaymentAvailability: .missing,
            hasAccounts: true,
            hasDebts: true
        )
        let pack = FinancialAnswerFactBuilder.build(intent: .totalDebt, context: context)
        #expect(pack.amounts["totalDebt"] == nil)
        #expect(pack.amounts["estimatedMonthlyRepayment"] == nil)
        #expect(pack.unknowns.contains("部分余额未知"))
        #expect(pack.unknowns.contains("预计每月还款信息不完整"))
    }

    @Test("mixed outstanding fact pack keeps subtotal and incomplete unknown")
    func factPackMixedOutstanding() {
        let context = FinancialContext(
            totalDebt: Money(amount: 10_000, currencyCode: "CNY"),
            totalDebtAvailability: .partial,
            estimatedMonthlyRepayment: Money(amount: 1_000, currencyCode: "CNY"),
            estimatedMonthlyRepaymentAvailability: .known,
            hasAccounts: true,
            hasDebts: true
        )
        let pack = FinancialAnswerFactBuilder.build(intent: .totalDebt, context: context)
        #expect(pack.amounts["totalDebt"]?.amount == 10_000)
        #expect(pack.unknowns.contains("部分余额未知"))
        #expect(pack.amounts["estimatedMonthlyRepayment"]?.amount == 1_000)
    }

    @Test("insight due pack omits dueAmount when next payment amount is unknown")
    func insightOmitsInventedDueAmount() {
        let asOf = date(2024, 9, 1)
        let debts = [
            Debt(
                userId: UUID(),
                lender: "招行",
                outstandingBalance: Money(amount: 8_000, currencyCode: "CNY"),
                dueDate: date(2024, 9, 10),
                status: .active
            ),
        ]
        let context = FinancialContext(asOf: asOf, currencyCode: "CNY")
        let packs = FinancialInsightGenerator.generate(
            context: context,
            debts: debts,
            calendar: calendar
        )
        let due = packs.first { $0.type == .debtRisk && $0.facts["lender"] == "招行" }
        #expect(due != nil)
        #expect(due?.amounts["dueAmount"] == nil)
        #expect(due?.amounts.values.contains { $0.amount == 0 } != true)
    }

    @Test("DTO omits unknown monthly repayment instead of encoding zero")
    func dtoOmitsMissingMonthlyRepayment() throws {
        let context = FinancialContext(
            totalDebt: .zeroCNY,
            totalDebtAvailability: .missing,
            estimatedMonthlyRepayment: .zeroCNY,
            estimatedMonthlyRepaymentAvailability: .missing,
            hasDebts: true
        )
        let dto = FinancialAssistantContextMapper.map(
            context: context,
            safeBalance: Money(amount: 2_000, currencyCode: "CNY")
        )
        #expect(dto.debt.totalOutstanding == nil)
        #expect(dto.debt.estimatedMonthlyRepayment == nil)
        #expect(dto.debt.totalOutstandingAvailability == .missing)
        #expect(dto.debt.estimatedMonthlyRepaymentAvailability == .missing)
        let json = try FinancialAssistantContextSerializer.contextJSONString(dto)
        #expect(json.contains("\"estimatedMonthlyRepayment\":null") || !json.contains("\"estimatedMonthlyRepayment\":{\"amount\":0"))
    }

    @Test("purchase scenario does not treat unknown monthly estimate as a payment fact")
    func purchaseDoesNotUseUnknownMonthlyEstimate() {
        let context = FinancialContext(
            availableCash: Money(amount: 8_000, currencyCode: "CNY"),
            monthlyIncome: Money(amount: 10_000, currencyCode: "CNY"),
            monthlyExpense: Money(amount: 3_000, currencyCode: "CNY"),
            monthlyDebtPayment: Money(amount: 500, currencyCode: "CNY"),
            estimatedMonthlyRepayment: .zeroCNY,
            estimatedMonthlyRepaymentAvailability: .missing,
            hasAccounts: true,
            hasTransactions: true,
            hasDebts: true
        )
        let scenario = PurchaseScenarioEngine.evaluate(
            purchaseAmount: Money(amount: 100, currencyCode: "CNY"),
            context: context
        )
        #expect(scenario.factPack.amounts["debtPayments"]?.amount == 500)
        #expect(scenario.factPack.amounts["debtPayments"]?.amount != 0)
    }
}
