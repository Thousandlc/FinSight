import Foundation
import Testing
import YoushuAI
import YoushuDomain

@Suite("Recognition quality harness")
struct RecognitionQualityHarnessTests {
    private struct ThrowingExtractor: TransactionExtracting {
        let name = "throwing-extractor"
        func extractTransactionDraft(fromImageData data: Data) async throws -> TransactionDraft {
            throw AIRecognitionError.networkTimeout
        }
    }

    @Test("recognizer throw is an operation failure, not an exact match")
    func providerFailureIsNotFieldMismatch() async throws {
        let loaded = try RecognitionQualityCorpusLoader.loadCommittedV1()
        let txOnly = RecognitionQualityCorpusV1(
            schemaVersion: loaded.corpus.schemaVersion,
            corpusVersion: loaded.corpus.corpusVersion,
            dateComparison: loaded.corpus.dateComparison,
            fixtures: loaded.corpus.fixtures.filter { $0.id == "tx-expense-normal" }
        )
        let report = await RecognitionQualityHarness.evaluate(
            corpus: txOnly,
            corpusDirectory: loaded.directory,
            transactionExtractor: ThrowingExtractor(),
            debtScanner: nil,
            recognizerLabel: "throwing-extractor",
            baselineEligible: false,
            baselineIneligibilityReasons: ["testFailureInjector"]
        )
        #expect(report.operationFailureCount == 1)
        #expect(report.operationFailureFixtureIDs == ["tx-expense-normal"])
        #expect(report.transaction.wholeRecordExactCount == 0)
        #expect(report.transaction.wholeRecordEvaluatedCount == 0)
        #expect(report.transaction.amount.correct == 0)
    }

    @Test("same corpus and observations produce identical reports")
    func reportDeterminism() throws {
        let loaded = try RecognitionQualityCorpusLoader.loadCommittedV1()
        let fixture = try #require(loaded.corpus.fixtures.first { $0.id == "tx-expense-normal" })
        let truth = try #require(fixture.transaction)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: 2020, month: 2, day: 2))
        let observation = TransactionRecognitionObservation(
            amount: Decimal(string: "42.00"),
            currencyCode: "CNY",
            transactionType: .expense,
            date: date,
            merchant: "SYNTH_COFFEE_NORTH",
            category: "餐饮"
        )
        let run: RecognitionFixtureRun = .observation(.transaction(observation))
        let first = RecognitionQualityReportBuilder.build(
            corpus: RecognitionQualityCorpusV1(
                schemaVersion: loaded.corpus.schemaVersion,
                corpusVersion: loaded.corpus.corpusVersion,
                dateComparison: loaded.corpus.dateComparison,
                fixtures: [fixture]
            ),
            recognizerLabel: "deterministic-test",
            baselineEligible: false,
            baselineIneligibilityReasons: ["syntheticEvaluator"],
            runs: [(fixture.id, run)]
        )
        let second = RecognitionQualityReportBuilder.build(
            corpus: RecognitionQualityCorpusV1(
                schemaVersion: loaded.corpus.schemaVersion,
                corpusVersion: loaded.corpus.corpusVersion,
                dateComparison: loaded.corpus.dateComparison,
                fixtures: [fixture]
            ),
            recognizerLabel: "deterministic-test",
            baselineEligible: false,
            baselineIneligibilityReasons: ["syntheticEvaluator"],
            runs: [(fixture.id, run)]
        )
        #expect(first == second)
        #expect(try RecognitionQualityReportBuilder.encodeDeterministic(first)
            == RecognitionQualityReportBuilder.encodeDeterministic(second))
        #expect(truth.merchant == .known("SYNTH_COFFEE_NORTH"))
    }

    @Test("MockAIProvider integration is not baseline eligible")
    func mockIntegrationNotBaseline() async throws {
        let loaded = try RecognitionQualityCorpusLoader.loadCommittedV1()
        let subset = RecognitionQualityCorpusV1(
            schemaVersion: loaded.corpus.schemaVersion,
            corpusVersion: loaded.corpus.corpusVersion,
            dateComparison: loaded.corpus.dateComparison,
            fixtures: loaded.corpus.fixtures.filter {
                $0.id == "tx-expense-normal" || $0.id == "debt-current-due-only"
            }
        )
        let mock = MockAIProvider(behavior: .success, debtScanBehavior: .currentDueOnly)
        let report = await RecognitionQualityHarness.evaluate(
            corpus: subset,
            corpusDirectory: loaded.directory,
            transactionExtractor: mock,
            debtScanner: mock,
            recognizerLabel: mock.name,
            baselineEligible: true,
            baselineIneligibilityReasons: []
        )
        #expect(report.schemaVersion == "RecognitionQualityReportV1")
        #expect(report.fixtureCount == 2)
        #expect(report.operationFailureCount == 0)
        #expect(report.baselineEligible == false)
        #expect(report.baselineIneligibilityReasons.contains("mockRecognizer"))
        #expect(report.baselineIneligibilityReasons.contains("recognizerDoesNotInspectPixels"))
        #expect(report.recognizerLabel == "mock")
    }
}
