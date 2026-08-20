import Foundation
import Testing
@testable import YoushuData
import YoushuDomain
import YoushuFoundation

@Suite("Application restore refresh controller")
@MainActor
struct ApplicationRestoreRefreshControllerTests {
    private static let fixedCreatedAt = Date(timeIntervalSince1970: 1_700_000_000)
    private static let userU1 = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
    private static let userU2 = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
    private static let accountU1 = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
    private static let accountU2 = UUID(uuidString: "00000000-0000-0000-0000-000000000302")!
    private static let txStateA = UUID(uuidString: "00000000-0000-0000-0000-000000000401")!
    private static let txStateB = UUID(uuidString: "00000000-0000-0000-0000-000000000402")!

    @MainActor
    private final class TransactionPresentationSurface {
        private let store: YoushuStore
        private let session: AppSession
        private(set) var displayedMerchants: [String] = []
        private(set) var loadCount = 0

        init(store: YoushuStore, session: AppSession) {
            self.store = store
            self.session = session
        }

        func load() async {
            loadCount += 1
            guard let userId = session.currentUserId else {
                displayedMerchants = []
                return
            }
            let snapshot = await store.currentSnapshot()
            displayedMerchants = snapshot.transactions
                .filter { $0.userId == userId }
                .compactMap(\.merchant)
        }
    }

    private func makeSession(store: YoushuStore) -> AppSession {
        AppSession(users: RepositoryContainer(store: store).users)
    }

    private func makeController(
        session: AppSession,
        store: YoushuStore,
        surface: TransactionPresentationSurface,
        resetCount: UnsafeMutablePointer<Int>? = nil
    ) -> ApplicationRestoreRefreshController {
        ApplicationRestoreRefreshController(
            actions: .init(
                resyncSession: {
                    try await session.resyncCurrentUserFromStore()
                },
                bumpDataRevision: {
                    session.bumpApplicationDataRevision()
                },
                resetTransientState: {
                    if let resetCount {
                        resetCount.pointee += 1
                    }
                },
                reloadPresentation: {
                    await surface.load()
                }
            )
        )
    }

    private func stateABackupPayload() -> BackupPayloadV1 {
        BackupPayloadV1(
            metadata: BackupPayloadMetadataV1(
                createdAt: Self.fixedCreatedAt,
                sourceStoreSchemaVersion: YoushuSnapshot.currentSchemaVersion,
                sourceAppVersion: "state-b"
            ),
            financialData: BackupFinancialDataV1(
                users: [
                    BackupUserV1(
                        id: Self.userU1,
                        displayName: "Same User",
                        preferredCurrency: "CNY",
                        debtInventoryEstablishment: .partial,
                        createdAt: Self.fixedCreatedAt,
                        updatedAt: Self.fixedCreatedAt
                    ),
                ],
                accounts: [
                    Account(id: Self.accountU1, userId: Self.userU1, name: "Backup Account", type: .cash),
                ],
                transactions: [
                    Transaction(
                        id: Self.txStateB,
                        userId: Self.userU1,
                        accountId: Self.accountU1,
                        amount: Money(amount: 500, currencyCode: "CNY"),
                        merchant: "State B Merchant",
                        transactionType: .expense
                    ),
                ]
            )
        )
    }

    private func stateBUserBackupPayload() -> BackupPayloadV1 {
        BackupPayloadV1(
            metadata: BackupPayloadMetadataV1(
                createdAt: Self.fixedCreatedAt,
                sourceStoreSchemaVersion: YoushuSnapshot.currentSchemaVersion,
                sourceAppVersion: "user-b"
            ),
            financialData: BackupFinancialDataV1(
                users: [
                    BackupUserV1(
                        id: Self.userU2,
                        displayName: "Restored User",
                        preferredCurrency: "CNY",
                        debtInventoryEstablishment: .partial,
                        createdAt: Self.fixedCreatedAt,
                        updatedAt: Self.fixedCreatedAt
                    ),
                ],
                accounts: [
                    Account(id: Self.accountU2, userId: Self.userU2, name: "User B Account", type: .cash),
                ],
                transactions: [
                    Transaction(
                        id: Self.txStateB,
                        userId: Self.userU2,
                        accountId: Self.accountU2,
                        amount: Money(amount: 120, currencyCode: "CNY"),
                        merchant: "User B Merchant",
                        transactionType: .expense
                    ),
                ]
            )
        )
    }

