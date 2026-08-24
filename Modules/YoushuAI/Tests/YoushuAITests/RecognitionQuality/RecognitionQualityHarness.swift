import Foundation
import YoushuDomain

enum RecognitionQualityAdapters {
    static func observation(from draft: TransactionDraft) -> TransactionRecognitionObservation {
        TransactionRecognitionObservation(
            amount: draft.amount,
            currencyCode: draft.currencyCode,
            transactionType: draft.transactionType,
            date: draft.date,
            merchant: draft.merchant,
            category: draft.category
        )
    }

    static func observation(from candidates: [DebtCandidate]) -> DebtRecognitionObservation {
        DebtRecognitionObservation(
            candidates: candidates.map { candidate in
                DebtCandidateObservation(
                    lender: candidate.lender,
                    productName: candidate.productName,
                    debtType: candidate.debtType,
                    outstandingBalance: candidate.outstandingBalance,
                    currentDue: candidate.currentDue,
                    minimumDue: candidate.minimumDue,
                    installmentAmount: candidate.installmentAmount,
                    dueDate: candidate.dueDate,
                    interestRate: candidate.interestRate
                )
            }
        )
    }

    static func operationFailureCode(_ error: Error) -> String {
        if let recognized = error as? AIRecognitionError {
            switch recognized {
            case .networkTimeout: return "networkTimeout"
            case .requestFailed: return "requestFailed"
            case .invalidResponse: return "invalidResponse"
            case .imageUnreadable: return "imageUnreadable"
            case .amountMissing: return "amountMissing"
            case .ambiguousAmount: return "ambiguousAmount"
            case .dateMissing: return "dateMissing"
            }
        }
        return String(describing: type(of: error))
    }
}

enum RecognitionQualityHarness {
    static func evaluate(
        corpus: RecognitionQualityCorpusV1,
        corpusDirectory: URL,
        transactionExtractor: (any TransactionExtracting)?,
        debtScanner: (any DebtScanning)?,
        recognizerLabel: String,
        baselineEligible: Bool,
        baselineIneligibilityReasons: [String]
    ) async -> RecognitionQualityReportV1 {
        var effectiveEligible = baselineEligible
        var effectiveReasons = baselineIneligibilityReasons
        if let transactionExtractor,
           corpus.fixtures.contains(where: { $0.capability == .transactionScreenshot }),
           !transactionExtractor.transactionRecognizerMetadata.baselineEligible {
            effectiveEligible = false
            for reason in RecognitionQualityBaseline.nonPixelReasons where !effectiveReasons.contains(reason) {
                effectiveReasons.append(reason)
            }
        }
        var runs: [(String, RecognitionFixtureRun)] = []
        let fixtures = corpus.fixtures.sorted { $0.id < $1.id }
        for fixture in fixtures {
            let run = await runFixture(
                fixture,
                corpusDirectory: corpusDirectory,
                transactionExtractor: transactionExtractor,
                debtScanner: debtScanner
            )
            runs.append((fixture.id, run))
        }
        return RecognitionQualityReportBuilder.build(
            corpus: corpus,
            recognizerLabel: recognizerLabel,
            baselineEligible: effectiveEligible,
            baselineIneligibilityReasons: effectiveReasons,
            runs: runs
        )
    }

    private static func runFixture(
        _ fixture: RecognitionQualityFixtureV1,
        corpusDirectory: URL,
        transactionExtractor: (any TransactionExtracting)?,
        debtScanner: (any DebtScanning)?
    ) async -> RecognitionFixtureRun {
        do {
            switch fixture.capability {
            case .transactionScreenshot:
                guard let transactionExtractor else {
                    return .operationFailure(code: "missingTransactionExtractor")
                }
                let data = try RecognitionQualityCorpusLoader.loadAssetBytes(
                    corpusDirectory: corpusDirectory,
                    relativePath: fixture.assets[0]
                )
                switch await transactionExtractor.recognizeTransaction(fromImageData: data) {
                case .recognized(let draft):
                    return .observation(.transaction(RecognitionQualityAdapters.observation(from: draft)))
                case .unsupported:
                    return .operationFailure(code: "unsupported")
                case .unreadable:
                    return .operationFailure(code: "unreadable")
                case .failure(let error):
                    return .operationFailure(code: RecognitionQualityAdapters.operationFailureCode(error))
                }
            case .debtScreenshot:
                guard let debtScanner else {
                    return .operationFailure(code: "missingDebtScanner")
                }
                let documents: [BillDocument] = try fixture.assets.map { relative in
                    let data = try RecognitionQualityCorpusLoader.loadAssetBytes(
                        corpusDirectory: corpusDirectory,
                        relativePath: relative
                    )
                    return BillDocument(kind: .screenshot, data: data, fileName: relative)
                }
                let candidates = try await debtScanner.scanDebts(from: documents)
                return .observation(.debt(RecognitionQualityAdapters.observation(from: candidates)))
            }
        } catch {
            return .operationFailure(code: RecognitionQualityAdapters.operationFailureCode(error))
        }
    }
}
