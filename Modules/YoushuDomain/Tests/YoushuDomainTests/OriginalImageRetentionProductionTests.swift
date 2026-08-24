import Foundation
import Testing
import YoushuAI
import YoushuData
import YoushuDomain
import YoushuFoundation

@Suite("Original image retention production")
struct OriginalImageRetentionProductionTests {
    private let sampleImage = Data("screenshot-original-bytes".utf8)
    private let billImage = Data("debt-bill-original-bytes".utf8)

    private func makeEnv(
        binaryStore: any MediaBinaryStoring,
        directoryStore: DirectoryMediaBinaryStore? = nil,
        tempRoot: URL
    ) async throws -> (
        container: RepositoryContainer,
        userId: UUID,
        account: Account,
        consentService: AIDataConsentService,
        media: MediaLifecycleService,
        screenshot: ScreenshotBookkeepingService,
        debtScanner: DebtScannerService,
        retention: OriginalImageRetentionService,
        binaries: DirectoryMediaBinaryStore?
    ) {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await container.users.upsert(User(id: userId, displayName: "Retention"))
        let account = Account(
            userId: userId,
            name: "现金",
            type: .cash,
            openingBalance: Money(amount: 1_000, currencyCode: "CNY")
        )
        try await container.accounts.upsert(account)
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        let media = MediaLifecycleService(
            artifacts: container.mediaArtifacts,
            binaries: binaryStore
        )
        let txService = TransactionService(
            accounts: container.accounts,
            transactions: container.transactions
        )
        let debtService = DebtService(
            debts: container.debts,
            events: container.debtEvents,
            accounts: container.accounts,
            transactions: container.transactions
        )
        let screenshot = ScreenshotBookkeepingService(
            extractor: MockAIProvider(),
            transactionService: txService,
            accounts: container.accounts,
            consentService: consentService,
            media: media,
            recognitionRecords: container.aiRecognitionRecords
        )
        let debtScanner = DebtScannerService(
            scanner: MockAIProvider(),
            debtService: debtService,
            consentService: consentService,
            media: media,
            recognitionRecords: container.aiRecognitionRecords
        )
        let retention = OriginalImageRetentionService(
            consentService: consentService,
            media: media
        )
        return (
            container,
            userId,
            account,
            consentService,
            media,
            screenshot,
            debtScanner,
            retention,
            directoryStore
        )
    }

