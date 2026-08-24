#if canImport(UIKit) && canImport(Vision)
import Testing
import UIKit
import YoushuAI
import YoushuDomain

@Suite("Apple Vision Transaction recognizer")
struct AppleVisionTransactionRecognizerTests {
    @Test("Vision adapter reads synthetic image pixels")
    @MainActor
    func readsSyntheticPixels() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1_200, height: 360))
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1_200, height: 360))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 72, weight: .bold),
                .foregroundColor: UIColor.black,
            ]
            NSString(string: "FINSIGHT OCR TEST\n12345").draw(
                in: CGRect(x: 60, y: 60, width: 1_080, height: 240),
                withAttributes: attributes
            )
        }
        let data = try #require(image.pngData())

        let spans = try await AppleVisionTextRecognizer().recognizeText(in: data)
        let text = spans.map(\.text).joined(separator: " ").uppercased()
        #expect(text.contains("FINSIGHT"))
        #expect(text.contains("12345"))
    }

    @Test("invalid image bytes map to unreadable")
    func invalidImageIsUnreadable() async {
        let outcome = await AppleVisionTransactionRecognizer()
            .recognizeTransaction(fromImageData: Data("not-an-image".utf8))
        #expect(outcome == .unreadable)
    }

    @Test("real Vision recognizer metadata is baseline-capable but not production wiring")
    func metadata() {
        let metadata = AppleVisionTransactionRecognizer().transactionRecognizerMetadata
        #expect(metadata.providerID == "apple-vision-transaction-v1")
        #expect(metadata.engineVersion == "vision-accurate-zh-Hans-en-US-v1")
        #expect(metadata.inspectsImagePixels)
        #expect(metadata.baselineEligible)
    }
}
#endif
