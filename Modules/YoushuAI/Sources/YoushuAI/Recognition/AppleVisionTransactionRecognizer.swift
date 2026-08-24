import Foundation
import YoushuDomain

#if canImport(Vision)
import ImageIO
import Vision

/// Apple-only pixel OCR adapter. Recognized text remains transient and is never logged or persisted here.
public struct AppleVisionTextRecognizer: Sendable {
    public let recognitionLanguages: [String]
    public let usesLanguageCorrection: Bool

    public init(
        recognitionLanguages: [String] = ["zh-Hans", "en-US"],
        usesLanguageCorrection: Bool = true
    ) {
        self.recognitionLanguages = recognitionLanguages
        self.usesLanguageCorrection = usesLanguageCorrection
    }

    public func recognizeText(in imageData: Data) async throws -> [RecognizedTextSpan] {
        guard !imageData.isEmpty else { throw AIRecognitionError.imageUnreadable }
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              CGImageSourceGetCount(source) > 0 else {
            throw AIRecognitionError.imageUnreadable
        }
        try Task.checkCancellation()

        let languages = recognitionLanguages
        let correction = usesLanguageCorrection
        return try await Task.detached(priority: nil) {
            try Task.checkCancellation()
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = languages
            request.usesLanguageCorrection = correction

            do {
                try VNImageRequestHandler(data: imageData, options: [:]).perform([request])
            } catch {
                if error is CancellationError { throw error }
                throw AIRecognitionError.requestFailed("本地图像文字识别失败")
            }
            try Task.checkCancellation()

            return (request.results ?? []).compactMap { observation in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return nil }
                return RecognizedTextSpan(text: text, confidence: Double(candidate.confidence))
            }
        }.value
    }
}

/// On-device composition of real pixel OCR plus deterministic Transaction parsing.
public struct AppleVisionTransactionRecognizer: TransactionExtracting {
    public let name = "apple-vision-transaction-v1"
    public let transactionRecognizerMetadata = TransactionRecognizerMetadata(
        providerID: "apple-vision-transaction-v1",
        engineVersion: "vision-accurate-zh-Hans-en-US-v1",
        inspectsImagePixels: true
    )

    private let textRecognizer: AppleVisionTextRecognizer
    private let parser: any TransactionRecognizedTextParsing

    public init(
        textRecognizer: AppleVisionTextRecognizer = AppleVisionTextRecognizer(),
        parser: any TransactionRecognizedTextParsing = DeterministicTransactionReceiptParser()
    ) {
        self.textRecognizer = textRecognizer
        self.parser = parser
    }

    public func recognizeTransaction(fromImageData data: Data) async -> TransactionRecognitionOutcome {
        do {
            let spans = try await textRecognizer.recognizeText(in: data)
            guard !spans.isEmpty else { return .unreadable }
            try Task.checkCancellation()
            return parser.parseTransaction(from: spans)
        } catch is CancellationError {
            return .failure(.requestFailed("识别已取消"))
        } catch AIRecognitionError.imageUnreadable {
            return .unreadable
        } catch let error as AIRecognitionError {
            return .failure(error)
        } catch {
            return .failure(.requestFailed("本地图像文字识别失败"))
        }
    }

    public func extractTransactionDraft(fromImageData data: Data) async throws -> TransactionDraft {
        switch await recognizeTransaction(fromImageData: data) {
        case .recognized(let draft): return draft
        case .unsupported: throw AIRecognitionError.invalidResponse("暂不支持此类交易截图")
        case .unreadable: throw AIRecognitionError.imageUnreadable
        case .failure(let error): throw error
        }
    }
}
#endif
