import Foundation
import Testing
import YoushuDomain

@Suite("Recognition Quality real Transaction corpus loader")
struct RealTransactionRecognitionCorpusLoaderTests {
    @Test("valid private manifest loads")
    func validManifest() throws {
        try withCorpus { directory, corpus in
            let data = try JSONEncoder().encode(corpus)
            let loaded = try RealTransactionRecognitionCorpusLoader.parseAndValidate(
                data,
                corpusDirectory: directory
            )
            #expect(loaded == corpus)
        }
    }

    @Test("missing sample asset is rejected without exposing its path")
    func missingSample() throws {
        try withCorpus { directory, original in
            var corpus = original
            corpus.samples[0].asset = "missing-private-image.png"
            #expect(throws: RealTransactionRecognitionCorpusError.missingAsset(corpus.samples[0].id)) {
                try RealTransactionRecognitionCorpusLoader.validate(corpus, corpusDirectory: directory)
            }
        }
    }

    @Test("malformed direction label is rejected")
    func malformedLabels() throws {
        try withCorpus { directory, original in
            var corpus = original
            corpus.samples[0].transaction?.direction = .known("sideways")
            #expect(throws: RealTransactionRecognitionCorpusError.invalidDirection(corpus.samples[0].id)) {
                try RealTransactionRecognitionCorpusLoader.validate(corpus, corpusDirectory: directory)
            }
        }
    }

    @Test("duplicate opaque sample ID is rejected")
    func duplicateSampleID() throws {
        try withCorpus { directory, original in
            var corpus = original
            corpus.samples.append(corpus.samples[0])
            #expect(throws: RealTransactionRecognitionCorpusError.duplicateSampleID(corpus.samples[0].id)) {
                try RealTransactionRecognitionCorpusLoader.validate(corpus, corpusDirectory: directory)
            }
        }
    }

    @Test("unsupported schema version is rejected")
    func unsupportedVersion() throws {
        try withCorpus { directory, original in
            var corpus = original
            corpus.schemaVersion = "RealTransactionRecognitionCorpusV0"
            #expect(throws: RealTransactionRecognitionCorpusError.unsupportedVersion(corpus.schemaVersion)) {
                try RealTransactionRecognitionCorpusLoader.validate(corpus, corpusDirectory: directory)
            }
        }
    }

    @Test("corpus digest is deterministic across sample and quality ordering")
    func deterministicDigest() throws {
        try withCorpus { directory, original in
            var reordered = original
            reordered.samples.reverse()
            reordered.samples[1].screenshotQualities.reverse()
            let first = try RealTransactionRecognitionCorpusLoader.corpusDigest(
                corpus: original,
                corpusDirectory: directory
            )
            let second = try RealTransactionRecognitionCorpusLoader.corpusDigest(
                corpus: reordered,
                corpusDirectory: directory
            )
            #expect(first == second)
            #expect(first.count == 64)

            var changed = original
            changed.samples[0].transaction?.amount = .known("42.01")
            let changedDigest = try RealTransactionRecognitionCorpusLoader.corpusDigest(
                corpus: changed,
                corpusDirectory: directory
            )
            #expect(changedDigest != first)
        }
    }

    @Test("private corpus absence is explicit and never falls back")
    func unavailableIsExplicit() {
        #expect(
            RealTransactionRecognitionCorpusLoader.availability(environment: [:])
                == .unavailable("REAL BASELINE CORPUS NOT AVAILABLE")
        )
    }
}

@Suite("Recognition Quality real Transaction metrics")
struct RealTransactionRecognitionMetricTests {
    @Test("end-to-end and recognized-only denominators remain distinct")
    func denominatorRules() throws {
        try withCorpus { _, base in
            var corpus = base
            corpus.samples = [supported("rq-111111111111"), supported("rq-222222222222"), supported("rq-333333333333")]
            let correct = observation(amount: "42.00", type: .expense)
            let wrong = observation(amount: "41.99", type: .income)
            let report = build(
                corpus,
                results: [
                    result("rq-111111111111", .recognized, correct),
                    result("rq-222222222222", .unreadable),
                    result("rq-333333333333", .recognized, wrong),
                ]
            )
            #expect(report.metrics.supportedRecognitionRate == RecognitionMetricRatio(numerator: 2, denominator: 3))
            #expect(report.metrics.amount.endToEnd == RecognitionMetricRatio(numerator: 1, denominator: 3))
            #expect(report.metrics.amount.recognizedOnly == RecognitionMetricRatio(numerator: 1, denominator: 2))
            #expect(report.metrics.direction.endToEnd == RecognitionMetricRatio(numerator: 1, denominator: 3))
            #expect(report.metrics.direction.recognizedOnly == RecognitionMetricRatio(numerator: 1, denominator: 2))
        }
    }

