import Foundation
import YoushuDomain

enum RealTransactionRecognitionEvaluator {
    private struct FieldAccumulator {
        var endToEndCorrect = 0
        var endToEndDenominator = 0
        var recognizedOnlyCorrect = 0
        var recognizedOnlyDenominator = 0

        mutating func add(expectedKnown: Bool, recognized: Bool, outcome: FieldOutcome?) {
            guard expectedKnown else { return }
            endToEndDenominator += 1
            if outcome == .correct { endToEndCorrect += 1 }
            guard recognized else { return }
            recognizedOnlyDenominator += 1
            if outcome == .correct { recognizedOnlyCorrect += 1 }
        }

        var accuracy: RecognitionFieldAccuracy {
            RecognitionFieldAccuracy(
                endToEnd: RecognitionMetricRatio(
                    numerator: endToEndCorrect,
                    denominator: endToEndDenominator
                ),
                recognizedOnly: RecognitionMetricRatio(
                    numerator: recognizedOnlyCorrect,
                    denominator: recognizedOnlyDenominator
                )
            )
        }
    }

    static func normalizeMerchant(_ value: String?) -> String? {
        guard let normalized = RecognitionQualityCompare.normalizeText(value) else { return nil }
        return normalized
            .folding(options: [.widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
    }

    static func buildReport(
        corpus: RealTransactionRecognitionCorpusV1,
        corpusDigest: String,
        candidateCommit: String,
        metadata: TransactionRecognizerMetadata,
        results: [RealRecognitionSampleResult],
        runTimestamp: String,
        environment: String,
        platformOS: String
    ) -> RealTransactionRecognitionBaselineReportV1 {
        let samplesByID = Dictionary(uniqueKeysWithValues: corpus.samples.map { ($0.id, $0) })
        var amount = FieldAccumulator()
        var direction = FieldAccumulator()
        var occurredAt = FieldAccumulator()
        var merchant = FieldAccumulator()
        var recognizedCount = 0
        var unsupportedCount = 0
        var unreadableCount = 0
        var failureCount = 0
        var supportedRecognized = 0
        var negativeFalsePositives = 0
        var invalidDrafts = 0
        var errors: [String: Int] = [:]

        for result in results {
            guard let sample = samplesByID[result.sampleID] else { continue }
            switch result.outcome {
            case .recognized: recognizedCount += 1
            case .unsupported: unsupportedCount += 1
            case .unreadable: unreadableCount += 1
            case .failure: failureCount += 1
            }
            if result.invalidRecognizedDraft {
                invalidDrafts += 1
                increment("invalidRecognizedDraft", in: &errors)
            }
            if let category = result.failureCategory {
                increment(category, in: &errors)
            }

            switch sample.expectedOutcome {
            case .recognized:
                let recognized = result.outcome == .recognized
                if recognized { supportedRecognized += 1 }
                guard let truth = sample.transaction else { continue }
                let observation = result.observation

                let amountOutcome = recognized
                    ? RecognitionQualityCompare.classifyDecimal(expected: truth.amount, observed: observation?.amount)
                    : nil
                amount.add(expectedKnown: truth.amount.knownValue != nil, recognized: recognized, outcome: amountOutcome)
                addFieldError(prefix: "amount", outcome: amountOutcome, expectedKnown: truth.amount.knownValue != nil, recognized: recognized, errors: &errors)

                let directionOutcome = recognized
                    ? RecognitionQualityCompare.classifyEnum(expected: truth.direction, observed: observation?.transactionType)
                    : nil
                direction.add(expectedKnown: truth.direction.knownValue != nil, recognized: recognized, outcome: directionOutcome)
                addDirectionError(outcome: directionOutcome, expectedKnown: truth.direction.knownValue != nil, recognized: recognized, errors: &errors)

                let dateOutcome: FieldOutcome?
                if recognized, case .known(let raw) = truth.occurredAt, let precision = truth.occurredAtPrecision {
                    dateOutcome = RealRecognitionDateCompare.matches(
                        expected: raw,
                        precision: precision,
                        observed: observation?.date,
                        timeZone: corpus.timeZone
                    )
                } else {
                    dateOutcome = nil
                }
                occurredAt.add(
                    expectedKnown: truth.occurredAt.knownValue != nil,
                    recognized: recognized,
                    outcome: dateOutcome
                )
                addFieldError(prefix: "date", outcome: dateOutcome, expectedKnown: truth.occurredAt.knownValue != nil, recognized: recognized, errors: &errors)

                let merchantOutcome: FieldOutcome?
                if recognized, case .known(let expected) = truth.merchant {
                    if let expectedNormalized = normalizeMerchant(expected) {
                        if let observedNormalized = normalizeMerchant(observation?.merchant) {
                            merchantOutcome = expectedNormalized == observedNormalized ? .correct : .incorrect
                        } else {
                            merchantOutcome = .missing
                        }
                    } else {
                        merchantOutcome = .incorrect
                    }
                } else {
                    merchantOutcome = nil
                }
                merchant.add(
                    expectedKnown: truth.merchant.knownValue != nil,
                    recognized: recognized,
                    outcome: merchantOutcome
                )
                addFieldError(prefix: "merchant", outcome: merchantOutcome, expectedKnown: truth.merchant.knownValue != nil, recognized: recognized, errors: &errors)

                switch result.outcome {
                case .unsupported: increment("parserFailure", in: &errors)
                case .unreadable: increment("ocrEmpty", in: &errors)
                case .failure: increment("providerFailure", in: &errors)
                case .recognized: break
                }
            case .unsupported:
                if result.outcome == .recognized {
                    negativeFalsePositives += 1
                    increment("unsupportedFalsePositive", in: &errors)
                } else if result.outcome == .failure {
                    increment("providerFailure", in: &errors)
                }
            case .unreadable:
                if result.outcome == .recognized { increment("unreadableFalsePositive", in: &errors) }
                if result.outcome == .failure { increment("providerFailure", in: &errors) }
            }
        }

        let coverage = makeCoverage(corpus.samples)
        let supportedRecognition = RecognitionMetricRatio(
            numerator: supportedRecognized,
            denominator: coverage.supported
        )
        let unsupportedFalsePositive = RecognitionMetricRatio(
            numerator: negativeFalsePositives,
            denominator: coverage.readableNegative
        )
        let metrics = RealRecognitionMetrics(
            supportedRecognitionRate: supportedRecognition,
            amount: amount.accuracy,
            direction: direction.accuracy,
            occurredAt: occurredAt.accuracy,
            merchant: merchant.accuracy,
            unsupportedFalsePositiveRate: unsupportedFalsePositive,
            invalidRecognizedDraftCount: invalidDrafts,
            operationalFailureCount: failureCount,
            crashCount: 0
        )

        return RealTransactionRecognitionBaselineReportV1(
            schemaVersion: "RealTransactionRecognitionBaselineReportV1",
            baselineStatus: RealRecognitionOfficialCoverage.status(for: coverage),
            runTimestamp: runTimestamp,
            candidateCommit: candidateCommit,
            providerID: metadata.providerID,
            engineVersion: metadata.engineVersion ?? "",
            baselineEligible: metadata.baselineEligible,
            corpusVersion: corpus.corpusVersion,
            corpusDigest: corpusDigest,
            sampleCount: corpus.samples.count,
            coverage: coverage,
            outcomes: RealRecognitionOutcomeDistribution(
                recognized: recognizedCount,
                unsupported: unsupportedCount,
                unreadable: unreadableCount,
                failure: failureCount
            ),
            metrics: metrics,
            gate: RealRecognitionGateEvaluator.evaluate(metrics),
            aggregateErrorCategories: errors.filter { $0.value > 0 },
            latency: latency(results.map(\.latencyMilliseconds)),
            environment: environment,
            platformOS: platformOS
        )
    }

    static func encodeAggregateReport(_ report: RealTransactionRecognitionBaselineReportV1) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(report)
    }

    private static func makeCoverage(_ samples: [RealTransactionRecognitionSampleV1]) -> RealRecognitionCoverage {
        let supported = samples.filter { $0.expectedOutcome == .recognized }
        func qualityCount(_ quality: RealRecognitionScreenshotQuality) -> Int {
            samples.filter { $0.screenshotQualities.contains(quality) }.count
        }
        return RealRecognitionCoverage(
            supported: supported.count,
            readableNegative: samples.filter { $0.expectedOutcome == .unsupported }.count,
            expectedUnreadable: samples.filter { $0.expectedOutcome == .unreadable }.count,
            privateRealScreenshot: samples.filter { $0.sourceKind == .privateRealScreenshot }.count,
            privateRepresentativeScreenshot: samples.filter {
                $0.sourceKind == .privateRepresentativeScreenshot
            }.count,
            weChat: supported.filter { $0.platform == .weChat }.count,
            alipay: supported.filter { $0.platform == .alipay }.count,
            otherPlatform: supported.filter { $0.platform == .other }.count,
            expensePayment: supported.filter { $0.family == .expensePayment }.count,
            incomeReceived: supported.filter { $0.family == .incomeReceived }.count,
            refund: supported.filter { $0.family == .refund }.count,
            transfer: supported.filter { $0.family == .transfer }.count,
            fullScreenshot: qualityCount(.fullScreenshot),
            crop: qualityCount(.crop),
            light: qualityCount(.light),
            dark: qualityCount(.dark),
            otherQuality: qualityCount(.other)
        )
    }

    private static func latency(_ values: [Double]) -> RealRecognitionLatency {
        let sorted = values.sorted()
        return RealRecognitionLatency(
            sampleCount: sorted.count,
            p50Milliseconds: percentile(sorted, percentile: 0.50),
            p95Milliseconds: percentile(sorted, percentile: 0.95)
        )
    }

    private static func percentile(_ sorted: [Double], percentile: Double) -> Double? {
        guard !sorted.isEmpty else { return nil }
        let rank = max(1, Int(ceil(percentile * Double(sorted.count))))
        return sorted[min(rank - 1, sorted.count - 1)]
    }

    private static func increment(_ key: String, in errors: inout [String: Int]) {
        errors[key, default: 0] += 1
    }

    private static func addFieldError(
        prefix: String,
        outcome: FieldOutcome?,
        expectedKnown: Bool,
        recognized: Bool,
        errors: inout [String: Int]
    ) {
        guard expectedKnown, recognized else { return }
        switch outcome {
        case .missing: increment("\(prefix)Missing", in: &errors)
        case .incorrect: increment("\(prefix)Incorrect", in: &errors)
        default: break
        }
    }

    private static func addDirectionError(
        outcome: FieldOutcome?,
        expectedKnown: Bool,
        recognized: Bool,
        errors: inout [String: Int]
    ) {
        guard expectedKnown, recognized else { return }
        switch outcome {
        case .missing: increment("directionMissing", in: &errors)
        case .incorrect: increment("directionConflict", in: &errors)
        default: break
        }
    }
}

enum RealRecognitionGateEvaluator {
    static func evaluate(_ metrics: RealRecognitionMetrics) -> RealRecognitionAccuracyGate {
        let amount = minimum("amountEndToEndExact", ratio: metrics.amount.endToEnd, percent: 98)
        let direction = minimum("directionEndToEnd", ratio: metrics.direction.endToEnd, percent: 99)
        let occurredAt = minimum("occurredAtEndToEnd", ratio: metrics.occurredAt.endToEnd, percent: 95)
        let merchant = minimum("merchantEndToEndNormalized", ratio: metrics.merchant.endToEnd, percent: 90)
        let recognition = minimum("supportedRecognitionRate", ratio: metrics.supportedRecognitionRate, percent: 95)
        let falsePositive = maximum(
            "unsupportedFalsePositiveRate",
            ratio: metrics.unsupportedFalsePositiveRate,
            percent: 2
        )
        let invalid = zero("invalidRecognizedDrafts", count: metrics.invalidRecognizedDraftCount)
        let crashes = zero("crashes", count: metrics.crashCount)
        let statuses = [
            amount.status, direction.status, occurredAt.status, merchant.status,
            recognition.status, falsePositive.status, invalid.status, crashes.status,
        ]
        let overall: RealRecognitionThresholdStatus = statuses.contains(.fail)
            ? .fail
            : (statuses.contains(.notEvaluable) ? .notEvaluable : .pass)
        return RealRecognitionAccuracyGate(
            amountExact: amount,
            direction: direction,
            occurredAt: occurredAt,
            merchant: merchant,
            supportedRecognition: recognition,
            unsupportedFalsePositive: falsePositive,
            invalidRecognizedDrafts: invalid,
            crashes: crashes,
            overall: overall
        )
    }

