import Foundation
import Testing
import YoushuAI
import YoushuDomain

@Suite("Transaction recognition v1 contract")
struct TransactionRecognitionContractTests {
    private struct OutcomeExtractor: TransactionExtracting {
        let name = "outcome-test"
        let outcome: TransactionRecognitionOutcome

        func extractTransactionDraft(fromImageData data: Data) async throws -> TransactionDraft {
            switch outcome {
            case .recognized(let draft): return draft
            case .unsupported: throw AIRecognitionError.invalidResponse("unsupported")
            case .unreadable: throw AIRecognitionError.imageUnreadable
            case .failure(let error): throw error
            }
        }

        func recognizeTransaction(fromImageData data: Data) async -> TransactionRecognitionOutcome {
            outcome
        }
    }

    private struct ParserStub: TransactionRecognizedTextParsing {
        func parseTransaction(from spans: [RecognizedTextSpan]) -> TransactionRecognitionOutcome {
            guard spans.contains(where: { $0.text == "¥36.50" }) else { return .unsupported }
            return .recognized(TransactionDraft(amount: Decimal(string: "36.50"), transactionType: .expense))
        }
    }

    @Test("single-image outcome explicitly represents recognized, unsupported, unreadable, and failure")
    func allOutcomes() async {
        let draft = MockAIProvider.sampleSuccessDraft()
        let outcomes: [TransactionRecognitionOutcome] = [
            .recognized(draft),
            .unsupported,
            .unreadable,
            .failure(.networkTimeout),
        ]

        #expect(await OutcomeExtractor(outcome: outcomes[0]).recognizeTransaction(fromImageData: Data([1])) == .recognized(draft))
        #expect(await OutcomeExtractor(outcome: outcomes[1]).recognizeTransaction(fromImageData: Data([1])) == .unsupported)
        #expect(await OutcomeExtractor(outcome: outcomes[2]).recognizeTransaction(fromImageData: Data([1])) == .unreadable)
        #expect(await OutcomeExtractor(outcome: outcomes[3]).recognizeTransaction(fromImageData: Data([1])) == .failure(.networkTimeout))
    }

    @Test("recognized output is a review draft and not an authoritative Transaction")
    func recognizedIsDraft() async {
        let outcome = await MockAIProvider().recognizeTransaction(fromImageData: Data("fixture".utf8))
        guard case .recognized(let draft) = outcome else {
            Issue.record("Expected a reviewable draft")
            return
        }
        #expect(draft.source == .screenshot)
        #expect(draft.amount == Decimal(string: "36.50"))
    }

    @Test("Mock conforms but is never baseline eligible")
    func mockMetadata() {
        let metadata = MockAIProvider().transactionRecognizerMetadata
        #expect(metadata.providerID == "mock")
        #expect(metadata.engineVersion == "fixture-v1")
        #expect(metadata.inspectsImagePixels == false)
        #expect(metadata.baselineEligible == false)
    }

    @Test("pixel claim alone cannot make an unidentified or mock recognizer baseline eligible")
    func eligibilityRequiresReproducibleRealMetadata() {
        #expect(TransactionRecognizerMetadata(
            providerID: "real-local",
            engineVersion: nil,
            inspectsImagePixels: true
        ).baselineEligible == false)
        #expect(TransactionRecognizerMetadata(
            providerID: "mock",
            engineVersion: "pixel-claim-v1",
            inspectsImagePixels: true
        ).baselineEligible == false)
        #expect(TransactionRecognizerMetadata(
            providerID: "real-local",
            engineVersion: "engine-v1",
            inspectsImagePixels: true
        ).baselineEligible == true)
    }

    @Test("recognized text and parser boundary are platform-neutral")
    func platformNeutralParserBoundary() {
        let span = RecognizedTextSpan(text: "¥36.50", confidence: 1.4)
        #expect(span.confidence == 1)
        #expect(ParserStub().parseTransaction(from: [span]) == .recognized(
            TransactionDraft(amount: Decimal(string: "36.50"), transactionType: .expense)
        ))
    }
}