    @Test("same user restore refresh observes State B not stale State A")
    func sameUserRestoreRefresh() async throws {
        let store = YoushuStore()
        let session = makeSession(store: store)
        let surface = TransactionPresentationSurface(store: store, session: session)
        let controller = makeController(session: session, store: store, surface: surface)
        let container = RepositoryContainer(store: store)

        try await container.users.upsert(User(id: Self.userU1, displayName: "Same User"))
        try await container.accounts.upsert(
            Account(id: Self.accountU1, userId: Self.userU1, name: "Live Account", type: .cash)
        )
        try await container.transactions.upsert(
            Transaction(
                id: Self.txStateA,
                userId: Self.userU1,
                accountId: Self.accountU1,
                amount: Money(amount: 100, currencyCode: "CNY"),
                merchant: "State A Merchant",
                transactionType: .expense
            )
        )
        session.configureForPreview(userId: Self.userU1)

        await surface.load()
        #expect(surface.displayedMerchants == ["State A Merchant"])

        let backupData = try BackupCodec.encode(payload: stateABackupPayload(), passphrase: "restore-pass")
        let restoreResult = try await BackupRestoreService(store: store).restoreBackup(
            data: backupData,
            passphrase: "restore-pass"
        )
        #expect(restoreResult.requiresApplicationReload)
        #expect(restoreResult.userIdentityChanged == false)
        #expect(surface.displayedMerchants == ["State A Merchant"])

        try await controller.perform()

        #expect(surface.displayedMerchants == ["State B Merchant"])
        #expect(session.currentUserId == Self.userU1)
        #expect(surface.loadCount >= 2)
    }

    @Test("different user restore refresh adopts restored user identity")
    func differentUserRestoreRefresh() async throws {
        let store = YoushuStore()
        let session = makeSession(store: store)
        let surface = TransactionPresentationSurface(store: store, session: session)
        let controller = makeController(session: session, store: store, surface: surface)
        let container = RepositoryContainer(store: store)

        try await container.users.upsert(User(id: Self.userU1, displayName: "Original User"))
        try await container.accounts.upsert(
            Account(id: Self.accountU1, userId: Self.userU1, name: "Original Account", type: .cash)
        )
        try await container.transactions.upsert(
            Transaction(
                id: Self.txStateA,
                userId: Self.userU1,
                accountId: Self.accountU1,
                amount: Money(amount: 50, currencyCode: "CNY"),
                merchant: "Original Merchant",
                transactionType: .expense
            )
        )
        try await session.resyncCurrentUserFromStore()
        await surface.load()
        #expect(surface.displayedMerchants == ["Original Merchant"])

        let backupData = try BackupCodec.encode(payload: stateBUserBackupPayload(), passphrase: "restore-pass")
        let restoreResult = try await BackupRestoreService(store: store).restoreBackup(
            data: backupData,
            passphrase: "restore-pass"
        )
        #expect(restoreResult.userIdentityChanged)
        #expect(session.currentUserId == Self.userU1)

        try await controller.perform()

        #expect(session.currentUserId == Self.userU2)
        #expect(surface.displayedMerchants == ["User B Merchant"])
    }

