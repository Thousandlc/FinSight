import Foundation
import Testing
import YoushuData
import YoushuDomain
import YoushuFoundation

@Suite("Privacy wipe-all user data")
struct PrivacyWipeAllUserDataTests {
    private let sampleImage = Data("wipe-retained-original".utf8)

    @Test("A complete deletion inventory removes all current-user persisted collections and binaries")
    func completeDeletionInventory() async throws {
        let env = try await makePopulatedEnv()
        defer { try? FileManager.default.removeItem(at: env.tempRoot) }

        let result = try await env.privacy.wipeAllUserData(userId: env.userA)
        #expect(result == .complete)

        try await assertUserFullyDeleted(env: env, userId: env.userA)
        #expect(try await env.binaries.load(imageId: env.imageIdA, userId: env.userA) == nil)
        let userDir = env.tempRoot.appendingPathComponent(env.userA.uuidString, isDirectory: true)
        #expect(!FileManager.default.fileExists(atPath: userDir.path))
    }

    @Test("B successful wipe removes consent and AI history")
    func consentAndAIHistoryDeleted() async throws {
        let env = try await makePopulatedEnv()
        defer { try? FileManager.default.removeItem(at: env.tempRoot) }

        _ = try await env.privacy.wipeAllUserData(userId: env.userA)

        #expect(try await env.container.aiDataConsents.fetch(userId: env.userA) == nil)
        #expect(try await env.container.insights.fetchAll(userId: env.userA).isEmpty)
        #expect(try await env.container.aiRecognitionRecords.fetchAll(userId: env.userA).isEmpty)
    }

    @Test("C directory-backed retained binaries and media metadata are removed")
    func mediaBinaryDeletion() async throws {
        let env = try await makePopulatedEnv()
        defer { try? FileManager.default.removeItem(at: env.tempRoot) }

        #expect(try await env.binaries.load(imageId: env.imageIdA, userId: env.userA) == sampleImage)
        #expect(!(try await env.container.mediaArtifacts.fetchAll(userId: env.userA)).isEmpty)

        _ = try await env.privacy.wipeAllUserData(userId: env.userA)

        #expect(try await env.binaries.load(imageId: env.imageIdA, userId: env.userA) == nil)
        #expect(try await env.container.mediaArtifacts.fetchAll(userId: env.userA).isEmpty)
    }

    @Test("D wiping user A leaves user B financial, consent, insight, and media intact")
    func crossUserIsolation() async throws {
        let env = try await makePopulatedEnv()
        defer { try? FileManager.default.removeItem(at: env.tempRoot) }

        _ = try await env.privacy.wipeAllUserData(userId: env.userA)

        #expect(try await env.container.users.fetch(id: env.userB) != nil)
        #expect(!(try await env.container.accounts.fetchAll(userId: env.userB)).isEmpty)
        #expect(!(try await env.container.transactions.fetchAll(userId: env.userB)).isEmpty)
        #expect(!(try await env.container.debts.fetchAll(userId: env.userB)).isEmpty)
        #expect(try await env.container.aiDataConsents.fetch(userId: env.userB) != nil)
        #expect(!(try await env.container.insights.fetchAll(userId: env.userB)).isEmpty)
        #expect(try await env.binaries.load(imageId: env.imageIdB, userId: env.userB) == Data("user-b-image".utf8))
        #expect(!(try await env.container.mediaArtifacts.fetchAll(userId: env.userB)).isEmpty)
    }

