#if canImport(UIKit) && canImport(Vision)
import Foundation
import Testing
import UIKit
import YoushuAI
import YoushuData
import YoushuDomain
@testable import YoushuUI

@Suite("Production Transaction recognition composition")
@MainActor
struct ProductionTransactionRecognitionCompositionTests {
    @Test("production switches only Transaction recognition to Apple Vision")
    func switchesOnlyTransactionPort() {
        let dependencies = AppDependencies(
            repositories: RepositoryContainer(store: YoushuStore())
        )

        #expect(dependencies.transactionRecognizerMetadata.providerID == "apple-vision-transaction-v1")
        #expect(dependencies.transactionRecognizerMetadata.engineVersion == "vision-accurate-zh-Hans-en-US-v1")
        #expect(dependencies.transactionRecognizerMetadata.inspectsImagePixels)
        #expect(dependencies.transactionRecognizerMetadata.baselineEligible)
        #expect(dependencies.debtScannerProviderName == "mock")
        #expect(dependencies.financialAssistingProviderName == "mock")
    }

    @Test("canonical consent gate blocks production recognizer before pixel processing")
    func canonicalConsentGate() async throws {
        let container = RepositoryContainer(store: YoushuStore())
        let dependencies = AppDependencies(repositories: container)
        let userId = UUID()
        try await container.users.upsert(User(id: userId, displayName: "Production Consent Test"))
        let invalidImage = Data("not-an-image".utf8)
        let identity = TransactionScreenshotImportIdentity.from(imageData: invalidImage)

        await #expect(throws: PrivacyError.consentRequired("记账截图")) {
            try await dependencies.screenshotBookkeeping.recognize(
                imageData: invalidImage,
                userId: userId,
                importIdentity: identity
            )
        }
        #expect(try await container.aiRecognitionRecords.fetchAll(userId: userId).isEmpty)
        #expect(try await container.mediaArtifacts.fetchAll(userId: userId).isEmpty)
        #expect(try await container.transactions.fetchAll(userId: userId).isEmpty)

        _ = try await dependencies.consentService.acceptScreenshotPrivacy(userId: userId)
        await #expect(throws: AIRecognitionError.imageUnreadable) {
            try await dependencies.screenshotBookkeeping.recognize(
                imageData: invalidImage,
                userId: userId,
                importIdentity: identity
            )
        }
    }

    @Test("production dependency reads pixels and enters editable review without auto-confirm")
    func productionPixelPathEntersReview() async throws {
        let container = RepositoryContainer(store: YoushuStore())
        let dependencies = AppDependencies(repositories: container)
        let userId = UUID()
        let account = Account(userId: userId, name: "现金", type: .cash)
        try await container.users.upsert(User(id: userId, displayName: "Production Vision Test"))
        try await container.accounts.upsert(account)
        dependencies.session.configureForPreview(userId: userId)

        let viewModel = dependencies.makeScreenshotBookkeepingViewModel()
        await viewModel.loadAccounts()
        await viewModel.acceptPrivacy()
        #expect(viewModel.privacyAccepted)

        viewModel.setImageData(try syntheticAlipayImageData())
        viewModel.startRecognition()
        for _ in 0..<240 {
            if case .confirm = viewModel.step { break }
            if case .failed = viewModel.step { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }

        #expect(viewModel.step == .confirm)
        #expect(viewModel.recognition?.aiDraft.amount == Decimal(string: "12.34"))
        #expect(viewModel.recognition?.aiDraft.transactionType == .expense)
        #expect(viewModel.amountText == "12.34")
        #expect(try await container.transactions.fetchAll(userId: userId).isEmpty)
        #expect(try await container.confirmedImportProvenances.fetchAll(userId: userId).isEmpty)

        let records = try await container.aiRecognitionRecords.fetchAll(userId: userId)
        #expect(records.count == 1)
        #expect(records[0].status == .recognized)
        #expect(records[0].modelName == "apple-vision-transaction-v1")
        #expect(records[0].summaryLabel == "截图记账识别")
        #expect(!records[0].summaryLabel.contains("12.34"))
        #expect(!records[0].summaryLabel.contains("FINSIGHT"))
    }

    private func syntheticAlipayImageData() throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1_600, height: 720))
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1_600, height: 720))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 76, weight: .bold),
                .foregroundColor: UIColor.black,
            ]
            let lines = ["支付宝", "支付成功", "交易金额 ¥12.34", "商家 FINSIGHT CAFE"]
            for (index, line) in lines.enumerated() {
                NSString(string: line).draw(
                    at: CGPoint(x: 80, y: 70 + (index * 145)),
                    withAttributes: attributes
                )
            }
        }
        return try #require(image.pngData())
    }
}
#endif
