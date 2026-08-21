import Foundation
import Testing
import YoushuData
import YoushuDomain
@testable import YoushuUI

@Suite("Privacy AI settings view model")
@MainActor
struct PrivacyAISettingsViewModelTests {
    private let userId = UUID(uuidString: "00000000-0000-0000-0000-000000000801")!
    private let sampleImage = Data("settings-retained-original".utf8)

    private func makeStandardEnv(
        mediaRoot: URL? = nil
    ) async throws -> (
        viewModel: PrivacyAISettingsViewModel,
        consentService: AIDataConsentService,
        dependencies: AppDependencies,
        container: RepositoryContainer
    ) {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        try await container.users.upsert(User(id: userId, displayName: "Settings"))
        let dependencies = AppDependencies(
            repositories: container,
            mediaBinaryRootURL: mediaRoot
        )
        dependencies.session.configureForPreview(userId: userId)
        let viewModel = dependencies.makePrivacyAISettingsViewModel()
        return (viewModel, dependencies.consentService, dependencies, container)
    }

    private func makeViewModel(
        consentService: AIDataConsentService,
        originalImageRetention: OriginalImageRetentionService,
        session: AppSession
    ) -> PrivacyAISettingsViewModel {
        PrivacyAISettingsViewModel(
            consentService: consentService,
            originalImageRetention: originalImageRetention,
            session: session
        )
    }

    @Test("A initial load deny-default leaves all toggles off")
    func initialLoadDenyDefault() async throws {
        let env = try await makeStandardEnv()
        await env.viewModel.load()

        #expect(env.viewModel.phase == .ready)
        #expect(!env.viewModel.allowScreenshotImageToAI)
        #expect(!env.viewModel.allowDebtScanImageToAI)
        #expect(!env.viewModel.allowFinancialContextToAI)
        #expect(!env.viewModel.retainOriginalImages)
    }

    @Test("B persisted mixed state loads exactly")
    func persistedMixedStateLoad() async throws {
        let env = try await makeStandardEnv()
        _ = try await env.consentService.acceptScreenshotPrivacy(userId: userId)
        _ = try await env.consentService.acceptAssistantPrivacy(userId: userId)

        await env.viewModel.load()

        #expect(env.viewModel.allowScreenshotImageToAI)
        #expect(!env.viewModel.allowDebtScanImageToAI)
        #expect(env.viewModel.allowFinancialContextToAI)
        #expect(!env.viewModel.retainOriginalImages)
    }

    @Test("C screenshot toggle persists without changing other fields")
    func screenshotToggleIsolation() async throws {
        let env = try await makeStandardEnv()
        await env.viewModel.load()

        await env.viewModel.setScreenshotAIEnabled(true)
        var consent = try await env.consentService.fetchOrDefault(userId: userId)
        #expect(consent.allowScreenshotImageToAI)
        #expect(!consent.allowDebtScanImageToAI)
        #expect(!consent.allowFinancialContextToAI)
        #expect(!consent.retainOriginalImages)
        #expect(env.viewModel.allowScreenshotImageToAI)

        await env.viewModel.setScreenshotAIEnabled(false)
        consent = try await env.consentService.fetchOrDefault(userId: userId)
        #expect(!consent.allowScreenshotImageToAI)
        #expect(!consent.allowDebtScanImageToAI)
        #expect(!consent.allowFinancialContextToAI)
        #expect(!consent.retainOriginalImages)
        #expect(!env.viewModel.allowScreenshotImageToAI)
    }

    @Test("D debt-scan toggle persists without changing other fields")
    func debtScanToggleIsolation() async throws {
        let env = try await makeStandardEnv()
        await env.viewModel.load()

        await env.viewModel.setDebtScanAIEnabled(true)
        var consent = try await env.consentService.fetchOrDefault(userId: userId)
        #expect(consent.allowDebtScanImageToAI)
        #expect(!consent.allowScreenshotImageToAI)
        #expect(!consent.allowFinancialContextToAI)
        #expect(!consent.retainOriginalImages)

        await env.viewModel.setDebtScanAIEnabled(false)
        consent = try await env.consentService.fetchOrDefault(userId: userId)
        #expect(!consent.allowDebtScanImageToAI)
        #expect(!consent.allowScreenshotImageToAI)
        #expect(!consent.allowFinancialContextToAI)
        #expect(!consent.retainOriginalImages)
    }

