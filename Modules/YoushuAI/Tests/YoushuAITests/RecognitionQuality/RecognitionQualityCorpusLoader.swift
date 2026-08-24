import Foundation
import YoushuDomain

enum RecognitionQualityCorpusLoader {
    static let committedSchemaVersion = "RecognitionQualityCorpusV1"

    static func repoRoot(from filePath: String = #filePath) -> URL {
        var url = URL(fileURLWithPath: filePath)
        while url.pathComponents.count > 1 {
            let candidate = url
                .deletingLastPathComponent()
                .appendingPathComponent("TestFixtures/RecognitionQualityV1/corpus.json")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return url.deletingLastPathComponent()
            }
            url.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    static func committedCorpusDirectory(from filePath: String = #filePath) -> URL {
        repoRoot(from: filePath).appendingPathComponent("TestFixtures/RecognitionQualityV1")
    }

    static func loadCommittedV1(from filePath: String = #filePath) throws -> (corpus: RecognitionQualityCorpusV1, directory: URL) {
        let directory = committedCorpusDirectory(from: filePath)
        let url = directory.appendingPathComponent("corpus.json")
        let data = try Data(contentsOf: url)
        let corpus = try parseAndValidate(
            data,
            corpusDirectory: directory,
            requireNoRealUserData: true
        )
        return (corpus, directory)
    }

    static func parseAndValidate(
        _ data: Data,
        corpusDirectory: URL,
        requireNoRealUserData: Bool
    ) throws -> RecognitionQualityCorpusV1 {
        let decoder = JSONDecoder()
        let corpus = try decoder.decode(RecognitionQualityCorpusV1.self, from: data)
        try validate(
            corpus,
            corpusDirectory: corpusDirectory,
            requireNoRealUserData: requireNoRealUserData
        )
        return corpus
    }

    static func validate(
        _ corpus: RecognitionQualityCorpusV1,
        corpusDirectory: URL,
        requireNoRealUserData: Bool
    ) throws {
        guard corpus.schemaVersion == committedSchemaVersion else {
            throw RecognitionQualityCorpusError.unsupportedVersion(corpus.schemaVersion)
        }
        guard corpus.dateComparison.precision == "day" else {
            throw RecognitionQualityCorpusError.invalidDate("unsupported precision \(corpus.dateComparison.precision)")
        }
        guard TimeZone(identifier: corpus.dateComparison.timeZone) != nil
            || corpus.dateComparison.timeZone == "UTC"
        else {
            throw RecognitionQualityCorpusError.invalidTimeZone(corpus.dateComparison.timeZone)
        }

        var seen = Set<String>()
        for fixture in corpus.fixtures {
            if !seen.insert(fixture.id).inserted {
                throw RecognitionQualityCorpusError.duplicateFixtureID(fixture.id)
            }
            if requireNoRealUserData && fixture.containsRealUserData {
                throw RecognitionQualityCorpusError.realUserDataNotAllowed(fixture.id)
            }
            switch fixture.capability {
            case .transactionScreenshot:
                guard fixture.transaction != nil, fixture.debt == nil else {
                    throw RecognitionQualityCorpusError.capabilityMismatch(fixture.id)
                }
                guard fixture.assets.count == 1 else {
                    throw RecognitionQualityCorpusError.capabilityMismatch(fixture.id)
                }
                try validateTransactionTruth(fixture.transaction!, fixtureID: fixture.id)
            case .debtScreenshot:
                guard fixture.debt != nil, fixture.transaction == nil else {
                    throw RecognitionQualityCorpusError.capabilityMismatch(fixture.id)
                }
                if fixture.assets.isEmpty {
                    throw RecognitionQualityCorpusError.emptyDebtDocuments(fixture.id)
                }
                try validateDebtTruth(fixture.debt!, fixtureID: fixture.id)
            }
            for relative in fixture.assets {
                let url = corpusDirectory.appendingPathComponent(relative)
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                      !isDirectory.boolValue,
                      let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                      let size = attrs[.size] as? NSNumber,
                      size.intValue > 0
                else {
                    throw RecognitionQualityCorpusError.missingAsset(fixtureID: fixture.id, path: relative)
                }
            }
        }
    }

    static func loadAssetBytes(corpusDirectory: URL, relativePath: String) throws -> Data {
        let url = corpusDirectory.appendingPathComponent(relativePath)
        return try Data(contentsOf: url)
    }

    private static func validateTransactionTruth(_ truth: TransactionGroundTruthV1, fixtureID: String) throws {
        try validateMoneyFact(truth.amount, fixtureID: fixtureID)
        try validateMoneyFact(truth.currencyCode, fixtureID: fixtureID, allowNonDecimal: true)
        if case .known(let raw) = truth.transactionType {
            guard TransactionType(rawValue: raw) != nil else {
                throw RecognitionQualityCorpusError.capabilityMismatch(fixtureID)
            }
        }
        try validateDateFact(truth.date, fixtureID: fixtureID)
    }

    private static func validateDebtTruth(_ truth: DebtGroundTruthV1, fixtureID: String) throws {
        guard !truth.candidates.isEmpty else {
            throw RecognitionQualityCorpusError.capabilityMismatch(fixtureID)
        }
        var localIDs = Set<String>()
        for candidate in truth.candidates {
            if !localIDs.insert(candidate.localId).inserted {
                throw RecognitionQualityCorpusError.duplicateFixtureID("\(fixtureID):\(candidate.localId)")
            }
            try validateMoneyFact(candidate.outstandingBalance, fixtureID: fixtureID)
            try validateMoneyFact(candidate.currentDue, fixtureID: fixtureID)
            try validateMoneyFact(candidate.minimumDue, fixtureID: fixtureID)
            try validateMoneyFact(candidate.installmentAmount, fixtureID: fixtureID)
            try validateMoneyFact(candidate.interestRate, fixtureID: fixtureID)
            try validateDateFact(candidate.dueDate, fixtureID: fixtureID)
            if case .known(let raw) = candidate.debtType {
                guard DebtType(rawValue: raw) != nil else {
                    throw RecognitionQualityCorpusError.capabilityMismatch(fixtureID)
                }
            }
        }
    }

    private static func validateMoneyFact(_ fact: OptionalFact<String>, fixtureID: String, allowNonDecimal: Bool = false) throws {
        guard case .known(let raw) = fact else { return }
        if allowNonDecimal { return }
        guard Decimal(string: raw) != nil else {
            throw RecognitionQualityCorpusError.invalidDecimal("\(fixtureID):\(raw)")
        }
    }

    private static func validateDateFact(_ fact: OptionalFact<String>, fixtureID: String) throws {
        guard case .known(let raw) = fact else { return }
        guard RecognitionQualityCompare.parseDay(raw, timeZoneIdentifier: "UTC") != nil else {
            throw RecognitionQualityCorpusError.invalidDate("\(fixtureID):\(raw)")
        }
    }
}