    @Test("refresh remains safe when backup matches current logical state")
    func unchangedDataRefreshIsIdempotent() async throws {
        let store = YoushuStore()
        let session = makeSession(store: store)
        let surface = TransactionPresentationSurface(store: store, session: session)
        let controller = makeController(session: session, store: store, surface: surface)
        let container = RepositoryContainer(store: store)

        try await container.users.upsert(User(id: Self.userU1, displayName: "Same User"))
        try await container.accounts.upsert(
            Account(id: Self.accountU1, userId: Self.userU1, name: "Backup Account", type: .cash)
        )
        try await container.transactions.upsert(
            Transaction(
                id: Self.txStateB,
                userId: Self.userU1,
                accountId: Self.accountU1,
                amount: Money(amount: 500, currencyCode: "CNY"),
                merchant: "State B Merchant",
                transactionType: .expense
            )
        )
        session.configureForPreview(userId: Self.userU1)
        await surface.load()

        let backupData = try BackupCodec.encode(payload: stateABackupPayload(), passphrase: "restore-pass")
        _ = try await BackupRestoreService(store: store).restoreBackup(data: backupData, passphrase: "restore-pass")
        try await controller.perform()

        #expect(surface.displayedMerchants == ["State B Merchant"])
        #expect(session.currentUserId == Self.userU1)
    }

    @Test("application refresh resets AI consent to denied default")
    func consentAfterRefresh() async throws {
        let store = YoushuStore()
        let session = makeSession(store: store)
        let container = RepositoryContainer(store: store)
        let consentService = AIDataConsentService(consents: container.aiDataConsents)
        var consentAuthorized: Bool?

        try await container.users.upsert(User(id: Self.userU1, displayName: "Same User"))
        session.configureForPreview(userId: Self.userU1)
        try await consentService.acceptAssistantPrivacy(userId: Self.userU1)

        let before = try await consentService.fetchOrDefault(userId: Self.userU1)
        consentAuthorized = before.allowFinancialContextToAI
        #expect(consentAuthorized == true)

        let backupData = try BackupCodec.encode(payload: stateABackupPayload(), passphrase: "restore-pass")
        _ = try await BackupRestoreService(store: store).restoreBackup(data: backupData, passphrase: "restore-pass")

        let controller = ApplicationRestoreRefreshController(
            actions: .init(
                resyncSession: { try await session.resyncCurrentUserFromStore() },
                bumpDataRevision: { session.bumpApplicationDataRevision() },
                resetTransientState: {},
                reloadPresentation: {
                    let consent = try? await consentService.fetchOrDefault(userId: session.currentUserId!)
                    consentAuthorized = consent?.allowFinancialContextToAI
                }
            )
        )
        try await controller.perform()

        let after = try await consentService.fetchOrDefault(userId: Self.userU1)
        #expect(after.allowFinancialContextToAI == false)
        #expect(after.allowScreenshotImageToAI == false)
        #expect(consentAuthorized == false)
    }

    @Test("application refresh bumps session data revision")
    func refreshBumpsRevision() async throws {
        let store = YoushuStore()
        let session = makeSession(store: store)
        let container = RepositoryContainer(store: store)
        try await container.users.upsert(User(id: Self.userU1, displayName: "Same User"))
        session.configureForPreview(userId: Self.userU1)
        let before = session.applicationDataRevision

        let controller = ApplicationRestoreRefreshController(
            actions: .init(
                resyncSession: { try await session.resyncCurrentUserFromStore() },
                bumpDataRevision: { session.bumpApplicationDataRevision() },
                resetTransientState: {},
                reloadPresentation: {}
            )
        )
        try await controller.perform()

        #expect(session.applicationDataRevision == before + 1)
    }

    @Test("refresh controller invokes reset before reload")
    func resetBeforeReloadOrdering() async throws {
        var resetCount = 0
        var reloadCount = 0
        var resetHappenedFirst = false

        let controller = ApplicationRestoreRefreshController(
            actions: .init(
                resyncSession: {},
                bumpDataRevision: {},
                resetTransientState: {
                    resetCount += 1
                    resetHappenedFirst = reloadCount == 0
                },
                reloadPresentation: {
                    reloadCount += 1
                }
            )
        )
        try await controller.perform()

        #expect(resetCount == 1)
        #expect(reloadCount == 1)
        #expect(resetHappenedFirst)
    }
}