    @Test("amount comparison is exact Decimal semantics without tolerance")
    func amountExact() throws {
        try withCorpus { _, base in
            var corpus = base
            corpus.samples = [supported("rq-111111111111"), supported("rq-222222222222")]
            let report = build(
                corpus,
                results: [
                    result("rq-111111111111", .recognized, observation(amount: "42.0")),
                    result("rq-222222222222", .recognized, observation(amount: "42.01")),
                ]
            )
            #expect(report.metrics.amount.endToEnd.numerator == 1)
            #expect(report.metrics.amount.endToEnd.denominator == 2)
            #expect(report.aggregateErrorCategories["amountIncorrect"] == 1)
        }
    }

    @Test("readable unsupported false positives use only negative denominator")
    func unsupportedFalsePositive() throws {
        try withCorpus { _, base in
            var corpus = base
            corpus.samples = [
                negative("rq-111111111111"),
                negative("rq-222222222222"),
                unreadable("rq-333333333333"),
            ]
            let report = build(
                corpus,
                results: [
                    result("rq-111111111111", .recognized, observation()),
                    result("rq-222222222222", .unsupported),
                    result("rq-333333333333", .recognized, observation()),
                ]
            )
            #expect(report.metrics.unsupportedFalsePositiveRate == RecognitionMetricRatio(numerator: 1, denominator: 2))
        }
    }

    @Test("optional fields are excluded from field denominators")
    func optionalFieldDenominators() throws {
        try withCorpus { _, base in
            var corpus = base
            let known = supported("rq-111111111111")
            var unknown = supported("rq-222222222222")
            unknown.transaction?.merchant = .unknown
            corpus.samples = [known, unknown]
            let report = build(
                corpus,
                results: [
                    result("rq-111111111111", .recognized, observation(merchant: "Private Merchant")),
                    result("rq-222222222222", .recognized, observation(merchant: "Invented Merchant")),
                ]
            )
            #expect(report.metrics.merchant.endToEnd.denominator == 1)
            #expect(report.metrics.merchant.endToEnd.numerator == 1)
        }
    }

    @Test("thresholds stay frozen and zero denominators are not evaluable")
    func thresholdAndZeroDenominator() {
        let empty = emptyMetrics()
        let gate = RealRecognitionGateEvaluator.evaluate(empty)
        #expect(gate.amountExact.threshold == 98)
        #expect(gate.direction.threshold == 99)
        #expect(gate.occurredAt.threshold == 95)
        #expect(gate.merchant.threshold == 90)
        #expect(gate.supportedRecognition.threshold == 95)
        #expect(gate.unsupportedFalsePositive.threshold == 2)
        #expect(gate.amountExact.status == .notEvaluable)
        #expect(gate.unsupportedFalsePositive.status == .notEvaluable)
        #expect(gate.overall == .notEvaluable)
    }

