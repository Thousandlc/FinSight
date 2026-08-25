import Foundation
import Testing
import YoushuAI

@Suite("Real Transaction Recognition baseline run")
struct RealTransactionRecognitionBaselineRunTests {
    @Test("private corpus runs only when explicitly configured")
    func runConfiguredPrivateCorpus() async throws {
        switch RealTransactionRecognitionCorpusLoader.availability() {
        case .unavailable(let message):
            print(message)
        case .available(let directory, let candidateCommit, let reportURL):
            #if canImport(Vision)
            let corpus = try RealTransactionRecognitionCorpusLoader.load(from: directory)
            let formatter = ISO8601DateFormatter()
            let report = try await RealTransactionRecognitionHarness.evaluate(
                corpus: corpus,
                corpusDirectory: directory,
                recognizer: AppleVisionTransactionRecognizer(),
                candidateCommit: candidateCommit,
                runTimestamp: formatter.string(from: Date()),
                environment: ProcessInfo.processInfo.environment["REAL_RECOGNITION_ENVIRONMENT"]
                    ?? "local Apple environment",
                platformOS: ProcessInfo.processInfo.operatingSystemVersionString
            )
            let data = try RealTransactionRecognitionEvaluator.encodeAggregateReport(report)
            print(String(decoding: data, as: UTF8.self))
            if let reportURL {
                try data.write(to: reportURL, options: .atomic)
            }
            #else
            Issue.record("Private real corpus was configured, but Apple Vision is unavailable on this platform")
            #endif
        }
    }
}