    @Test("E financial-context toggle persists without deleting historical insights")
    func financialContextToggleIsolation() async throws {
        let env = try await makeStandardEnv()
        let insight = FinancialInsight(
            userId: userId,
            type: .summary,
            title: "历史洞察",
            body: "保留",
            modelName: "test-model"
        )
        try await env.container.insights.upsert(insight)
        await env.viewModel.load()

        await env.viewModel.setFinancialContextAIEnabled(true)
        var consent = try await env.consentService.fetchOrDefault(userId: userId)
        #expect(consent.allowFinancialContextToAI)
        #expect(!consent.allowScreenshotImageToAI)
        #expect(!consent.allowDebtScanImageToAI)
        #expect(!consent.retainOriginalImages)

        await env.viewModel.setFinancialContextAIEnabled(false)
        consent = try await env.consentService.fetchOrDefault(userId: userId)
        #expect(!consent.allowFinancialContextToAI)
        let remaining = try await env.container.insights.fetchAll(userId: userId)
        #expect(remaining.contains(where: { $0.id == insight.id }))
    }

    @Test("F retention enable persists without granting AI consent or creating media")
    func retentionEnableDoesNotGrantAIOrCreateMedia() async throws {
        let env = try await makeStandardEnv()
        await env.viewModel.load()

        await env.viewModel.setRetainOriginalImagesEnabled(true)

        let consent = try await env.consentService.fetchOrDefault(userId: userId)
        #expect(consent.retainOriginalImages)
        #expect(!consent.allowScreenshotImageToAI)
        #expect(!consent.allowDebtScanImageToAI)
        #expect(!consent.allowFinancialContextToAI)
        #expect(env.viewModel.retainOriginalImages)
        #expect(try await env.container.mediaArtifacts.fetchAll(userId: userId).isEmpty)
    }

    @Test("G retention disable uses orchestration and deletes retained originals")
    func retentionDisableDeletesRetainedOriginals() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("privacy-settings-g-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let binaries = DirectoryMediaBinaryStore(rootURL: tempRoot)
        let env = try await makeStandardEnv(mediaRoot: tempRoot)
        await env.viewModel.load()
        await env.viewModel.setRetainOriginalImagesEnabled(true)

        let media = MediaLifecycleService(
            artifacts: env.container.mediaArtifacts,
            binaries: binaries
        )
        let artifact = try await media.register(
            data: sampleImage,
            userId: userId,
            kind: .screenshotTransaction,
            retainOriginal: true
        )
        #expect(try await binaries.load(imageId: artifact.id, userId: userId) == sampleImage)

        await env.viewModel.setRetainOriginalImagesEnabled(false)

        let consent = try await env.consentService.fetchOrDefault(userId: userId)
        #expect(!consent.retainOriginalImages)
        #expect(!env.viewModel.retainOriginalImages)
        #expect(env.viewModel.retentionCleanupWarning == nil)
        #expect(try await binaries.load(imageId: artifact.id, userId: userId) == nil)
        #expect(try await env.container.mediaArtifacts.fetch(id: artifact.id) == nil)
    }

    @Test("H cleanup failure keeps toggle off and retry succeeds")
    func retentionCleanupFailureThenRetry() async throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("privacy-settings-h-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let failingStore = FailingDeleteMediaBinaryStore(rootURL: tempRoot)
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        try await container.users.upsert(User(id: userId, displayName: "Settings"))
        let session = AppSession(users: container.users)
        session.configureForPreview(userId: userId)
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        let media = MediaLifecycleService(artifacts: container.mediaArtifacts, binaries: failingStore)
        let retention = OriginalImageRetentionService(consentService: consentService, media: media)
        let viewModel = makeViewModel(
            consentService: consentService,
            originalImageRetention: retention,
            session: session
        )

        _ = try await consentService.setRetainOriginalImages(true, userId: userId)
        let artifact = try await media.register(
            data: sampleImage,
            userId: userId,
            kind: .screenshotTransaction,
            retainOriginal: true
        )
        await failingStore.setFailDelete(imageId: artifact.id)
        await viewModel.load()
        #expect(viewModel.retainOriginalImages)

        await viewModel.setRetainOriginalImagesEnabled(false)

        let consent = try await consentService.fetchOrDefault(userId: userId)
        #expect(!consent.retainOriginalImages)
        #expect(!viewModel.retainOriginalImages)
        #expect(viewModel.retentionCleanupWarning != nil)
        #expect(viewModel.showsRetentionCleanupRetry)
        #expect(!(viewModel.retentionCleanupWarning ?? "").contains(artifact.id))

        await failingStore.setFailDelete(imageId: nil)
        await viewModel.retryRetentionCleanup()

        #expect(viewModel.retentionCleanupWarning == nil)
        #expect(!viewModel.retainOriginalImages)
        #expect(!viewModel.showsRetentionCleanupRetry)
        #expect(try await failingStore.load(imageId: artifact.id, userId: userId) == nil)
    }