    @Test("accuracy gate evaluates exact frozen pass and fail boundaries")
    func thresholdEvaluation() {
        let passingField = RecognitionFieldAccuracy(
            endToEnd: RecognitionMetricRatio(numerator: 100, denominator: 100),
            recognizedOnly: RecognitionMetricRatio(numerator: 100, denominator: 100)
        )
        var metrics = RealRecognitionMetrics(
            supportedRecognitionRate: RecognitionMetricRatio(numerator: 95, denominator: 100),
            amount: RecognitionFieldAccuracy(
                endToEnd: RecognitionMetricRatio(numerator: 98, denominator: 100),
                recognizedOnly: RecognitionMetricRatio(numerator: 98, denominator: 100)
            ),
            direction: RecognitionFieldAccuracy(
                endToEnd: RecognitionMetricRatio(numerator: 99, denominator: 100),
                recognizedOnly: RecognitionMetricRatio(numerator: 99, denominator: 100)
            ),
            occurredAt: RecognitionFieldAccuracy(
                endToEnd: RecognitionMetricRatio(numerator: 95, denominator: 100),
                recognizedOnly: RecognitionMetricRatio(numerator: 95, denominator: 100)
            ),
            merchant: RecognitionFieldAccuracy(
                endToEnd: RecognitionMetricRatio(numerator: 90, denominator: 100),
                recognizedOnly: RecognitionMetricRatio(numerator: 90, denominator: 100)
            ),
            unsupportedFalsePositiveRate: RecognitionMetricRatio(numerator: 2, denominator: 100),
            invalidRecognizedDraftCount: 0,
            operationalFailureCount: 0,
            crashCount: 0
        )
        #expect(RealRecognitionGateEvaluator.evaluate(metrics).overall == .pass)
        metrics.amount = passingField
        metrics.unsupportedFalsePositiveRate = RecognitionMetricRatio(numerator: 3, denominator: 100)
        #expect(RealRecognitionGateEvaluator.evaluate(metrics).unsupportedFalsePositive.status == .fail)
        #expect(RealRecognitionGateEvaluator.evaluate(metrics).overall == .fail)
    }

    @Test("merchant normalization is conservative for width whitespace and Latin case")
    func merchantNormalization() {
        #expect(
            RealTransactionRecognitionEvaluator.normalizeMerchant("  ＡＣＭＥ   Store ")
                == RealTransactionRecognitionEvaluator.normalizeMerchant("acme store")
        )
        #expect(
            RealTransactionRecognitionEvaluator.normalizeMerchant("acme store")
                != RealTransactionRecognitionEvaluator.normalizeMerchant("acme stores")
        )
    }

    @Test("aggregate report structurally excludes private sample data")
    func aggregatePrivacy() throws {
        try withCorpus { _, base in
            var corpus = base
            corpus.samples = [supported("rq-deadbeefcafe")]
            corpus.samples[0].asset = "private-order-12345-88.88.png"
            corpus.samples[0].transaction?.amount = .known("88.88")
            corpus.samples[0].transaction?.merchant = .known("Sensitive Merchant")
            let report = build(
                corpus,
                results: [result(
                    "rq-deadbeefcafe",
                    .recognized,
                    observation(amount: "88.88", merchant: "Sensitive Merchant")
                )]
            )
            let encoded = try #require(String(
                data: RealTransactionRecognitionEvaluator.encodeAggregateReport(report),
                encoding: .utf8
            ))
            let object = try #require(
                JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: Any]
            )
            let keys = recursivelyCollectedKeys(object)
            #expect(keys.isDisjoint(with: [
                "sampleID", "sampleIDs", "asset", "assets", "fileName", "filePath",
                "rawOCR", "ocrText", "imageBytes", "amountValue", "merchantValue",
                "orderID", "transactionID", "groundTruth",
            ]))
            #expect(!encoded.contains("rq-deadbeefcafe"))
            #expect(!encoded.contains("private-order-12345-88.88.png"))
            #expect(!encoded.contains("88.88"))
            #expect(!encoded.contains("Sensitive Merchant"))
            #expect(!encoded.contains("rawOCR"))
            #expect(!encoded.contains("imageBytes"))
            #expect(!encoded.contains("transactionId"))
        }
    }
}

private func withCorpus(
    _ body: (URL, RealTransactionRecognitionCorpusV1) throws -> Void
) throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("recognition-quality-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try Data("synthetic-image-a".utf8).write(to: directory.appendingPathComponent("a.png"))
    try Data("synthetic-image-b".utf8).write(to: directory.appendingPathComponent("b.png"))
    let corpus = RealTransactionRecognitionCorpusV1(
        schemaVersion: "RealTransactionRecognitionCorpusV1",
        corpusVersion: "private-v1",
        timeZone: "Asia/Shanghai",
        samples: [supported("rq-aaaaaaaaaaaa", asset: "a.png"), negative("rq-bbbbbbbbbbbb", asset: "b.png")]
    )
    try body(directory, corpus)
}

