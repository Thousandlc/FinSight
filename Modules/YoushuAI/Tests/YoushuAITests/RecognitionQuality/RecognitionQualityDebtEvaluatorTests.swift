import Foundation
import Testing
import YoushuDomain

@Suite("Recognition quality debt evaluator")
struct RecognitionQualityDebtEvaluatorTests {
    private let spec = DateComparisonSpec.utcDay

    private func truth(
        localId: String,
        lender: String,
        product: String,
        type: String,
        outstanding: OptionalFact<String>,
        currentDue: OptionalFact<String>,
        dueDate: OptionalFact<String> = .unknown
    ) -> DebtCandidateGroundTruthV1 {
        DebtCandidateGroundTruthV1(
            localId: localId,
            lender: .known(lender),
            productName: .known(product),
            debtType: .known(type),
            outstandingBalance: outstanding,
            currentDue: currentDue,
            minimumDue: .unknown,
            installmentAmount: .unknown,
            dueDate: dueDate,
            interestRate: .unknown
        )
    }

    private func observe(
        lender: String,
        product: String,
        type: DebtType,
        outstanding: Decimal?,
        currentDue: Decimal?,
        dueDate: Date? = nil
    ) -> DebtCandidateObservation {
        DebtCandidateObservation(
            lender: lender,
            productName: product,
            debtType: type,
            outstandingBalance: outstanding,
            currentDue: currentDue,
            minimumDue: nil,
            installmentAmount: nil,
            dueDate: dueDate,
            interestRate: nil
        )
    }

    @Test("exact candidate")
    func exactCandidate() {
        let expected = truth(
            localId: "a",
            lender: "SYNTH_BANK_ORANGE",
            product: "合成信用卡",
            type: "creditCard",
            outstanding: .known("8800.00"),
            currentDue: .known("1200.00")
        )
        let observed = observe(
            lender: "SYNTH_BANK_ORANGE",
            product: "合成信用卡",
            type: .creditCard,
            outstanding: Decimal(string: "8800.00"),
            currentDue: Decimal(string: "1200.00")
        )
        let fields = RecognitionQualityDebtEvaluator.evaluatePair(
            truth: expected,
            observation: observed,
            spec: spec
        )
        #expect(fields["outstandingBalance"] == .correct)
        #expect(fields["currentDue"] == .correct)
        #expect(fields["lender"] == .correct)
    }

    @Test("currentDue-only ground truth with outstanding unknown")
    func currentDueOnlyUnknownOutstanding() {
        let expected = truth(
            localId: "a",
            lender: "SYNTH_LENDER_PINE",
            product: "合成消费贷",
            type: "consumerLoan",
            outstanding: .unknown,
            currentDue: .known("2300.00")
        )
        let honest = observe(
            lender: "SYNTH_LENDER_PINE",
            product: "合成消费贷",
            type: .consumerLoan,
            outstanding: nil,
            currentDue: Decimal(string: "2300.00")
        )
        let honestFields = RecognitionQualityDebtEvaluator.evaluatePair(
            truth: expected,
            observation: honest,
            spec: spec
        )
        #expect(honestFields["outstandingBalance"] == .correctlyUnknown)
        #expect(honestFields["currentDue"] == .correct)
    }

    @Test("invented outstanding from currentDue is penalized")
    func inventedOutstandingFromCurrentDue() {
        let expected = truth(
            localId: "a",
            lender: "SYNTH_LENDER_PINE",
            product: "合成消费贷",
            type: "consumerLoan",
            outstanding: .unknown,
            currentDue: .known("2300.00")
        )
        let invented = observe(
            lender: "SYNTH_LENDER_PINE",
            product: "合成消费贷",
            type: .consumerLoan,
            outstanding: Decimal(string: "2300.00"),
            currentDue: Decimal(string: "2300.00")
        )
        let fields = RecognitionQualityDebtEvaluator.evaluatePair(
            truth: expected,
            observation: invented,
            spec: spec
        )
        #expect(fields["outstandingBalance"] == .invented)
        #expect(fields["currentDue"] == .correct)
        #expect(fields["outstandingBalance"] != .correct)
    }