    @Test("I mutation failure reloads persisted truth")
    func mutationFailurePreservesPersistedTruth() async throws {
        let repository = ControllableConsentRepository()
        let consentService = AIDataConsentService(consents: repository)
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        try await container.users.upsert(User(id: userId, displayName: "Settings"))
        let session = AppSession(users: container.users)
        session.configureForPreview(userId: userId)
        let media = MediaLifecycleService(
            artifacts: container.mediaArtifacts,
            binaries: NoPersistMediaBinaryStore()
        )
        let viewModel = makeViewModel(
            consentService: consentService,
            originalImageRetention: OriginalImageRetentionService(
                consentService: consentService,
                media: media
            ),
            session: session
        )
        await viewModel.load()
        repository.failUpsert = true

        await viewModel.setScreenshotAIEnabled(true)
        #expect(!viewModel.allowScreenshotImageToAI)
        #expect(viewModel.actionError != nil)
        #expect(!(viewModel.actionError ?? "").contains(userId.uuidString))

        await viewModel.setDebtScanAIEnabled(true)
        #expect(!viewModel.allowDebtScanImageToAI)
        #expect(viewModel.actionError != nil)

        await viewModel.setFinancialContextAIEnabled(true)
        #expect(!viewModel.allowFinancialContextToAI)
        #expect(viewModel.actionError != nil)

        await viewModel.setRetainOriginalImagesEnabled(true)
        #expect(!viewModel.retainOriginalImages)
        #expect(viewModel.actionError != nil)
    }

    @Test("J screenshot flow grant is reflected in settings")
    func screenshotFlowGrantReflectedInSettings() async throws {
        let env = try await makeStandardEnv()
        try await env.dependencies.screenshotBookkeeping.acceptPrivacy(userId: userId)

        await env.viewModel.load()
        #expect(env.viewModel.allowScreenshotImageToAI)
        #expect(!env.viewModel.allowDebtScanImageToAI)
        #expect(!env.viewModel.allowFinancialContextToAI)
        #expect(!env.viewModel.retainOriginalImages)
    }

    @Test("K Account navigates to unified privacy settings")
    func accountNavigatesToUnifiedPrivacySettings() async throws {
        let env = try await makeStandardEnv()
        let account = env.dependencies.makeAccountViewModel()
        let privacy = env.dependencies.makePrivacyAISettingsViewModel()

        #expect(!account.isPresentingPrivacyAISettings)
        account.openPrivacyAISettings()
        #expect(account.isPresentingPrivacyAISettings)

        await privacy.load()
        #expect(privacy.phase == .ready)
        #expect(!privacy.allowFinancialContextToAI)
    }
}

private final class ControllableConsentRepository: AIDataConsentRepository, @unchecked Sendable {
    private var storage: [UUID: AIDataConsent] = [:]
    private let lock = NSLock()
    private var failUpsertEnabled = false

    var failUpsert: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return failUpsertEnabled
        }
        set {
            lock.lock()
            failUpsertEnabled = newValue
            lock.unlock()
        }
    }

    func upsert(_ consent: AIDataConsent) async throws {
        if failUpsert {
            throw PrivacyError.operationFailed
        }
        lock.lock()
        storage[consent.userId] = consent
        lock.unlock()
    }

    func fetch(userId: UUID) async throws -> AIDataConsent? {
        lock.lock()
        defer { lock.unlock() }
        return storage[userId]
    }

    func delete(userId: UUID) async throws {
        lock.lock()
        storage.removeValue(forKey: userId)
        lock.unlock()
    }
}

private actor FailingDeleteMediaBinaryStore: MediaBinaryStoring {
    private let inner: DirectoryMediaBinaryStore
    private var failDeleteImageIds: Set<String> = []

    init(rootURL: URL) {
        inner = DirectoryMediaBinaryStore(rootURL: rootURL)
    }

    func setFailDelete(imageId: String?) {
        failDeleteImageIds.removeAll()
        if let imageId {
            failDeleteImageIds.insert(imageId)
        }
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