private func supported(
    _ id: String,
    asset: String = "a.png"
) -> RealTransactionRecognitionSampleV1 {
    RealTransactionRecognitionSampleV1(
        id: id,
        asset: asset,
        sourceKind: .privateRepresentativeScreenshot,
        platform: .weChat,
        family: .expensePayment,
        screenshotQualities: [.fullScreenshot, .light],
        expectedOutcome: .recognized,
        transaction: RealTransactionGroundTruthV1(
            amount: .known("42.00"),
            direction: .known("expense"),
            occurredAt: .known("2020-02-02T10:30"),
            occurredAtPrecision: .minute,
            merchant: .known("Private Merchant"),
            paymentAccountHint: .unknown,
            category: .unknown
        )
    )
}

private func negative(
    _ id: String,
    asset: String = "b.png"
) -> RealTransactionRecognitionSampleV1 {
    RealTransactionRecognitionSampleV1(
        id: id,
        asset: asset,
        sourceKind: .privateRepresentativeScreenshot,
        platform: .alipay,
        family: .readableUnsupported,
        screenshotQualities: [.fullScreenshot],
        expectedOutcome: .unsupported,
        transaction: nil
    )
}

private func unreadable(_ id: String) -> RealTransactionRecognitionSampleV1 {
    RealTransactionRecognitionSampleV1(
        id: id,
        asset: "b.png",
        sourceKind: .privateRepresentativeScreenshot,
        platform: .other,
        family: .unreadable,
        screenshotQualities: [.other],
        expectedOutcome: .unreadable,
        transaction: nil
    )
}

private func observation(
    amount: String = "42.00",
    type: TransactionType = .expense,
    merchant: String? = "Private Merchant"
) -> TransactionRecognitionObservation {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    return TransactionRecognitionObservation(
        amount: Decimal(string: amount),
        currencyCode: "CNY",
        transactionType: type,
        date: calendar.date(from: DateComponents(year: 2020, month: 2, day: 2, hour: 10, minute: 30)),
        merchant: merchant,
        category: nil
    )
}

private func result(
    _ id: String,
    _ outcome: RealRecognitionObservedOutcome,
    _ observation: TransactionRecognitionObservation? = nil
) -> RealRecognitionSampleResult {
    RealRecognitionSampleResult(
        sampleID: id,
        outcome: outcome,
        observation: observation,
        invalidRecognizedDraft: false,
        failureCategory: nil,
        latencyMilliseconds: 10
    )
}

private func build(
    _ corpus: RealTransactionRecognitionCorpusV1,
    results: [RealRecognitionSampleResult]
) -> RealTransactionRecognitionBaselineReportV1 {
    RealTransactionRecognitionEvaluator.buildReport(
        corpus: corpus,
        corpusDigest: String(repeating: "a", count: 64),
        candidateCommit: String(repeating: "b", count: 40),
        metadata: TransactionRecognizerMetadata(
            providerID: "apple-vision-transaction-v1",
            engineVersion: "vision-accurate-zh-Hans-en-US-v1",
            inspectsImagePixels: true
        ),
        results: results,
        runTimestamp: "2026-08-25T00:00:00Z",
        environment: "test-owned synthetic metric input",
        platformOS: "test"
    )
}

private func emptyMetrics() -> RealRecognitionMetrics {
    let zero = RecognitionMetricRatio(numerator: 0, denominator: 0)
    let field = RecognitionFieldAccuracy(endToEnd: zero, recognizedOnly: zero)
    return RealRecognitionMetrics(
        supportedRecognitionRate: zero,
        amount: field,
        direction: field,
        occurredAt: field,
        merchant: field,
        unsupportedFalsePositiveRate: zero,
        invalidRecognizedDraftCount: 0,
        operationalFailureCount: 0,
        crashCount: 0
    )
}

private func recursivelyCollectedKeys(_ value: Any) -> Set<String> {
    if let dictionary = value as? [String: Any] {
        return dictionary.reduce(into: Set(dictionary.keys)) { keys, item in
            keys.formUnion(recursivelyCollectedKeys(item.value))
        }
    }
    if let array = value as? [Any] {
        return array.reduce(into: Set<String>()) { keys, item in
            keys.formUnion(recursivelyCollectedKeys(item))
        }
    }
    return []
}