    @Test("E wipe does not delete external backup artifacts outside the private store")
    func externalBackupIndependence() async throws {
        let env = try await makePopulatedEnv()
        defer { try? FileManager.default.removeItem(at: env.tempRoot) }

        let backupRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("youshu-external-backup-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: backupRoot) }
        try FileManager.default.createDirectory(at: backupRoot, withIntermediateDirectories: true)
        let backupFile = backupRoot.appendingPathComponent("FinSight-Backup.finsightbackup")
        let backupBytes = Data("not-a-live-store".utf8)
        try backupBytes.write(to: backupFile)

        _ = try await env.privacy.wipeAllUserData(userId: env.userA)

        #expect(FileManager.default.fileExists(atPath: backupFile.path))
        #expect(try Data(contentsOf: backupFile) == backupBytes)
    }

    @Test("F persistent-store deletion failure is not success and does not restore deleted binaries")
    func persistentStoreDeletionFailure() async throws {
        let env = try await makePopulatedEnv()
        defer { try? FileManager.default.removeItem(at: env.tempRoot) }

        await env.users.setFailDelete(true)
        do {
            _ = try await env.privacy.wipeAllUserData(userId: env.userA)
            Issue.record("Expected persistent deletion failure")
        } catch let error as PrivacyError {
            #expect(error == .persistentDeletionIncomplete)
            assertNoSensitiveLeak(in: error.userMessage)
        }

        #expect(try await env.container.users.fetch(id: env.userA) != nil)
        #expect(!(try await env.container.transactions.fetchAll(userId: env.userA)).isEmpty)
        #expect(try await env.container.aiDataConsents.fetch(userId: env.userA) != nil)
        #expect(try await env.binaries.load(imageId: env.imageIdA, userId: env.userA) == nil)
    }

    @Test("G media cleanup failure still deletes persisted records and reports incomplete cleanup")
    func mediaCleanupPartialFailure() async throws {
        let env = try await makePopulatedEnv()
        defer { try? FileManager.default.removeItem(at: env.tempRoot) }

        await env.binaries.setFailDeleteAll(true)
        let result = try await env.privacy.wipeAllUserData(userId: env.userA)
        #expect(result == .mediaCleanupIncomplete)

        try await assertUserFullyDeleted(env: env, userId: env.userA)
        #expect(try await env.binaries.load(imageId: env.imageIdA, userId: env.userA) == sampleImage)

        await env.binaries.setFailDeleteAll(false)
        try await env.privacy.retryWipeMediaCleanup(userId: env.userA)
        #expect(try await env.binaries.load(imageId: env.imageIdA, userId: env.userA) == nil)
    }

    @Test("N user-facing wipe errors omit UUID, path, and media ids")
    func failureCopySafety() {
        let persistent = PrivacyError.persistentDeletionIncomplete.userMessage
        let media = PrivacyError.mediaCleanupIncomplete.userMessage
        assertNoSensitiveLeak(in: persistent)
        assertNoSensitiveLeak(in: media)
        #expect(persistent.contains("未能删除全部本地数据"))
        #expect(media.contains("财务数据已删除"))
        #expect(media.contains("原图"))
        #expect(!media.contains("账本仍在"))
    }

    private func assertUserFullyDeleted(env: WipeEnv, userId: UUID) async throws {
        #expect(try await env.container.users.fetch(id: userId) == nil)
        #expect(try await env.container.accounts.fetchAll(userId: userId).isEmpty)
        #expect(try await env.container.transactions.fetchAll(userId: userId).isEmpty)
        #expect(try await env.container.debts.fetchAll(userId: userId).isEmpty)
        #expect(try await env.container.repaymentPlans.fetchAll(userId: userId).isEmpty)
        #expect(try await env.container.assets.fetchAll(userId: userId).isEmpty)
        #expect(try await env.container.budgets.fetchAll(userId: userId).isEmpty)
        #expect(try await env.container.goals.fetchAll(userId: userId).isEmpty)
        #expect(try await env.container.insights.fetchAll(userId: userId).isEmpty)
        #expect(try await env.container.pendingDebtLinks.fetchAll(userId: userId).isEmpty)
        #expect(try await env.container.suspectedDebts.fetchAll(userId: userId).isEmpty)
        #expect(try await env.container.aiDataConsents.fetch(userId: userId) == nil)
        #expect(try await env.container.aiRecognitionRecords.fetchAll(userId: userId).isEmpty)
        #expect(try await env.container.mediaArtifacts.fetchAll(userId: userId).isEmpty)
        let snapshot = await env.store.currentSnapshot()
        #expect(snapshot.debtEvents.allSatisfy { $0.userId != userId })
        #expect(snapshot.subscriptions.allSatisfy { $0.userId != userId })
    }

    private func assertNoSensitiveLeak(in message: String) {
        #expect(!message.contains("00000000"))
        #expect(!message.contains("uuid"))
        #expect(!message.lowercased().contains("file://"))
        #expect(!message.contains("media-originals"))
        #expect(!message.contains("img-"))
        #expect(!message.contains("\\"))
        #expect(!message.contains("/Users"))
        #expect(!message.contains("C:\\"))
    }

    private func makePopulatedEnv() async throws -> WipeEnv {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("youshu-wipe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userA = UUID(uuidString: "00000000-0000-0000-0000-000000000a01")!
        let userB = UUID(uuidString: "00000000-0000-0000-0000-000000000b01")!
        let binaries = ControllableMediaBinaryStore(rootURL: tempRoot)
        let media = MediaLifecycleService(artifacts: container.mediaArtifacts, binaries: binaries)
        let users = ControllableUserRepository(inner: container.users)
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

        try await seedUser(
            userId: userA,
            displayName: "A",
            store: store,
            container: container,
            media: media,
            image: sampleImage,
            merchant: "旧商家A"
        )
        try await seedUser(
            userId: userB,
            displayName: "B",
            store: store,
            container: container,
            media: media,
            image: Data("user-b-image".utf8),
            merchant: "商家B"
        )

        let artifactsA = try await container.mediaArtifacts.fetchAll(userId: userA)
        let artifactsB = try await container.mediaArtifacts.fetchAll(userId: userB)
        let imageIdA = try #require(artifactsA.first?.id)
        let imageIdB = try #require(artifactsB.first?.id)

        return WipeEnv(
            privacy: privacy,
            container: container,
            store: store,
            binaries: binaries,
            users: users,
            userA: userA,
            userB: userB,
            imageIdA: imageIdA,
            imageIdB: imageIdB,
            tempRoot: tempRoot
        )
    }

    private func seedUser(
        userId: UUID,
        displayName: String,
        store: YoushuStore,
        container: RepositoryContainer,
        media: MediaLifecycleService,
        image: Data,
        merchant: String
    ) async throws {
        try await container.users.upsert(User(id: userId, displayName: displayName))
        let account = Account(
            userId: userId,
            name: "现金-\(displayName)",
            type: .cash,
            openingBalance: Money(amount: 100, currencyCode: "CNY")
        )
        try await container.accounts.upsert(account)
        let transaction = Transaction(
            userId: userId,
            accountId: account.id,
            amount: Money(amount: 12, currencyCode: "CNY"),
            merchant: merchant,
            transactionType: .expense
        )
        try await container.transactions.upsert(transaction)
        let debt = Debt(userId: userId, lender: "银行-\(displayName)", source: .userInput)
        try await container.debts.upsert(debt)
        try await container.debtEvents.upsert(
            DebtEvent(debtId: debt.id, userId: userId, type: .created)
        )
        try await container.repaymentPlans.upsert(
            RepaymentPlan(
                debtId: debt.id,
                userId: userId,
                installmentAmount: Money(amount: 10, currencyCode: "CNY"),
                frequency: .monthly,
                startDate: Date()
            )
        )
        try await container.assets.upsert(
            Asset(
                userId: userId,
                name: "资产-\(displayName)",
                type: .cashEquivalent,
                currentValue: Money(amount: 50, currencyCode: "CNY")
            )
        )
        try await container.budgets.upsert(
            Budget(
                userId: userId,
                name: "预算-\(displayName)",
                limit: Money(amount: 200, currencyCode: "CNY")
            )
        )
        try await container.goals.upsert(
            Goal(
                userId: userId,
                name: "目标-\(displayName)",
                type: .savings,
                targetAmount: Money(amount: 500, currencyCode: "CNY")
            )
        )
        try await store.upsertSubscription(
            Subscription(
                userId: userId,
                name: "订阅-\(displayName)",
                amount: Money(amount: 15, currencyCode: "CNY")
            )
        )
        try await container.insights.upsert(
            FinancialInsight(
                userId: userId,
                type: .summary,
                title: "洞察-\(displayName)",
                body: "历史洞察",
                modelName: "test-model"
            )
        )
        try await container.pendingDebtLinks.upsert(
            PendingDebtLink(
                userId: userId,
                transactionId: transaction.id,
                confidence: 0.4,
                reason: "待确认"
            )
        )
        try await container.suspectedDebts.upsert(
            SuspectedDebt(
                userId: userId,
                merchant: merchant,
                amount: Money(amount: 12, currencyCode: "CNY"),
                dayOfMonth: 1,
                occurrenceCount: 2,
                sampleTransactionIds: [transaction.id],
                reason: "疑似债务"
            )
        )
        try await container.aiDataConsents.upsert(
            AIDataConsent(
                userId: userId,
                allowScreenshotImageToAI: true,
                allowDebtScanImageToAI: true,
                allowFinancialContextToAI: true,
                retainOriginalImages: true
            )
        )
        let artifact = try await media.register(
            data: image,
            userId: userId,
            kind: .screenshotTransaction,
            retainOriginal: true
        )
        try await container.aiRecognitionRecords.upsert(
            AIRecognitionRecord(
                userId: userId,
                kind: .screenshotTransaction,
                sourceImageId: artifact.id,
                status: .recognized,
                summaryLabel: "截图记账识别"
            )
        )
    }
}

private struct WipeEnv {
    let privacy: PrivacyDataService
    let container: RepositoryContainer
    let store: YoushuStore
    let binaries: ControllableMediaBinaryStore
    let users: ControllableUserRepository
    let userA: UUID
    let userB: UUID
    let imageIdA: String
    let imageIdB: String
    let tempRoot: URL
}

private actor ControllableUserRepository: UserRepository {
    private let inner: any UserRepository
    private var failDelete = false
    private var deleteCount = 0

    init(inner: any UserRepository) {
        self.inner = inner
    }

    func setFailDelete(_ value: Bool) {
        failDelete = value
    }

    func deleteCallCount() -> Int {
        deleteCount
    }

    func upsert(_ user: User) async throws {
        try await inner.upsert(user)
    }

    func fetch(id: UUID) async throws -> User? {
        try await inner.fetch(id: id)
    }

    func fetchAll() async throws -> [User] {
        try await inner.fetchAll()
    }

    func delete(id: UUID) async throws {
        deleteCount += 1
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

    func setFailDeleteAll(_ value: Bool) {
        failDeleteAll = value
    }

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
