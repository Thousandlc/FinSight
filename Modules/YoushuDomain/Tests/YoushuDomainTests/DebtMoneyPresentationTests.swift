import Foundation
import Testing
import YoushuDomain
import YoushuFoundation

@Suite("Debt money presentation")
struct DebtMoneyPresentationTests {
    /// Mirrors production `YSMoneyFormatter` CNY output without depending on DesignSystem.
    private func format(_ money: Money) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = ","
        let amountString = formatter.string(from: money.amount as NSDecimalNumber) ?? "\(money.amount)"
        return "¥\(amountString)"
    }

    private var formattedZero: String { format(.zeroCNY) }

    @Test("nil outstanding balance is unknown, not formatted zero")
    func unknownOutstandingBalance() {
        let presentation = DebtMoneyPresentation(nil as Money?)
        let text = presentation.text(formatted: format)

        #expect(presentation == .unknown)
        #expect(presentation.isUnknown)
        #expect(text == DebtMoneyPresentation.unknownPlaceholder)
        #expect(text == "—")
        #expect(text != formattedZero)
        #expect(text.contains("0.00") == false)
        #expect(text.contains("¥0") == false)
    }

    @Test("known outstanding balance preserves exact formatted value")
    func knownOutstandingBalance() {
        let money = Money(amount: Decimal(string: "8200.50")!, currencyCode: "CNY")
        let presentation = DebtMoneyPresentation(money)
        let text = presentation.text(formatted: format)

        #expect(presentation == .known(money))
        #expect(presentation.isUnknown == false)
        #expect(text == format(money))
        #expect(text == "¥8,200.50")
        #expect(text != DebtMoneyPresentation.unknownPlaceholder)
    }

    @Test("known zero outstanding is numeric zero and distinct from nil")
    func knownZeroOutstandingBalance() {
        let knownZero = DebtMoneyPresentation(.zeroCNY)
        let unknown = DebtMoneyPresentation(nil as Money?)

        #expect(knownZero == .known(.zeroCNY))
        #expect(unknown == .unknown)
        #expect(knownZero != unknown)

        let knownText = knownZero.text(formatted: format)
        let unknownText = unknown.text(formatted: format)

        #expect(knownText == formattedZero)
        #expect(knownText == "¥0.00")
        #expect(unknownText == "—")
        #expect(knownText != unknownText)
    }

    @Test("all-nil outstanding totals stay unknown even if calculator returns zero")
    func knownOutstandingTotalAllUnknown() {
        let debts = [
            Debt(userId: UUID(), outstandingBalance: nil),
            Debt(userId: UUID(), outstandingBalance: nil),
        ]
        let presentation = DebtMoneyPresentation.knownOutstandingTotal(
            from: debts,
            computed: .zeroCNY
        )
        let text = presentation.text(formatted: format)

        #expect(presentation == .unknown)
        #expect(text == "—")
        #expect(text != formattedZero)
    }

    @Test("any known outstanding uses the computed known subtotal as incomplete")
    func knownOutstandingTotalIncludesKnown() {
        let known = Money(amount: 4_000, currencyCode: "CNY")
        let debts = [
            Debt(userId: UUID(), outstandingBalance: nil),
            Debt(userId: UUID(), outstandingBalance: known),
        ]
        let presentation = DebtMoneyPresentation.knownOutstandingTotal(
            from: debts,
            computed: known
        )

        #expect(presentation == .knownIncomplete(known))
        #expect(presentation.isComplete == false)
        #expect(presentation.availability == .partial)
        #expect(presentation.caption == DebtMoneyPresentation.incompleteCaption)
        #expect(presentation.text(formatted: format) == format(known))
        #expect(presentation.text(formatted: format) != formattedZero)
    }

    @Test("known-zero outstanding total remains known zero, not unknown")
    func knownOutstandingTotalKnownZero() {
        let debts = [
            Debt(
                userId: UUID(),
                outstandingBalance: .zeroCNY,
                status: .active
            ),
        ]
        let presentation = DebtMoneyPresentation.knownOutstandingTotal(
            from: debts,
            computed: .zeroCNY
        )

        #expect(presentation == .known(.zeroCNY))
        #expect(presentation.text(formatted: format) == formattedZero)
        #expect(presentation != .unknown)
    }

    @Test("paid-off known zero does not make open unknown outstanding look like ¥0")
    func knownOutstandingTotalIgnoresPaidOffWhenOpenIsUnknown() {
        let debts = [
            Debt(userId: UUID(), outstandingBalance: nil, status: .active),
            Debt(userId: UUID(), outstandingBalance: .zeroCNY, status: .paidOff),
        ]
        let presentation = DebtMoneyPresentation.knownOutstandingTotal(
            from: debts,
            computed: .zeroCNY
        )
        let text = presentation.text(formatted: format)

        #expect(presentation == .unknown)
        #expect(text == "—")
        #expect(text != formattedZero)
    }

    @Test("no open debts uses the defined empty-sum total")
    func knownOutstandingTotalEmptyOpenSet() {
        let debts = [
            Debt(userId: UUID(), outstandingBalance: .zeroCNY, status: .paidOff),
        ]
        let presentation = DebtMoneyPresentation.knownOutstandingTotal(
            from: debts,
            computed: .zeroCNY
        )

        #expect(presentation == .known(.zeroCNY))
        #expect(presentation.text(formatted: format) == formattedZero)
    }

    @Test("all open outstanding known is a complete total")
    func outstandingAllKnownIsComplete() {
        let a = Money(amount: 10_000, currencyCode: "CNY")
        let b = Money(amount: 5_000, currencyCode: "CNY")
        let debts = [
            Debt(userId: UUID(), outstandingBalance: a, status: .active),
            Debt(userId: UUID(), outstandingBalance: b, status: .active),
        ]
        let total = Money(amount: 15_000, currencyCode: "CNY")
        let presentation = DebtMoneyPresentation.knownOutstandingTotal(from: debts, computed: total)
        #expect(presentation == .known(total))
        #expect(presentation.isComplete)
        #expect(presentation.availability == .known)
        #expect(presentation.caption == nil)
    }

    @Test("no usable monthly payment facts stay unknown, not known zero")
    func estimatedMonthlyNoKnownAmounts() {
        let debts = [
            Debt(userId: UUID(), outstandingBalance: Money(amount: 8_000, currencyCode: "CNY"), status: .active),
            Debt(userId: UUID(), outstandingBalance: Money(amount: 2_000, currencyCode: "CNY"), status: .active),
        ]
        let presentation = DebtMoneyPresentation.estimatedMonthly(from: debts)
        #expect(presentation == .unknown)
        #expect(presentation.knownAmount == nil)
        #expect(presentation.text(formatted: format) != formattedZero)
        #expect(DebtCenterCalculator.estimatedMonthlyRepayment(debts: debts).amount == 0)
    }

    @Test("known monthly payment facts preserve the exact sum")
    func estimatedMonthlyKnownAmounts() {
        let debts = [
            Debt(
                userId: UUID(),
                installmentAmount: Money(amount: 1_000, currencyCode: "CNY"),
                paymentFrequency: .monthly,
                status: .active
            ),
            Debt(
                userId: UUID(),
                installmentAmount: Money(amount: 600, currencyCode: "CNY"),
                paymentFrequency: .monthly,
                status: .active
            ),
        ]
        let presentation = DebtMoneyPresentation.estimatedMonthly(from: debts)
        let expected = Money(amount: 1_600, currencyCode: "CNY")
        #expect(presentation == .known(expected))
        #expect(DebtCenterCalculator.estimatedMonthlyRepayment(debts: debts).amount == 1_600)
    }

    @Test("mixed monthly payment facts are an incomplete subtotal")
    func estimatedMonthlyMixedAmounts() {
        let debts = [
            Debt(
                userId: UUID(),
                installmentAmount: Money(amount: 1_000, currencyCode: "CNY"),
                paymentFrequency: .monthly,
                status: .active
            ),
            Debt(userId: UUID(), outstandingBalance: Money(amount: 4_000, currencyCode: "CNY"), status: .active),
        ]
        let presentation = DebtMoneyPresentation.estimatedMonthly(from: debts)
        let subtotal = Money(amount: 1_000, currencyCode: "CNY")
        #expect(presentation == .knownIncomplete(subtotal))
        #expect(presentation.isComplete == false)
        #expect(presentation.availability == .partial)
    }

    @Test("known-zero monthly installment remains known zero")
    func estimatedMonthlyKnownZero() {
        let debts = [
            Debt(
                userId: UUID(),
                installmentAmount: .zeroCNY,
                paymentFrequency: .monthly,
                status: .active
            ),
        ]
        let presentation = DebtMoneyPresentation.estimatedMonthly(from: debts)
        #expect(presentation == .known(.zeroCNY))
        #expect(presentation != .unknown)
    }
}
