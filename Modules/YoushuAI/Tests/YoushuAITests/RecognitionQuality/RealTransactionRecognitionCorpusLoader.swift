import Foundation
import YoushuDomain
import YoushuFoundation

enum RealTransactionRecognitionCorpusLoader {
    static let schemaVersion = "RealTransactionRecognitionCorpusV1"
    static let unavailableMessage = "REAL BASELINE CORPUS NOT AVAILABLE"

    static func availability(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> RealRecognitionCorpusAvailability {
        guard let rawDirectory = environment["REAL_RECOGNITION_CORPUS"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !rawDirectory.isEmpty
        else {
            return .unavailable(unavailableMessage)
        }
        let candidate = environment["REAL_RECOGNITION_CANDIDATE_COMMIT"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let reportURL = environment["REAL_RECOGNITION_REPORT"]
            .flatMap { raw -> URL? in
                let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : URL(fileURLWithPath: value)
            }
        return .available(
            directory: URL(fileURLWithPath: rawDirectory, isDirectory: true),
            candidateCommit: candidate,
            reportURL: reportURL
        )
    }

    static func load(from directory: URL) throws -> RealTransactionRecognitionCorpusV1 {
        let manifestURL = directory.appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: manifestURL)
        let corpus = try JSONDecoder().decode(RealTransactionRecognitionCorpusV1.self, from: data)
        try validate(corpus, corpusDirectory: directory)
        return corpus
    }

    static func parseAndValidate(
        _ data: Data,
        corpusDirectory: URL
    ) throws -> RealTransactionRecognitionCorpusV1 {
        let corpus = try JSONDecoder().decode(RealTransactionRecognitionCorpusV1.self, from: data)
        try validate(corpus, corpusDirectory: corpusDirectory)
        return corpus
    }

    static func validate(
        _ corpus: RealTransactionRecognitionCorpusV1,
        corpusDirectory: URL
    ) throws {
        guard corpus.schemaVersion == schemaVersion else {
            throw RealTransactionRecognitionCorpusError.unsupportedVersion(corpus.schemaVersion)
        }
        guard !corpus.corpusVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RealTransactionRecognitionCorpusError.emptyCorpusVersion
        }
        guard TimeZone(identifier: corpus.timeZone) != nil || corpus.timeZone == "UTC" else {
            throw RealTransactionRecognitionCorpusError.invalidTimeZone(corpus.timeZone)
        }

        var ids = Set<String>()
        for sample in corpus.samples {
            guard isOpaqueSampleID(sample.id) else {
                throw RealTransactionRecognitionCorpusError.nonOpaqueSampleID(sample.id)
            }
            guard ids.insert(sample.id).inserted else {
                throw RealTransactionRecognitionCorpusError.duplicateSampleID(sample.id)
            }
            guard !sample.screenshotQualities.isEmpty else {
                throw RealTransactionRecognitionCorpusError.emptyQualityLabels(sample.id)
            }
            try validateAsset(sample.asset, sampleID: sample.id, corpusDirectory: corpusDirectory)
            try validateLabels(sample, timeZone: corpus.timeZone)
        }
    }

    static func validateCandidateCommit(_ candidate: String) throws {
        let scalars = candidate.unicodeScalars
        guard scalars.count == 40,
              scalars.allSatisfy({ scalar in
                  (scalar.value >= 48 && scalar.value <= 57)
                      || (scalar.value >= 97 && scalar.value <= 102)
              })
        else {
            throw RealTransactionRecognitionCorpusError.invalidCandidateCommit(candidate)
        }
    }

    static func corpusDigest(
        corpus: RealTransactionRecognitionCorpusV1,
        corpusDirectory: URL
    ) throws -> String {
        struct CanonicalSample: Codable {
            var id: String
            var imageDigest: String
            var sourceKind: RealRecognitionSourceKind
            var platform: RealRecognitionPlatform
            var family: RealRecognitionFamily
            var screenshotQualities: [RealRecognitionScreenshotQuality]
            var expectedOutcome: RealRecognitionExpectedOutcome
            var transaction: RealTransactionGroundTruthV1?
        }
        struct CanonicalCorpus: Codable {
            var schemaVersion: String
            var corpusVersion: String
            var timeZone: String
            var samples: [CanonicalSample]
        }

        try validate(corpus, corpusDirectory: corpusDirectory)
        let samples = try corpus.samples.sorted { $0.id < $1.id }.map { sample in
            let bytes = try Data(contentsOf: corpusDirectory.appendingPathComponent(sample.asset))
            return CanonicalSample(
                id: sample.id,
                imageDigest: DeterministicSHA256.digestHex(bytes),
                sourceKind: sample.sourceKind,
                platform: sample.platform,
                family: sample.family,
                screenshotQualities: sample.screenshotQualities.sorted { $0.rawValue < $1.rawValue },
                expectedOutcome: sample.expectedOutcome,
                transaction: sample.transaction
            )
        }
        let canonical = CanonicalCorpus(
            schemaVersion: corpus.schemaVersion,
            corpusVersion: corpus.corpusVersion,
            timeZone: corpus.timeZone,
            samples: samples
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return DeterministicSHA256.digestHex(try encoder.encode(canonical))
    }

    static func loadAssetBytes(
        corpusDirectory: URL,
        sample: RealTransactionRecognitionSampleV1
    ) throws -> Data {
        try Data(contentsOf: corpusDirectory.appendingPathComponent(sample.asset))
    }

    private static func isOpaqueSampleID(_ value: String) -> Bool {
        guard value.hasPrefix("rq-"), (15 ... 67).contains(value.count) else { return false }
        return value.dropFirst(3).unicodeScalars.allSatisfy { scalar in
            (scalar.value >= 48 && scalar.value <= 57)
                || (scalar.value >= 97 && scalar.value <= 102)
        }
    }

    private static func validateAsset(
        _ relativePath: String,
        sampleID: String,
        corpusDirectory: URL
    ) throws {
        let normalized = relativePath.replacingOccurrences(of: "\\", with: "/")
        guard !normalized.isEmpty,
              !normalized.hasPrefix("/"),
              !normalized.contains(":/"),
              !normalized.split(separator: "/").contains("..")
        else {
            throw RealTransactionRecognitionCorpusError.unsafeAssetPath(sampleID)
        }
        let url = corpusDirectory.appendingPathComponent(relativePath)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber,
              size.intValue > 0
        else {
            throw RealTransactionRecognitionCorpusError.missingAsset(sampleID)
        }
    }

    private static func validateLabels(
        _ sample: RealTransactionRecognitionSampleV1,
        timeZone: String
    ) throws {
        switch sample.expectedOutcome {
        case .recognized:
            guard let truth = sample.transaction,
                  sample.family != .readableUnsupported,
                  sample.family != .unreadable
            else {
                throw RealTransactionRecognitionCorpusError.outcomeLabelMismatch(sample.id)
            }
            if case .known(let amount) = truth.amount,
               let decimal = Decimal(string: amount.trimmingCharacters(in: .whitespacesAndNewlines)) {
                guard decimal > 0 else {
                    throw RealTransactionRecognitionCorpusError.invalidDecimal(sample.id)
                }
            } else if truth.amount.knownValue != nil {
                throw RealTransactionRecognitionCorpusError.invalidDecimal(sample.id)
            }
            if case .known(let direction) = truth.direction,
               TransactionType(rawValue: direction) == nil {
                throw RealTransactionRecognitionCorpusError.invalidDirection(sample.id)
            }
            switch truth.occurredAt {
            case .unknown:
                guard truth.occurredAtPrecision == nil else {
                    throw RealTransactionRecognitionCorpusError.invalidOccurredAt(sample.id)
                }
            case .known(let raw):
                guard let precision = truth.occurredAtPrecision,
                      RealRecognitionDateCompare.parse(raw, precision: precision, timeZone: timeZone) != nil
                else {
                    throw RealTransactionRecognitionCorpusError.invalidOccurredAt(sample.id)
                }
            }
        case .unsupported:
            guard sample.transaction == nil, sample.family == .readableUnsupported else {
                throw RealTransactionRecognitionCorpusError.outcomeLabelMismatch(sample.id)
            }
        case .unreadable:
            guard sample.transaction == nil, sample.family == .unreadable else {
                throw RealTransactionRecognitionCorpusError.outcomeLabelMismatch(sample.id)
            }
        }
    }
}

enum RealRecognitionDateCompare {
    static func parse(
        _ raw: String,
        precision: RealRecognitionDatePrecision,
        timeZone: String
    ) -> Date? {
        let zone = TimeZone(identifier: timeZone) ?? TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        switch precision {
        case .day:
            guard let day = RecognitionQualityCompare.parseDay(raw, timeZoneIdentifier: timeZone) else { return nil }
            return calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day))
        case .minute:
            let parts = raw.split(separator: "T", omittingEmptySubsequences: false)
            guard parts.count == 2,
                  let day = RecognitionQualityCompare.parseDay(String(parts[0]), timeZoneIdentifier: timeZone)
            else { return nil }
            let time = parts[1].split(separator: ":", omittingEmptySubsequences: false)
            guard time.count == 2,
                  let hour = Int(time[0]), (0 ... 23).contains(hour),
                  let minute = Int(time[1]), (0 ... 59).contains(minute)
            else { return nil }
            return calendar.date(from: DateComponents(
                year: day.year,
                month: day.month,
                day: day.day,
                hour: hour,
                minute: minute
            ))
        }
    }

    static func matches(
        expected raw: String,
        precision: RealRecognitionDatePrecision,
        observed: Date?,
        timeZone: String
    ) -> FieldOutcome {
        guard let expected = parse(raw, precision: precision, timeZone: timeZone) else { return .incorrect }
        guard let observed else { return .missing }
        let zone = TimeZone(identifier: timeZone) ?? TimeZone(secondsFromGMT: 0)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let components: Set<Calendar.Component> = precision == .day
            ? [.year, .month, .day]
            : [.year, .month, .day, .hour, .minute]
        return calendar.dateComponents(components, from: expected)
            == calendar.dateComponents(components, from: observed) ? .correct : .incorrect
    }
}