    private static func minimum(
        _ metric: String,
        ratio: RecognitionMetricRatio,
        percent: Int
    ) -> RealRecognitionThresholdResult {
        let status: RealRecognitionThresholdStatus = ratio.denominator == 0
            ? .notEvaluable
            : (ratio.numerator * 100 >= percent * ratio.denominator ? .pass : .fail)
        return RealRecognitionThresholdResult(
            metric: metric,
            comparison: ">=",
            threshold: Double(percent),
            actual: ratio,
            actualCount: nil,
            status: status
        )
    }

    private static func maximum(
        _ metric: String,
        ratio: RecognitionMetricRatio,
        percent: Int
    ) -> RealRecognitionThresholdResult {
        let status: RealRecognitionThresholdStatus = ratio.denominator == 0
            ? .notEvaluable
            : (ratio.numerator * 100 <= percent * ratio.denominator ? .pass : .fail)
        return RealRecognitionThresholdResult(
            metric: metric,
            comparison: "<=",
            threshold: Double(percent),
            actual: ratio,
            actualCount: nil,
            status: status
        )
    }

    private static func zero(_ metric: String, count: Int) -> RealRecognitionThresholdResult {
        RealRecognitionThresholdResult(
            metric: metric,
            comparison: "==",
            threshold: 0,
            actual: nil,
            actualCount: count,
            status: count == 0 ? .pass : .fail
        )
    }
}

enum RealTransactionRecognitionHarness {
    static func evaluate(
        corpus: RealTransactionRecognitionCorpusV1,
        corpusDirectory: URL,
        recognizer: any TransactionExtracting,
        candidateCommit: String,
        runTimestamp: String,
        environment: String,
        platformOS: String
    ) async throws -> RealTransactionRecognitionBaselineReportV1 {
        try RealTransactionRecognitionCorpusLoader.validateCandidateCommit(candidateCommit)
        let digest = try RealTransactionRecognitionCorpusLoader.corpusDigest(
            corpus: corpus,
            corpusDirectory: corpusDirectory
        )
        var results: [RealRecognitionSampleResult] = []
        for sample in corpus.samples.sorted(by: { $0.id < $1.id }) {
            let data = try RealTransactionRecognitionCorpusLoader.loadAssetBytes(
                corpusDirectory: corpusDirectory,
                sample: sample
            )
            let started = Date()
            let outcome = await recognizer.recognizeTransaction(fromImageData: data)
            let latency = max(0, Date().timeIntervalSince(started) * 1_000)
            results.append(result(sampleID: sample.id, outcome: outcome, latency: latency))
        }
        return RealTransactionRecognitionEvaluator.buildReport(
            corpus: corpus,
            corpusDigest: digest,
            candidateCommit: candidateCommit,
            metadata: recognizer.transactionRecognizerMetadata,
            results: results,
            runTimestamp: runTimestamp,
            environment: environment,
            platformOS: platformOS
        )
    }

