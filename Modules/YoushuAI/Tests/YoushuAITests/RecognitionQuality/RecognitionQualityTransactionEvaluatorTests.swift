import Foundation
import Testing
import YoushuDomain

@Suite("Recognition quality transaction evaluator")
struct RecognitionQualityTransactionEvaluatorTests {
    private let spec = DateComparisonSpec.utcDay
    private let truth = TransactionGroundTruthV1(
        amount: .known("42.00"),
        currencyCode: .known("CNY"),
        transactionType: .known("expense"),
        date: .known("2020-02-02"),
        merchant: .known("SYNTH_COFFEE_NORTH"),
        category: .known("餐饮")
    )

    private func observe(
        amount: Decimal? = Decimal(string: "42.00"),
        currency: String? = "CNY",
        type: TransactionType? = .expense,
        date: Date? = RecognitionQualityCompare.parseDay("2020-02-02", timeZoneIdentifier: "UTC").map { ymd in
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            return calendar.date(from: DateComponents(year: ymd.year, month: ymd.month, day: ymd.day))!
        },
        merchant: String? = "SYNTH_COFFEE_NORTH",
        category: String? = "餐饮"
    ) -> TransactionRecognitionObservation {
        TransactionRecognitionObservation(
            amount: amount,
            currencyCode: currency,
            transactionType: type,
            date: date,
            merchant: merchant,
            category: category
        )
    }

    @Test("exact match")
    func exactMatch() {
        let result = RecognitionQualityTransactionEvaluator.evaluate(
            truth: truth,
            observation: observe(),
            spec: spec
        )
        #expect(result.exact)
        #expect(result.fields.values.allSatisfy { $0 == .correct })
    }

    @Test("wrong amount")
    func wrongAmount() {
        let result = RecognitionQualityTransactionEvaluator.evaluate(
            truth: truth,
            observation: observe(amount: Decimal(string: "41.00")),
            spec: spec
        )
        #expect(result.fields["amount"] == .incorrect)
        #expect(result.exact == false)
    }

    @Test("missing amount")
    func missingAmount() {
        let result = RecognitionQualityTransactionEvaluator.evaluate(
            truth: truth,
            observation: observe(amount: nil),
            spec: spec
        )
        #expect(result.fields["amount"] == .missing)
        #expect(result.exact == false)
    }

    @Test("wrong direction")
    func wrongDirection() {
        let result = RecognitionQualityTransactionEvaluator.evaluate(
            truth: truth,
            observation: observe(type: .income),
            spec: spec
        )
        #expect(result.fields["transactionType"] == .incorrect)
    }

    @Test("date mismatch")
    func dateMismatch() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let other = calendar.date(from: DateComponents(year: 2020, month: 2, day: 3))
        let result = RecognitionQualityTransactionEvaluator.evaluate(
            truth: truth,
            observation: observe(date: other),
            spec: spec
        )
        #expect(result.fields["date"] == .incorrect)
    }

    @Test("merchant missing")
    func merchantMissing() {
        let result = RecognitionQualityTransactionEvaluator.evaluate(
            truth: truth,
            observation: observe(merchant: nil),
            spec: spec
        )
        #expect(result.fields["merchant"] == .missing)
    }

    @Test("merchant invented")
    func merchantInvented() {
        var unknownMerchant = truth
        unknownMerchant.merchant = .unknown
        let result = RecognitionQualityTransactionEvaluator.evaluate(
            truth: unknownMerchant,
            observation: observe(merchant: "某商户"),
            spec: spec
        )
        #expect(result.fields["merchant"] == .invented)
        #expect(result.exact == false)
    }

    @Test("unknown merchant correctly remains nil")
    func unknownMerchantCorrectlyUnknown() {
        var unknownMerchant = truth
        unknownMerchant.merchant = .unknown
        let result = RecognitionQualityTransactionEvaluator.evaluate(
            truth: unknownMerchant,
            observation: observe(merchant: nil),
            spec: spec
        )
        #expect(result.fields["merchant"] == .correctlyUnknown)
        #expect(result.exact)
    }

    @Test("whole-record exactness fails on invented field")
    func wholeRecordExactness() {
        let exact = RecognitionQualityTransactionEvaluator.evaluate(
            truth: truth,
            observation: observe(),
            spec: spec
        )
        #expect(exact.exact)
        var unknownMerchant = truth
        unknownMerchant.merchant = .unknown
        let invented = RecognitionQualityTransactionEvaluator.evaluate(
            truth: unknownMerchant,
            observation: observe(merchant: "SYNTH_COFFEE_NORTH"),
            spec: spec
        )
        #expect(invented.exact == false)
        #expect(invented.fields["merchant"] == .invented)
    }

    @Test("canonical money comparison ignores formatting")
    func moneyCanonical() {
        let result = RecognitionQualityTransactionEvaluator.evaluate(
            truth: truth,
            observation: observe(amount: Decimal(string: "42.0")),
            spec: spec
        )
        #expect(result.fields["amount"] == .correct)
    }
}
