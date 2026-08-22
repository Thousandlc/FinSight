import Foundation
import Testing
import YoushuFoundation

@Suite("Observability taxonomy Swift/Go parity fixture")
struct ObservabilityTaxonomyParityTests {
    private struct Fixture: Decodable {
        struct CodeRow: Decodable {
            var code: String
            var failureClass: String
            var retryability: String
        }

        var errorCodes: [CodeRow]
        var failureStages: [String]
        var outcomes: [String]
    }

    private func loadFixture() throws -> Fixture {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<12 {
            let candidate = dir.appendingPathComponent("contracts/observability_taxonomy_defaults.json")
            if FileManager.default.fileExists(atPath: candidate.path) {
                let data = try Data(contentsOf: candidate)
                return try JSONDecoder().decode(Fixture.self, from: data)
            }
            dir.deleteLastPathComponent()
        }
        Issue.record("taxonomy fixture not found")
        struct FixtureMissing: Error {}
        throw FixtureMissing()
    }

    @Test("Swift defaults match the shared taxonomy fixture")
    func swiftMatchesSharedFixture() throws {
        let fixture = try loadFixture()
        #expect(Set(fixture.failureStages) == Set(ObservabilityFailureStage.allCases.map(\.rawValue)))
        #expect(Set(fixture.outcomes) == Set(ObservabilityOutcome.allCases.map(\.rawValue)))
        #expect(fixture.errorCodes.count == ObservabilityErrorCode.allCases.count)

        var seen = Set<String>()
        for row in fixture.errorCodes {
            let code = try #require(ObservabilityErrorCode(rawValue: row.code))
            seen.insert(row.code)
            let attributes = ObservabilityErrorMapping.attributes(for: code)
            #expect(attributes.failureClass.rawValue == row.failureClass, "class drift for \(row.code)")
            #expect(attributes.retryability.rawValue == row.retryability, "retry drift for \(row.code)")
        }
        #expect(seen == Set(ObservabilityErrorCode.allCases.map(\.rawValue)))
    }

    @Test("networkUnavailable default is notRetryable to match iOS runtime")
    func networkUnavailableDefault() {
        let classified = ObservabilityErrorMapping.classify(URLError(.notConnectedToInternet))
        #expect(classified.errorCode == .networkUnavailable)
        #expect(classified.retryability == .notRetryable)
        #expect(classified.stage == .clientTransport)
    }
}