    private static func result(
        sampleID: String,
        outcome: TransactionRecognitionOutcome,
        latency: Double
    ) -> RealRecognitionSampleResult {
        switch outcome {
        case .recognized(let draft):
            let invalid: Bool
            let failureCategory: String?
            do {
                _ = try TransactionDraftValidator.validateRecognition(draft)
                invalid = false
                failureCategory = nil
            } catch AIRecognitionError.ambiguousAmount {
                invalid = true
                failureCategory = "amountAmbiguous"
            } catch AIRecognitionError.amountMissing {
                invalid = true
                failureCategory = "amountMissing"
            } catch {
                invalid = true
                failureCategory = "invalidRecognizedDraft"
            }
            return RealRecognitionSampleResult(
                sampleID: sampleID,
                outcome: .recognized,
                observation: RecognitionQualityAdapters.observation(from: draft),
                invalidRecognizedDraft: invalid,
                failureCategory: failureCategory,
                latencyMilliseconds: latency
            )
        case .unsupported:
            return RealRecognitionSampleResult(
                sampleID: sampleID,
                outcome: .unsupported,
                observation: nil,
                invalidRecognizedDraft: false,
                failureCategory: nil,
                latencyMilliseconds: latency
            )
        case .unreadable:
            return RealRecognitionSampleResult(
                sampleID: sampleID,
                outcome: .unreadable,
                observation: nil,
                invalidRecognizedDraft: false,
                failureCategory: nil,
                latencyMilliseconds: latency
            )
        case .failure(let error):
            return RealRecognitionSampleResult(
                sampleID: sampleID,
                outcome: .failure,
                observation: nil,
                invalidRecognizedDraft: false,
                failureCategory: RecognitionQualityAdapters.operationFailureCode(error),
                latencyMilliseconds: latency
            )
        }
    }
}