    @Test("unknown dueDate remains unknown")
    func unknownDueDate() {
        let expected = truth(
            localId: "a",
            lender: "SYNTH_BANK_CEDAR",
            product: "合成分期",
            type: "bnpl",
            outstanding: .known("1500.00"),
            currentDue: .known("500.00"),
            dueDate: .unknown
        )
        let honest = observe(
            lender: "SYNTH_BANK_CEDAR",
            product: "合成分期",
            type: .bnpl,
            outstanding: Decimal(string: "1500.00"),
            currentDue: Decimal(string: "500.00"),
            dueDate: nil
        )
        let fields = RecognitionQualityDebtEvaluator.evaluatePair(
            truth: expected,
            observation: honest,
            spec: spec
        )
        #expect(fields["dueDate"] == .correctlyUnknown)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let inventedDate = calendar.date(from: DateComponents(year: 2020, month: 1, day: 1))
        let invented = observe(
            lender: "SYNTH_BANK_CEDAR",
            product: "合成分期",
            type: .bnpl,
            outstanding: Decimal(string: "1500.00"),
            currentDue: Decimal(string: "500.00"),
            dueDate: inventedDate
        )
        let inventedFields = RecognitionQualityDebtEvaluator.evaluatePair(
            truth: expected,
            observation: invented,
            spec: spec
        )
        #expect(inventedFields["dueDate"] == .invented)
    }

    @Test("wrong lender or product")
    func wrongLenderProduct() {
        let expected = truth(
            localId: "a",
            lender: "SYNTH_BANK_ORANGE",
            product: "合成信用卡",
            type: "creditCard",
            outstanding: .known("1.00"),
            currentDue: .unknown
        )
        let observed = observe(
            lender: "OTHER_BANK",
            product: "别的产品",
            type: .creditCard,
            outstanding: Decimal(string: "1.00"),
            currentDue: nil
        )
        let fields = RecognitionQualityDebtEvaluator.evaluatePair(
            truth: expected,
            observation: observed,
            spec: spec
        )
        #expect(fields["lender"] == .incorrect)
        #expect(fields["productName"] == .incorrect)
    }

    @Test("missing and extra candidates")
    func missingAndExtraCandidates() {
        let expected = [
            truth(
                localId: "a",
                lender: "SYNTH_LENDER_ALPHA",
                product: "合成卡A",
                type: "creditCard",
                outstanding: .known("3000.00"),
                currentDue: .known("300.00")
            ),
        ]
        let observed = [
            observe(
                lender: "SYNTH_LENDER_BETA",
                product: "合成贷B",
                type: .consumerLoan,
                outstanding: Decimal(string: "7000.00"),
                currentDue: Decimal(string: "700.00")
            ),
        ]
        let matched = RecognitionQualityDebtEvaluator.match(expected: expected, observed: observed)
        #expect(matched.pairs.isEmpty)
        #expect(matched.missed == 1)
        #expect(matched.extra == 1)
    }

    @Test("multiple candidates are order independent")
    func orderIndependentMatching() {
        let expected = [
            truth(
                localId: "alpha",
                lender: "SYNTH_LENDER_ALPHA",
                product: "合成卡A",
                type: "creditCard",
                outstanding: .known("3000.00"),
                currentDue: .known("300.00")
            ),
            truth(
                localId: "beta",
                lender: "SYNTH_LENDER_BETA",
                product: "合成贷B",
                type: "consumerLoan",
                outstanding: .known("7000.00"),
                currentDue: .known("700.00")
            ),
        ]
        let observedForward = [
            observe(
                lender: "SYNTH_LENDER_ALPHA",
                product: "合成卡A",
                type: .creditCard,
                outstanding: Decimal(string: "3000.00"),
                currentDue: Decimal(string: "300.00")
            ),
            observe(
                lender: "SYNTH_LENDER_BETA",
                product: "合成贷B",
                type: .consumerLoan,
                outstanding: Decimal(string: "7000.00"),
                currentDue: Decimal(string: "700.00")
            ),
        ]
        let observedReversed = Array(observedForward.reversed())
        let forward = RecognitionQualityDebtEvaluator.match(expected: expected, observed: observedForward)
        let reversed = RecognitionQualityDebtEvaluator.match(expected: expected, observed: observedReversed)
        #expect(forward.pairs.count == 2)
        #expect(reversed.pairs.count == 2)
        #expect(forward.missed == 0)
        #expect(reversed.missed == 0)
        #expect(forward.extra == 0)
        #expect(Set(forward.pairs.map(\.0.localId)) == Set(reversed.pairs.map(\.0.localId)))
    }
}
