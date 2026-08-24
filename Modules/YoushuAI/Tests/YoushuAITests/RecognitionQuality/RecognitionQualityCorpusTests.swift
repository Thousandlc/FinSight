import Foundation
import Testing
import YoushuDomain

@Suite("Recognition quality corpus v1")
struct RecognitionQualityCorpusTests {
    @Test("valid v1 corpus loads")
    func validCorpusLoads() throws {
        let loaded = try RecognitionQualityCorpusLoader.loadCommittedV1()
        #expect(loaded.corpus.schemaVersion == "RecognitionQualityCorpusV1")
        #expect(loaded.corpus.corpusVersion == "1")
        #expect(loaded.corpus.fixtures.count == 9)
        #expect(Set(loaded.corpus.fixtures.map(\.id)).count == 9)
        #expect(loaded.corpus.fixtures.allSatisfy { $0.containsRealUserData == false })
        #expect(loaded.corpus.fixtures.contains { $0.id == "tx-unknown-merchant" })
        #expect(loaded.corpus.fixtures.contains { $0.id == "debt-current-due-only" })
        #expect(loaded.corpus.fixtures.contains { $0.id == "debt-multi-document" })
        #expect(loaded.corpus.fixtures.contains { $0.id == "debt-multi-candidate" })
        let currentDueOnly = try #require(loaded.corpus.fixtures.first { $0.id == "debt-current-due-only" })
        #expect(currentDueOnly.debt?.candidates.first?.outstandingBalance == .unknown)
        #expect(currentDueOnly.debt?.candidates.first?.currentDue == .known("2300.00"))
        for fixture in loaded.corpus.fixtures {
            for asset in fixture.assets {
                let data = try RecognitionQualityCorpusLoader.loadAssetBytes(
                    corpusDirectory: loaded.directory,
                    relativePath: asset
                )
                #expect(!data.isEmpty)
            }
        }
    }

    @Test("unsupported version is rejected")
    func unsupportedVersionRejected() throws {
        let json = """
        {"schemaVersion":"RecognitionQualityCorpusV0","corpusVersion":"1","dateComparison":{"precision":"day","timeZone":"UTC"},"fixtures":[]}
        """
        #expect(throws: RecognitionQualityCorpusError.unsupportedVersion("RecognitionQualityCorpusV0")) {
            try RecognitionQualityCorpusLoader.parseAndValidate(
                Data(json.utf8),
                corpusDirectory: RecognitionQualityCorpusLoader.committedCorpusDirectory(),
                requireNoRealUserData: true
            )
        }
    }

    @Test("duplicate fixture ID is rejected")
    func duplicateFixtureIDRejected() throws {
        let loaded = try RecognitionQualityCorpusLoader.loadCommittedV1()
        var corpus = loaded.corpus
        corpus.fixtures.append(corpus.fixtures[0])
        #expect(throws: RecognitionQualityCorpusError.duplicateFixtureID(corpus.fixtures[0].id)) {
            try RecognitionQualityCorpusLoader.validate(
                corpus,
                corpusDirectory: loaded.directory,
                requireNoRealUserData: true
            )
        }
    }

    @Test("missing asset is rejected")
    func missingAssetRejected() throws {
        let loaded = try RecognitionQualityCorpusLoader.loadCommittedV1()
        var corpus = loaded.corpus
        corpus.fixtures[0].assets = ["assets/does-not-exist.png"]
        #expect(throws: RecognitionQualityCorpusError.missingAsset(
            fixtureID: corpus.fixtures[0].id,
            path: "assets/does-not-exist.png"
        )) {
            try RecognitionQualityCorpusLoader.validate(
                corpus,
                corpusDirectory: loaded.directory,
                requireNoRealUserData: true
            )
        }
    }

    @Test("real-user-data flag is rejected for committed corpus")
    func realUserDataRejected() throws {
        let loaded = try RecognitionQualityCorpusLoader.loadCommittedV1()
        var corpus = loaded.corpus
        corpus.fixtures[0].containsRealUserData = true
        #expect(throws: RecognitionQualityCorpusError.realUserDataNotAllowed(corpus.fixtures[0].id)) {
            try RecognitionQualityCorpusLoader.validate(
                corpus,
                corpusDirectory: loaded.directory,
                requireNoRealUserData: true
            )
        }
    }

    @Test("empty debt document list is rejected")
    func emptyDebtDocumentsRejected() throws {
        let loaded = try RecognitionQualityCorpusLoader.loadCommittedV1()
        var corpus = loaded.corpus
        guard let index = corpus.fixtures.firstIndex(where: { $0.capability == .debtScreenshot }) else {
            Issue.record("expected a debt fixture")
            return
        }
        corpus.fixtures[index].assets = []
        #expect(throws: RecognitionQualityCorpusError.emptyDebtDocuments(corpus.fixtures[index].id)) {
            try RecognitionQualityCorpusLoader.validate(
                corpus,
                corpusDirectory: loaded.directory,
                requireNoRealUserData: true
            )
        }
    }
}
