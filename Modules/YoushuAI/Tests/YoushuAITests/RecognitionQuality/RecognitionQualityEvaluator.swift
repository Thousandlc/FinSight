import Foundation
import YoushuDomain

enum RecognitionQualityCompare {
    static func normalizeText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let collapsed = trimmed.split { $0.isWhitespace }.joined(separator: " ")
        return collapsed.precomposedStringWithCanonicalMapping
    }

    static func parseDecimal(_ raw: String) -> Decimal? {
        Decimal(string: raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func parseDay(_ raw: String, timeZoneIdentifier: String) -> (year: Int, month: Int, day: Int)? {
        let parts = raw.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2])
        else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard calendar.date(from: components) != nil else { return nil }
        return (year, month, day)
    }

    static func dayComponents(of date: Date, timeZoneIdentifier: String) -> (year: Int, month: Int, day: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return (parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func classifyText(expected: OptionalFact<String>, observed: String?) -> FieldOutcome {
        switch expected {
        case .unknown:
            return normalizeText(observed) == nil ? .correctlyUnknown : .invented
        case .known(let raw):
            let expectedNorm = normalizeText(raw)
            let observedNorm = normalizeText(observed)
            guard let expectedNorm else {
                return observedNorm == nil ? .correct : .incorrect
            }
            guard let observedNorm else { return .missing }
            return expectedNorm == observedNorm ? .correct : .incorrect
        }
    }

    static func classifyDecimal(expected: OptionalFact<String>, observed: Decimal?) -> FieldOutcome {
        switch expected {
        case .unknown:
            return observed == nil ? .correctlyUnknown : .invented
        case .known(let raw):
            guard let expectedValue = parseDecimal(raw) else { return .incorrect }
            guard let observed else { return .missing }
            return expectedValue == observed ? .correct : .incorrect
        }
    }

    static func classifyEnum<T: RawRepresentable & Equatable>(
        expected: OptionalFact<String>,
        observed: T?
    ) -> FieldOutcome where T.RawValue == String {
        switch expected {
        case .unknown:
            return observed == nil ? .correctlyUnknown : .invented
        case .known(let raw):
            guard let expectedValue = T(rawValue: raw) else { return .incorrect }
            guard let observed else { return .missing }
            return expectedValue == observed ? .correct : .incorrect
        }
    }

    static func classifyDay(
        expected: OptionalFact<String>,
        observed: Date?,
        spec: DateComparisonSpec
    ) -> FieldOutcome {
        let zone = spec.timeZone
        switch expected {
        case .unknown:
            return observed == nil ? .correctlyUnknown : .invented
        case .known(let raw):
            guard let expectedDay = parseDay(raw, timeZoneIdentifier: zone) else { return .incorrect }
            guard let observed else { return .missing }
            let observedDay = dayComponents(of: observed, timeZoneIdentifier: zone)
            return expectedDay == observedDay ? .correct : .incorrect
        }
    }
}

enum RecognitionQualityTransactionEvaluator {
    static func evaluate(
        truth: TransactionGroundTruthV1,
        observation: TransactionRecognitionObservation,
        spec: DateComparisonSpec
    ) -> (fields: [String: FieldOutcome], exact: Bool) {
        let fields: [String: FieldOutcome] = [
            "amount": RecognitionQualityCompare.classifyDecimal(expected: truth.amount, observed: observation.amount),
            "currencyCode": RecognitionQualityCompare.classifyText(
                expected: truth.currencyCode,
                observed: observation.currencyCode
            ),
            "transactionType": RecognitionQualityCompare.classifyEnum(
                expected: truth.transactionType,
                observed: observation.transactionType
            ),
            "date": RecognitionQualityCompare.classifyDay(
                expected: truth.date,
                observed: observation.date,
                spec: spec
            ),
            "merchant": RecognitionQualityCompare.classifyText(
                expected: truth.merchant,
                observed: observation.merchant
            ),
            "category": RecognitionQualityCompare.classifyText(
                expected: truth.category,
                observed: observation.category
            ),
        ]
        let exact = fields.values.allSatisfy { $0 == .correct || $0 == .correctlyUnknown }
        return (fields, exact)
    }
}

enum RecognitionQualityDebtEvaluator {
    /// v1 match key: normalized known lender + productName + debtType.
    /// Same-key leftovers pair by lexicographic money/date tie-break.
    /// Unmatched expected = missed; unmatched observed = extra.
    /// Does not use Provider order or production UUID.
    static func match(
        expected: [DebtCandidateGroundTruthV1],
        observed: [DebtCandidateObservation]
    ) -> (pairs: [(DebtCandidateGroundTruthV1, DebtCandidateObservation)], missed: Int, extra: Int) {
        struct ObservedItem {
            var index: Int
            var observation: DebtCandidateObservation
            var key: String
            var tie: String
        }

        var remaining = observed.enumerated().map { item in
            ObservedItem(
                index: item.offset,
                observation: item.element,
                key: matchKey(observation: item.element),
                tie: tieBreak(observation: item.element)
            )
        }
        remaining.sort {
            if $0.key != $1.key { return $0.key < $1.key }
            if $0.tie != $1.tie { return $0.tie < $1.tie }
            return $0.index < $1.index
        }

        let expectedSorted = expected.enumerated().sorted { lhs, rhs in
            let lKey = matchKey(truth: lhs.element)
            let rKey = matchKey(truth: rhs.element)
            if lKey != rKey { return lKey < rKey }
            let lTie = tieBreak(truth: lhs.element)
            let rTie = tieBreak(truth: rhs.element)
            if lTie != rTie { return lTie < rTie }
            return lhs.offset < rhs.offset
        }

        var pairs: [(DebtCandidateGroundTruthV1, DebtCandidateObservation)] = []
        var used = Set<Int>()
        for item in expectedSorted {
            let key = matchKey(truth: item.element)
            let tie = tieBreak(truth: item.element)
            let candidates = remaining.filter { $0.key == key && !used.contains($0.index) }
            guard !candidates.isEmpty else { continue }
            let chosen = candidates.min { lhs, rhs in
                if lhs.tie != rhs.tie {
                    let lDistance = lhs.tie == tie
                    let rDistance = rhs.tie == tie
                    if lDistance != rDistance { return lDistance && !rDistance }
                    return lhs.tie < rhs.tie
                }
                return lhs.index < rhs.index
            }!
            used.insert(chosen.index)
            pairs.append((item.element, chosen.observation))
        }

        let missed = expected.count - pairs.count
        let extra = observed.count - pairs.count
        return (pairs, missed, extra)
    }

    static func evaluatePair(
        truth: DebtCandidateGroundTruthV1,
        observation: DebtCandidateObservation,
        spec: DateComparisonSpec
    ) -> [String: FieldOutcome] {
        [
            "lender": RecognitionQualityCompare.classifyText(expected: truth.lender, observed: observation.lender),
            "productName": RecognitionQualityCompare.classifyText(
                expected: truth.productName,
                observed: observation.productName
            ),
            "debtType": RecognitionQualityCompare.classifyEnum(
                expected: truth.debtType,
                observed: observation.debtType
            ),
            "outstandingBalance": RecognitionQualityCompare.classifyDecimal(
                expected: truth.outstandingBalance,
                observed: observation.outstandingBalance
            ),
            "currentDue": RecognitionQualityCompare.classifyDecimal(
                expected: truth.currentDue,
                observed: observation.currentDue
            ),
            "minimumDue": RecognitionQualityCompare.classifyDecimal(
                expected: truth.minimumDue,
                observed: observation.minimumDue
            ),
            "installmentAmount": RecognitionQualityCompare.classifyDecimal(
                expected: truth.installmentAmount,
                observed: observation.installmentAmount
            ),
            "dueDate": RecognitionQualityCompare.classifyDay(
                expected: truth.dueDate,
                observed: observation.dueDate,
                spec: spec
            ),
            "interestRate": RecognitionQualityCompare.classifyDecimal(
                expected: truth.interestRate,
                observed: observation.interestRate
            ),
        ]
    }

    static func matchKey(truth: DebtCandidateGroundTruthV1) -> String {
        [
            RecognitionQualityCompare.normalizeText(truth.lender.knownValue) ?? "",
            RecognitionQualityCompare.normalizeText(truth.productName.knownValue) ?? "",
            truth.debtType.knownValue ?? "",
        ].joined(separator: "\u{1f}")
    }

    static func matchKey(observation: DebtCandidateObservation) -> String {
        [
            RecognitionQualityCompare.normalizeText(observation.lender) ?? "",
            RecognitionQualityCompare.normalizeText(observation.productName) ?? "",
            observation.debtType?.rawValue ?? "",
        ].joined(separator: "\u{1f}")
    }

    static func tieBreak(truth: DebtCandidateGroundTruthV1) -> String {
        [
            truth.outstandingBalance.knownValue ?? "",
            truth.currentDue.knownValue ?? "",
            truth.minimumDue.knownValue ?? "",
            truth.installmentAmount.knownValue ?? "",
            truth.dueDate.knownValue ?? "",
        ].joined(separator: "\u{1f}")
    }

    static func canonicalDecimal(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    static func tieBreak(observation: DebtCandidateObservation) -> String {
        [
            observation.outstandingBalance.map(canonicalDecimal) ?? "",
            observation.currentDue.map(canonicalDecimal) ?? "",
            observation.minimumDue.map(canonicalDecimal) ?? "",
            observation.installmentAmount.map(canonicalDecimal) ?? "",
            observation.dueDate.map { ISO8601DateFormatter().string(from: $0) } ?? "",
        ].joined(separator: "\u{1f}")
    }
}

enum RecognitionQualityReportBuilder {
    static func build(
        corpus: RecognitionQualityCorpusV1,
        recognizerLabel: String,
        baselineEligible: Bool,
        baselineIneligibilityReasons: [String],
        runs: [(fixtureID: String, run: RecognitionFixtureRun)]
    ) -> RecognitionQualityReportV1 {
        let byID = Dictionary(uniqueKeysWithValues: corpus.fixtures.map { ($0.id, $0) })
        let ordered = runs.sorted { $0.fixtureID < $1.fixtureID }

        var txMetrics = TransactionQualityMetricsV1()
        var debtMetrics = DebtQualityMetricsV1()
        var failures: [String] = []
        var txCount = 0
        var debtCount = 0

        for item in ordered {
            guard let fixture = byID[item.fixtureID] else { continue }
            switch fixture.capability {
            case .transactionScreenshot: txCount += 1
            case .debtScreenshot: debtCount += 1
            }

            switch item.run {
            case .operationFailure:
                failures.append(item.fixtureID)
            case .observation(let observation):
                switch (fixture.capability, observation, fixture.transaction, fixture.debt) {
                case (.transactionScreenshot, .transaction(let observed), let truth?, nil):
                    let result = RecognitionQualityTransactionEvaluator.evaluate(
                        truth: truth,
                        observation: observed,
                        spec: corpus.dateComparison
                    )
                    addTransaction(&txMetrics, fields: result.fields, exact: result.exact)
                case (.debtScreenshot, .debt(let observed), nil, let truth?):
                    addDebt(&debtMetrics, truth: truth, observed: observed, spec: corpus.dateComparison)
                default:
                    failures.append(item.fixtureID)
                }
            }
        }

        var eligible = baselineEligible
        var reasons = baselineIneligibilityReasons.sorted()
        if recognizerLabel == "mock" {
            eligible = false
            for reason in RecognitionQualityBaseline.mockReasons where !reasons.contains(reason) {
                reasons.append(reason)
            }
            reasons.sort()
        }

        return RecognitionQualityReportV1(
            schemaVersion: "RecognitionQualityReportV1",
            corpusVersion: corpus.corpusVersion,
            recognizerLabel: recognizerLabel,
            baselineEligible: eligible,
            baselineIneligibilityReasons: reasons,
            fixtureCount: corpus.fixtures.count,
            transactionFixtureCount: txCount,
            debtFixtureCount: debtCount,
            operationFailureCount: failures.count,
            operationFailureFixtureIDs: failures,
            transaction: txMetrics,
            debt: debtMetrics
        )
    }

    static func encodeDeterministic(_ report: RecognitionQualityReportV1) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(report)
        guard let string = String(data: data, encoding: .utf8) else {
            throw RecognitionQualityCorpusError.invalidPresence("utf8")
        }
        return string
    }

    private static func addTransaction(
        _ metrics: inout TransactionQualityMetricsV1,
        fields: [String: FieldOutcome],
        exact: Bool
    ) {
        metrics.wholeRecordEvaluatedCount += 1
        if exact { metrics.wholeRecordExactCount += 1 }
        metrics.amount.add(fields["amount"] ?? .incorrect)
        metrics.transactionType.add(fields["transactionType"] ?? .incorrect)
        metrics.date.add(fields["date"] ?? .incorrect)
        metrics.merchant.add(fields["merchant"] ?? .incorrect)
        metrics.category.add(fields["category"] ?? .incorrect)
        metrics.currencyCode.add(fields["currencyCode"] ?? .incorrect)
    }

    private static func addDebt(
        _ metrics: inout DebtQualityMetricsV1,
        truth: DebtGroundTruthV1,
        observed: DebtRecognitionObservation,
        spec: DateComparisonSpec
    ) {
        let matched = RecognitionQualityDebtEvaluator.match(
            expected: truth.candidates,
            observed: observed.candidates
        )
        metrics.expectedCandidateCount += truth.candidates.count
        metrics.observedCandidateCount += observed.candidates.count
        metrics.matchedCount += matched.pairs.count
        metrics.missedCandidateCount += matched.missed
        metrics.extraCandidateCount += matched.extra
        for pair in matched.pairs {
            let fields = RecognitionQualityDebtEvaluator.evaluatePair(
                truth: pair.0,
                observation: pair.1,
                spec: spec
            )
            metrics.lender.add(fields["lender"] ?? .incorrect)
            metrics.productName.add(fields["productName"] ?? .incorrect)
            metrics.debtType.add(fields["debtType"] ?? .incorrect)
            metrics.outstandingBalance.add(fields["outstandingBalance"] ?? .incorrect)
            metrics.currentDue.add(fields["currentDue"] ?? .incorrect)
            metrics.minimumDue.add(fields["minimumDue"] ?? .incorrect)
            metrics.installmentAmount.add(fields["installmentAmount"] ?? .incorrect)
            metrics.dueDate.add(fields["dueDate"] ?? .incorrect)
            metrics.interestRate.add(fields["interestRate"] ?? .incorrect)
        }
    }
}

private func == (
    lhs: (year: Int, month: Int, day: Int),
    rhs: (year: Int, month: Int, day: Int)
) -> Bool {
    lhs.year == rhs.year && lhs.month == rhs.month && lhs.day == rhs.day
}
