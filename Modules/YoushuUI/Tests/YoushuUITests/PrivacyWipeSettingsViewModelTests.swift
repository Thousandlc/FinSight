import Foundation
import Testing
import YoushuData
import YoushuDomain
import YoushuFoundation
@testable import YoushuUI

@Suite("Privacy wipe settings and application reset")
@MainActor
struct PrivacyWipeSettingsViewModelTests {
    private let userA = UUID(uuidString: "00000000-0000-0000-0000-000000000c01")!
    private let oldAccountId = UUID(uuidString: "00000000-0000-0000-0000-000000000c11")!
    private let sampleImage = Data("wipe-ui-retained".utf8)

    @Test("K cancel requires confirmation and does not wipe")
    func destructiveConfirmationCancel() async throws {
        let env = try await makeManualEnv()
        defer { try? FileManager.default.removeItem(at: env.tempRoot) }
        await env.viewModel.load()

        env.viewModel.requestDeleteAllLocalData()
        #expect(env.viewModel.wipePhase == .confirming)

        env.viewModel.cancelDeleteAllLocalData()
        #expect(env.viewModel.wipePhase == .idle)
        #expect(await env.users.deleteCallCount() == 0)
        #expect(try await env.container.users.fetch(id: userA) != nil)
    }

    @Test("K confirm performs exactly one wipe")
    func destructiveConfirmationInvokesWipeOnce() async throws {
        let env = try await makeManualEnv()
        defer { try? FileManager.default.removeItem(at: env.tempRoot) }
        await env.viewModel.load()

        env.viewModel.requestDeleteAllLocalData()
        await env.viewModel.confirmDeleteAllLocalData()

        #expect(await env.users.deleteCallCount() == 1)
        #expect(try await env.container.users.fetch(id: userA) == nil)
        #expect(env.viewModel.wipePhase == .idle)
        #expect(env.viewModel.wipeStatusMessage == PrivacyAIDisclosureCopy.wipeSuccessMessage)
    }