    private func makeDirectoryEnv() async throws -> (
        env: (
            container: RepositoryContainer,
            userId: UUID,
            account: Account,
            consentService: AIDataConsentService,
            media: MediaLifecycleService,
            screenshot: ScreenshotBookkeepingService,
            debtScanner: DebtScannerService,
            retention: OriginalImageRetentionService,
            binaries: DirectoryMediaBinaryStore?
        ),
        tempRoot: URL
    ) {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("youshu-retention-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let binaries = DirectoryMediaBinaryStore(rootURL: tempRoot)
        let env = try await makeEnv(binaryStore: binaries, directoryStore: binaries, tempRoot: tempRoot)
        return (env, tempRoot)
    }

    private func recognizeScreenshot(
        _ service: ScreenshotBookkeepingService,
        imageData: Data,
        userId: UUID
    ) async throws -> PendingScreenshotRecognition {
        let identity = TransactionScreenshotImportIdentity.from(imageData: imageData)
        return try await service.recognize(imageData: imageData, userId: userId, importIdentity: identity)
    }

    private func acceptScreenshot(
        _ service: ScreenshotBookkeepingService,
        imageData: Data,
        userId: UUID
    ) async throws -> ScreenshotRecognitionResult {
        let pending = try await recognizeScreenshot(service, imageData: imageData, userId: userId)
        return try await service.acceptRecognition(pending, userId: userId)
    }

    private func scanDebt(
        _ service: DebtScannerService,
        documents: [BillDocument],
        userId: UUID
    ) async throws -> PendingDebtScanResult {
        let identity = DebtScanImportIdentity.from(documents: documents)
        return try await service.scan(documents: documents, userId: userId, importIdentity: identity)
    }

    private func acceptDebtScan(
        _ service: DebtScannerService,
        documents: [BillDocument],
        userId: UUID
    ) async throws -> DebtScanResult {
        let pending = try await scanDebt(service, documents: documents, userId: userId)
        return try await service.acceptScan(pending, userId: userId)
    }

    @Test("retain false screenshot leaves no persistent binary after confirm")
    func screenshotRetainFalse() async throws {
        let (env, tempRoot) = try await makeDirectoryEnv()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        _ = try await env.consentService.acceptScreenshotPrivacy(userId: env.userId)
        #expect(try await env.consentService.fetchOrDefault(userId: env.userId).retainOriginalImages == false)

        let result = try await acceptScreenshot(env.screenshot, imageData: sampleImage, userId: env.userId)
        guard let imageId = result.sourceImageId else {
            Issue.record("Expected source image id")
            return
        }
        _ = try await env.screenshot.confirm(
            ConfirmScreenshotTransactionInput(
                amount: 36.50,
                currencyCode: "CNY",
                date: Date(),
                merchant: "地铁",
                category: "交通",
                accountId: env.account.id,
                formType: .expense,
                recognitionConfidence: result.aiDraft.confidence,
                sourceImageId: imageId,
                confirmationToken: UUID()
            ),
            userId: env.userId
        )

        #expect(try await env.binaries?.load(imageId: imageId, userId: env.userId) == nil)
        #expect(try await env.container.mediaArtifacts.fetch(id: imageId) == nil)
    }

    @Test("retain true screenshot keeps binary after confirm")
    func screenshotRetainTrue() async throws {
        let (env, tempRoot) = try await makeDirectoryEnv()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        _ = try await env.consentService.acceptScreenshotPrivacy(userId: env.userId)
        _ = try await env.consentService.setRetainOriginalImages(true, userId: env.userId)

        let result = try await acceptScreenshot(env.screenshot, imageData: sampleImage, userId: env.userId)
        guard let imageId = result.sourceImageId else {
            Issue.record("Expected source image id")
            return
        }
        _ = try await env.screenshot.confirm(
            ConfirmScreenshotTransactionInput(
                amount: 36.50,
                currencyCode: "CNY",
                date: Date(),
                merchant: "地铁",
                category: "交通",
                accountId: env.account.id,
                formType: .expense,
                recognitionConfidence: result.aiDraft.confidence,
                sourceImageId: imageId,
                confirmationToken: UUID()
            ),
            userId: env.userId
        )

        #expect(try await env.binaries?.load(imageId: imageId, userId: env.userId) == sampleImage)
        let artifact = try await env.container.mediaArtifacts.fetch(id: imageId)
        #expect(artifact?.retention == .userRetained)
    }

    @Test("retain false debt scan leaves no persistent binary after confirm")
    func debtScanRetainFalse() async throws {
        let (env, tempRoot) = try await makeDirectoryEnv()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        _ = try await env.consentService.acceptDebtScanPrivacy(userId: env.userId)
        let document = BillDocument(kind: .screenshot, data: billImage, fileName: "bill.png")
        let scan = try await acceptDebtScan(env.debtScanner, documents: [document], userId: env.userId)
        #expect(!scan.candidates.isEmpty)

        let imageId = MediaLifecyclePolicy.makeImageId(for: billImage)
        let outcome = await env.debtScanner.confirm(candidates: [scan.candidates[0]], userId: env.userId)
        #expect(outcome.isFullySuccessful)

        #expect(try await env.binaries?.load(imageId: imageId, userId: env.userId) == nil)
        #expect(try await env.container.mediaArtifacts.fetch(id: imageId) == nil)
    }

    @Test("retain true debt scan keeps binaries after confirm")
    func debtScanRetainTrue() async throws {
        let (env, tempRoot) = try await makeDirectoryEnv()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        _ = try await env.consentService.acceptDebtScanPrivacy(userId: env.userId)
        _ = try await env.consentService.setRetainOriginalImages(true, userId: env.userId)

        let document = BillDocument(kind: .screenshot, data: billImage, fileName: "bill.png")
        let scan = try await acceptDebtScan(env.debtScanner, documents: [document], userId: env.userId)
        let imageId = MediaLifecyclePolicy.makeImageId(for: billImage)
        let outcome = await env.debtScanner.confirm(candidates: [scan.candidates[0]], userId: env.userId)
        #expect(outcome.isFullySuccessful)

        #expect(try await env.binaries?.load(imageId: imageId, userId: env.userId) == billImage)
        let artifact = try await env.container.mediaArtifacts.fetch(id: imageId)
        #expect(artifact?.retention == .userRetained)
    }

    @Test("disable retention persists false and purges retained originals")
    func disableRetentionCleanup() async throws {
        let (env, tempRoot) = try await makeDirectoryEnv()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        _ = try await env.consentService.acceptScreenshotPrivacy(userId: env.userId)
        _ = try await env.consentService.acceptAssistantPrivacy(userId: env.userId)
        _ = try await env.consentService.setRetainOriginalImages(true, userId: env.userId)

        let result = try await acceptScreenshot(env.screenshot, imageData: sampleImage, userId: env.userId)
        guard let imageId = result.sourceImageId else { return }

        let deleted = try await env.retention.disableRetention(userId: env.userId)
        #expect(deleted == 1)

        let consent = try await env.consentService.fetchOrDefault(userId: env.userId)
        #expect(!consent.retainOriginalImages)
        #expect(consent.allowScreenshotImageToAI)
        #expect(consent.allowFinancialContextToAI)
        #expect(try await env.binaries?.load(imageId: imageId, userId: env.userId) == nil)
        #expect(try await env.container.mediaArtifacts.fetch(id: imageId) == nil)
    }

    @Test("disable retention keeps preference false when cleanup fails")
    func disableRetentionCleanupFailure() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("youshu-retention-fail-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let failingStore = FailingDeleteMediaBinaryStore(rootURL: tempRoot)
        let env = try await makeEnv(binaryStore: failingStore, tempRoot: tempRoot)

        _ = try await env.consentService.acceptScreenshotPrivacy(userId: env.userId)
        _ = try await env.consentService.setRetainOriginalImages(true, userId: env.userId)
        let result = try await acceptScreenshot(env.screenshot, imageData: sampleImage, userId: env.userId)
        guard let imageId = result.sourceImageId else { return }
        await failingStore.setFailDelete(imageId: imageId)

        do {
            _ = try await env.retention.disableRetention(userId: env.userId)
            Issue.record("Expected retention cleanup failure")
        } catch let error as PrivacyError {
            guard case .retentionCleanupFailed(let deletedCount, let failedIds) = error else {
                Issue.record("Unexpected error \(error)")
                return
            }
            #expect(deletedCount == 0)
            #expect(failedIds == [imageId])
        }

        let consent = try await env.consentService.fetchOrDefault(userId: env.userId)
        #expect(!consent.retainOriginalImages)
    }

    @Test("disable retention for one user does not delete another user's retained originals")
    func crossUserIsolation() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("youshu-retention-users-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let binaries = DirectoryMediaBinaryStore(rootURL: tempRoot)

        let envA = try await makeEnv(binaryStore: binaries, directoryStore: binaries, tempRoot: tempRoot)
        let userB = UUID()
        try await envA.container.users.upsert(User(id: userB, displayName: "B"))
        let accountB = Account(userId: userB, name: "B", type: .cash)
        try await envA.container.accounts.upsert(accountB)

        _ = try await envA.consentService.setRetainOriginalImages(true, userId: envA.userId)
        _ = try await envA.consentService.acceptScreenshotPrivacy(userId: envA.userId)
        let resultA = try await acceptScreenshot(envA.screenshot, imageData: sampleImage, userId: envA.userId)
        guard let imageIdA = resultA.sourceImageId else { return }

        let consentB = AIDataConsentService(consents: envA.container.aiDataConsents)
        _ = try await consentB.setRetainOriginalImages(true, userId: userB)
        _ = try await consentB.acceptScreenshotPrivacy(userId: userB)
        let screenshotB = ScreenshotBookkeepingService(
            extractor: MockAIProvider(),
            transactionService: TransactionService(
                accounts: envA.container.accounts,
                transactions: envA.container.transactions
            ),
            accounts: envA.container.accounts,
            consentService: consentB,
            media: envA.media
        )
        let imageB = Data("user-b-image".utf8)
        let resultB = try await acceptScreenshot(screenshotB, imageData: imageB, userId: userB)
        guard let imageIdB = resultB.sourceImageId else { return }

        _ = try await envA.retention.disableRetention(userId: envA.userId)

        #expect(try await binaries.load(imageId: imageIdA, userId: envA.userId) == nil)
        #expect(try await binaries.load(imageId: imageIdB, userId: userB) == imageB)
    }

    @Test("wipeAllUserData removes directory-backed retained binaries")
    func wipeAllRemovesRetainedBinaries() async throws {
        let (env, tempRoot) = try await makeDirectoryEnv()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        _ = try await env.consentService.acceptScreenshotPrivacy(userId: env.userId)
        _ = try await env.consentService.setRetainOriginalImages(true, userId: env.userId)
        let result = try await acceptScreenshot(env.screenshot, imageData: sampleImage, userId: env.userId)
        guard let imageId = result.sourceImageId else { return }
        #expect(try await env.binaries?.load(imageId: imageId, userId: env.userId) == sampleImage)

        let privacy = PrivacyDataService(
            users: env.container.users,
            transactions: env.container.transactions,
            debts: env.container.debts,
            debtEvents: env.container.debtEvents,
            accounts: env.container.accounts,
            recognitionRecords: env.container.aiRecognitionRecords,
            consents: env.container.aiDataConsents,
            media: env.media
        )
        try await privacy.wipeAllUserData(userId: env.userId)

        #expect(try await env.binaries?.load(imageId: imageId, userId: env.userId) == nil)
        #expect(try await env.container.mediaArtifacts.fetchAll(userId: env.userId).isEmpty)
        let userDir = tempRoot.appendingPathComponent(env.userId.uuidString, isDirectory: true)
        #expect(!FileManager.default.fileExists(atPath: userDir.path))
    }

    @Test("deny default retains no binary on screenshot flow")
    func denyDefaultNoBinary() async throws {
        let (env, tempRoot) = try await makeDirectoryEnv()
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        _ = try await env.consentService.acceptScreenshotPrivacy(userId: env.userId)
        #expect(try await env.consentService.fetchOrDefault(userId: env.userId).retainOriginalImages == false)

        let result = try await acceptScreenshot(env.screenshot, imageData: sampleImage, userId: env.userId)
        guard let imageId = result.sourceImageId else { return }
        #expect(try await env.binaries?.load(imageId: imageId, userId: env.userId) == nil)
    }
}

// MARK: - Test doubles

private actor FailingDeleteMediaBinaryStore: MediaBinaryStoring {
    private let inner: DirectoryMediaBinaryStore
    private var failDeleteImageIds: Set<String> = []

    init(rootURL: URL) {
        self.inner = DirectoryMediaBinaryStore(rootURL: rootURL)
    }

    func setFailDelete(imageId: String) {
        failDeleteImageIds.insert(imageId)
    }

    func save(imageId: String, userId: UUID, data: Data) async throws -> String? {
        try await inner.save(imageId: imageId, userId: userId, data: data)
    }

    func load(imageId: String, userId: UUID) async throws -> Data? {
        try await inner.load(imageId: imageId, userId: userId)
    }

    func delete(imageId: String, userId: UUID) async throws {
        if failDeleteImageIds.contains(imageId) {
            throw NSError(domain: "test.media", code: 1)
        }
        try await inner.delete(imageId: imageId, userId: userId)
    }

    func deleteAll(userId: UUID) async throws {
        try await inner.deleteAll(userId: userId)
    }
}