    @Test("L second confirm while deleting does not start another wipe")
    func doubleSubmitProtection() async throws {
        let env = try await makeManualEnv()
        defer { try? FileManager.default.removeItem(at: env.tempRoot) }
        await env.viewModel.load()
        await env.users.setHoldDelete(true)

        env.viewModel.requestDeleteAllLocalData()
        let first = Task { await env.viewModel.confirmDeleteAllLocalData() }
        for _ in 0..<40 {
            if env.viewModel.isWipeBusy { break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        #expect(env.viewModel.isWipeBusy)

        await env.viewModel.confirmDeleteAllLocalData()
        env.viewModel.requestDeleteAllLocalData()
        await env.users.releaseHold()
        await first.value

        #expect(await env.users.deleteCallCount() == 1)
    }

    @Test("F store deletion failure does not show success or replace session")
    func persistentStoreFailureKeepsSession() async throws {
        let env = try await makeManualEnv()
        defer { try? FileManager.default.removeItem(at: env.tempRoot) }
        await env.viewModel.load()
        await env.users.setFailDelete(true)

        env.viewModel.requestDeleteAllLocalData()
        await env.viewModel.confirmDeleteAllLocalData()

        #expect(env.viewModel.wipePhase == .failed(PrivacyError.persistentDeletionIncomplete.userMessage))
        #expect(env.viewModel.wipeStatusMessage == nil)
        #expect(env.session.currentUserId == userA)
        #expect(try await env.container.users.fetch(id: userA) != nil)
        assertNoSensitiveLeak(in: env.viewModel.wipeFailureMessage ?? "")
    }

    @Test("G media cleanup failure resets session and surfaces a privacy-safe warning")
    func mediaCleanupPartialFailureResetsSession() async throws {
        let env = try await makeAppCompositionEnv()
        defer { try? FileManager.default.removeItem(at: env.tempRoot) }

        await env.binaries.setFailDeleteAll(true)
        let privacy = PrivacyDataService(
            users: env.container.users,
            transactions: env.container.transactions,
            debts: env.container.debts,
            debtEvents: env.container.debtEvents,
            accounts: env.container.accounts,
            recognitionRecords: env.container.aiRecognitionRecords,
            consents: env.container.aiDataConsents,
            media: MediaLifecycleService(
                artifacts: env.container.mediaArtifacts,
                binaries: env.binaries
            )
        )
        let viewModel = PrivacyAISettingsViewModel(
            consentService: env.dependencies.consentService,
            originalImageRetention: env.dependencies.originalImageRetention,
            privacyData: privacy,
            session: env.dependencies.session,
            applicationWipeReset: {
                try await ApplicationPrivacyWipeReset.perform(
                    dependencies: env.dependencies,
                    viewModels: env.viewModels
                )
            }
        )
        await viewModel.load()
        viewModel.requestDeleteAllLocalData()
        await viewModel.confirmDeleteAllLocalData()

        #expect(try await env.container.users.fetch(id: userA) == nil)
        #expect(env.dependencies.session.currentUserId != userA)
        #expect(env.dependencies.session.currentUserId != nil)
        #expect(viewModel.showsWipeMediaCleanupRetry)
        if case .mediaCleanupIncomplete(let message) = viewModel.wipePhase {
            assertNoSensitiveLeak(in: message)
            #expect(!message.contains(userA.uuidString))
        } else {
            Issue.record("Expected media cleanup incomplete")
        }
        #expect(viewModel.wipeStatusMessage == nil)
    }

    @Test("H I J M successful wipe bootstraps a new session and clears stale presentation")
    func sessionBootstrapAndTransientReset() async throws {
        let env = try await makeAppCompositionEnv()
        defer { try? FileManager.default.removeItem(at: env.tempRoot) }

        env.viewModels.privacyAISettings.applicationWipeReset = {
            try await ApplicationPrivacyWipeReset.perform(
                dependencies: env.dependencies,
                viewModels: env.viewModels
            )
        }
        env.viewModels.ai.questionText = "旧问题"
        env.viewModels.account.isPresentingPrivacyAISettings = true
        env.viewModels.debt.selectedDebtId = UUID()
        await env.viewModels.home.load()
        await env.viewModels.transaction.load()
        await env.viewModels.debt.load()
        await env.viewModels.account.load()
        await env.viewModels.privacyAISettings.load()

        #expect(transactionMerchants(in: env.viewModels.transaction).contains("旧商家A"))
        #expect(debtLenders(in: env.viewModels.debt).contains("银行-A"))
        #expect(accountNames(in: env.viewModels.account).contains("现金-A"))
        #expect(env.viewModels.privacyAISettings.allowFinancialContextToAI)

        env.viewModels.privacyAISettings.requestDeleteAllLocalData()
        await env.viewModels.privacyAISettings.confirmDeleteAllLocalData()

        let newUserId = try #require(env.dependencies.session.currentUserId)
        #expect(newUserId != userA)
        #expect(try await env.container.users.fetch(id: userA) == nil)
        #expect(!transactionMerchants(in: env.viewModels.transaction).contains("旧商家A"))
        #expect(!debtLenders(in: env.viewModels.debt).contains("银行-A"))
        #expect(!accountNames(in: env.viewModels.account).contains("现金-A"))
        #expect(env.viewModels.debt.selectedDebtId == nil)
        #expect(env.viewModels.ai.questionText.isEmpty)
        #expect(env.viewModels.account.isPresentingPrivacyAISettings)
        #expect(!env.viewModels.privacyAISettings.allowScreenshotImageToAI)
        #expect(!env.viewModels.privacyAISettings.allowDebtScanImageToAI)
        #expect(!env.viewModels.privacyAISettings.allowFinancialContextToAI)
        #expect(!env.viewModels.privacyAISettings.retainOriginalImages)

        let consent = try await env.dependencies.consentService.fetchOrDefault(userId: newUserId)
        #expect(!consent.allowScreenshotImageToAI)
        #expect(!consent.allowDebtScanImageToAI)
        #expect(!consent.allowFinancialContextToAI)
        #expect(!consent.retainOriginalImages)
        #expect(try await env.container.insights.fetchAll(userId: newUserId).isEmpty)
        #expect(try await env.container.aiRecognitionRecords.fetchAll(userId: newUserId).isEmpty)
    }

    @Test("N wipe copy does not expose identifiers or paths")
    func wipeCopySafety() {
        assertNoSensitiveLeak(in: PrivacyError.persistentDeletionIncomplete.userMessage)
        assertNoSensitiveLeak(in: PrivacyError.mediaCleanupIncomplete.userMessage)
        assertNoSensitiveLeak(in: PrivacyError.mediaCleanupIncomplete.userMessage)
        #expect(!PrivacyError.mediaCleanupIncomplete.userMessage.contains(userA.uuidString))
    }

    private func makeManualEnv() async throws -> ManualEnv {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("wipe-ui-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        try await seedUserA(
            container: container,
            mediaRoot: tempRoot
        )
        let users = ControllableUserRepository(inner: container.users)
        let binaries = ControllableMediaBinaryStore(rootURL: tempRoot)
        let media = MediaLifecycleService(artifacts: container.mediaArtifacts, binaries: binaries)
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        let session = AppSession(users: container.users)
        session.configureForPreview(userId: userA)
        let privacy = PrivacyDataService(
            users: users,
            transactions: container.transactions,
            debts: container.debts,
            debtEvents: container.debtEvents,
            accounts: container.accounts,
            recognitionRecords: container.aiRecognitionRecords,
            consents: container.aiDataConsents,
            media: media
        )
        let viewModel = PrivacyAISettingsViewModel(
            consentService: consentService,
            originalImageRetention: OriginalImageRetentionService(
                consentService: consentService,
                media: media
            ),
            privacyData: privacy,
            session: session
        )
        return ManualEnv(
            viewModel: viewModel,
            container: container,
            users: users,
            session: session,
            tempRoot: tempRoot
        )
    }

    private func makeAppCompositionEnv() async throws -> AppEnv {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("wipe-app-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let binaries = ControllableMediaBinaryStore(rootURL: tempRoot)
        try await seedUserA(
            container: container,
            media: MediaLifecycleService(artifacts: container.mediaArtifacts, binaries: binaries)
        )
        let dependencies = AppDependencies(repositories: container)
        dependencies.session.configureForPreview(userId: userA)
        let homeVM = dependencies.makeHomeViewModel()
        let aiVM = dependencies.makeAIViewModel()
        let accountVM = dependencies.makeAccountViewModel(onDataChanged: { await homeVM.load() })
        let privacyVM = dependencies.makePrivacyAISettingsViewModel {
            await aiVM.reloadConsent()
            await homeVM.load()
        }
        let transactionVM = dependencies.makeTransactionViewModel(onDataChanged: {
            await homeVM.load()
            await accountVM.load()
        })
        let screenshotVM = dependencies.makeScreenshotBookkeepingViewModel(onSaved: {
            await transactionVM.load()
            await homeVM.load()
        })
        let debtVM = dependencies.makeDebtViewModel(onDataChanged: {
            await homeVM.load()
            await accountVM.load()
        })
        let debtScannerVM = dependencies.makeDebtScannerViewModel(onCompleted: {
            await debtVM.load()
            await homeVM.load()
        })
        let viewModels = ApplicationRestoreRefresh.ViewModels(
            home: homeVM,
            transaction: transactionVM,
            screenshot: screenshotVM,
            debt: debtVM,
            debtScanner: debtScannerVM,
            account: accountVM,
            ai: aiVM,
            privacyAISettings: privacyVM
        )
        return AppEnv(
            dependencies: dependencies,
            viewModels: viewModels,
            container: container,
            binaries: binaries,
            tempRoot: tempRoot
        )
    }

    private func seedUserA(
        container: RepositoryContainer,
        mediaRoot: URL? = nil,
        media: MediaLifecycleService? = nil
    ) async throws {
        try await container.users.upsert(User(id: userA, displayName: "A"))
        let account = Account(
            id: oldAccountId,
            userId: userA,
            name: "现金-A",
            type: .cash,
            openingBalance: Money(amount: 100, currencyCode: "CNY")
        )
        try await container.accounts.upsert(account)
        try await container.transactions.upsert(
            Transaction(
                userId: userA,
                accountId: account.id,
                amount: Money(amount: 12, currencyCode: "CNY"),
                merchant: "旧商家A",
                transactionType: .expense
            )
        )
        try await container.debts.upsert(Debt(userId: userA, lender: "银行-A", source: .userInput))
        try await container.insights.upsert(
            FinancialInsight(
                userId: userA,
                type: .summary,
                title: "旧洞察",
                body: "历史",
                modelName: "test-model"
            )
        )
        try await container.aiDataConsents.upsert(
            AIDataConsent(
                userId: userA,
                allowScreenshotImageToAI: true,
                allowFinancialContextToAI: true,
                retainOriginalImages: true
            )
        )
        let mediaService: MediaLifecycleService
        if let media {
            mediaService = media
        } else if let mediaRoot {
            mediaService = MediaLifecycleService(
                artifacts: container.mediaArtifacts,
                binaries: DirectoryMediaBinaryStore(rootURL: mediaRoot)
            )
        } else {
            mediaService = MediaLifecycleService(
                artifacts: container.mediaArtifacts,
                binaries: NoPersistMediaBinaryStore()
            )
        }
        _ = try await mediaService.register(
            data: sampleImage,
            userId: userA,
            kind: .screenshotTransaction,
            retainOriginal: true
        )
        try await container.aiRecognitionRecords.upsert(
            AIRecognitionRecord(
                userId: userA,
                kind: .screenshotTransaction,
                status: .recognized,
                summaryLabel: "截图记账识别"
            )
        )
    }

    private func transactionMerchants(in viewModel: TransactionViewModel) -> [String] {
        guard case let .content(snapshot) = viewModel.phase else { return [] }
        return snapshot.sections.flatMap(\.items).map { $0.transaction.merchant ?? "" }
    }

    private func debtLenders(in viewModel: DebtViewModel) -> [String] {
        guard case let .content(snapshot) = viewModel.phase else { return [] }
        return snapshot.debts.compactMap(\.lender)
    }

    private func accountNames(in viewModel: AccountViewModel) -> [String] {
        guard case let .content(snapshot) = viewModel.phase else { return [] }
        return snapshot.accounts.map(\.account.name)
    }

    private func assertNoSensitiveLeak(in message: String) {
        #expect(!message.contains(userA.uuidString))
        #expect(!message.lowercased().contains("file://"))
        #expect(!message.contains("media-originals"))
        #expect(!message.contains("img-"))
        #expect(!message.contains("NSError"))
        #expect(!message.contains("test.media"))
    }
}

private struct ManualEnv {
    let viewModel: PrivacyAISettingsViewModel
    let container: RepositoryContainer
    let users: ControllableUserRepository
    let session: AppSession
    let tempRoot: URL
}

private struct AppEnv {
    let dependencies: AppDependencies
    let viewModels: ApplicationRestoreRefresh.ViewModels
    let container: RepositoryContainer
    let binaries: ControllableMediaBinaryStore
    let tempRoot: URL
}

private actor ControllableUserRepository: UserRepository {
    private let inner: any UserRepository
    private var failDelete = false
    private var holdDelete = false
    private var deleteCount = 0
    private var holdContinuation: CheckedContinuation<Void, Never>?

    init(inner: any UserRepository) {
        self.inner = inner
    }

    func setFailDelete(_ value: Bool) { failDelete = value }
    func setHoldDelete(_ value: Bool) { holdDelete = value }
    func deleteCallCount() -> Int { deleteCount }

    func releaseHold() {
        holdContinuation?.resume()
        holdContinuation = nil
    }

    func upsert(_ user: User) async throws { try await inner.upsert(user) }
    func fetch(id: UUID) async throws -> User? { try await inner.fetch(id: id) }
    func fetchAll() async throws -> [User] { try await inner.fetchAll() }

    func delete(id: UUID) async throws {
        deleteCount += 1
        if holdDelete {
            await withCheckedContinuation { continuation in
                holdContinuation = continuation
            }
        }
        if failDelete {
            throw PrivacyError.operationFailed
        }
        try await inner.delete(id: id)
    }
}

private actor ControllableMediaBinaryStore: MediaBinaryStoring {
    private let inner: DirectoryMediaBinaryStore
    private var failDeleteAll = false

    init(rootURL: URL) {
        inner = DirectoryMediaBinaryStore(rootURL: rootURL)
    }

    func setFailDeleteAll(_ value: Bool) { failDeleteAll = value }

    func save(imageId: String, userId: UUID, data: Data) async throws -> String? {
        try await inner.save(imageId: imageId, userId: userId, data: data)
    }

    func load(imageId: String, userId: UUID) async throws -> Data? {
        try await inner.load(imageId: imageId, userId: userId)
    }

    func delete(imageId: String, userId: UUID) async throws {
        try await inner.delete(imageId: imageId, userId: userId)
    }

    func deleteAll(userId: UUID) async throws {
        if failDeleteAll {
            throw NSError(domain: "test.media.wipe", code: 2)
        }
        try await inner.deleteAll(userId: userId)
    }
}
