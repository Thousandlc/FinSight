import Foundation
import Testing
import YoushuAI
import YoushuData
import YoushuDomain
import YoushuFoundation
@testable import YoushuUI

@Suite("Application restore refresh UI integration")
@MainActor
struct ApplicationRestoreRefreshUITests {
    private static let fixedCreatedAt = Date(timeIntervalSince1970: 1_700_000_000)
    private static let userU1 = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
    private static let userU2 = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
    private static let accountU1 = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
    private static let accountU2 = UUID(uuidString: "00000000-0000-0000-0000-000000000302")!
    private static let txStateA = UUID(uuidString: "00000000-0000-0000-0000-000000000401")!
    private static let txStateB = UUID(uuidString: "00000000-0000-0000-0000-000000000402")!

    private func makeComposition(store: YoushuStore) -> (AppDependencies, ApplicationRestoreRefresh.ViewModels) {
        let dependencies = AppDependencies(repositories: RepositoryContainer(store: store))
        let homeVM = dependencies.makeHomeViewModel()
        let aiVM = dependencies.makeAIViewModel()
        let accountVM = dependencies.makeAccountViewModel(
            onDataChanged: { await homeVM.load() }
        )
        let privacyAISettingsVM = dependencies.makePrivacyAISettingsViewModel {
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
            privacyAISettings: privacyAISettingsVM
        )
        return (dependencies, viewModels)
    }

    private func transactionMerchants(in viewModel: TransactionViewModel) -> [String] {
        guard case let .content(snapshot) = viewModel.phase else { return [] }
        return snapshot.sections.flatMap(\.items).map { $0.transaction.merchant ?? "" }
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
        let (dependencies, viewModels) = makeComposition(store: store)

        let container = dependencies.repositories
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
        dependencies.session.configureForPreview(userId: Self.userU1)

        await viewModels.transaction.load()
        #expect(transactionMerchants(in: viewModels.transaction) == ["State A Merchant"])

        let backupData = try BackupCodec.encode(payload: stateABackupPayload(), passphrase: "restore-pass")
        let restoreResult = try await dependencies.backupRestore.restoreBackup(
            data: backupData,
            passphrase: "restore-pass"
        )
        #expect(restoreResult.requiresApplicationReload)
        #expect(restoreResult.userIdentityChanged == false)

        #expect(transactionMerchants(in: viewModels.transaction) == ["State A Merchant"])

        try await ApplicationRestoreRefresh.perform(dependencies: dependencies, viewModels: viewModels)

        #expect(transactionMerchants(in: viewModels.transaction) == ["State B Merchant"])
        #expect(dependencies.session.currentUserId == Self.userU1)
    }

    @Test("different user restore refresh adopts restored user identity")
    func differentUserRestoreRefresh() async throws {
        let store = YoushuStore()
        let (dependencies, viewModels) = makeComposition(store: store)

        let container = dependencies.repositories
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
        try await dependencies.session.resyncCurrentUserFromStore()
        #expect(dependencies.session.currentUserId == Self.userU1)

        await viewModels.transaction.load()
        #expect(transactionMerchants(in: viewModels.transaction) == ["Original Merchant"])

        let backupData = try BackupCodec.encode(payload: stateBUserBackupPayload(), passphrase: "restore-pass")
        let restoreResult = try await dependencies.backupRestore.restoreBackup(
            data: backupData,
            passphrase: "restore-pass"
        )
        #expect(restoreResult.userIdentityChanged)

        #expect(dependencies.session.currentUserId == Self.userU1)
        #expect(transactionMerchants(in: viewModels.transaction) == ["Original Merchant"])

        try await ApplicationRestoreRefresh.perform(dependencies: dependencies, viewModels: viewModels)

        #expect(dependencies.session.currentUserId == Self.userU2)
        #expect(transactionMerchants(in: viewModels.transaction) == ["User B Merchant"])
    }

    @Test("refresh remains safe when backup matches current logical state")
    func unchangedDataRefreshIsIdempotent() async throws {
        let store = YoushuStore()
        let (dependencies, viewModels) = makeComposition(store: store)

        let container = dependencies.repositories
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
        dependencies.session.configureForPreview(userId: Self.userU1)

        await viewModels.transaction.load()
        #expect(transactionMerchants(in: viewModels.transaction) == ["State B Merchant"])

        let backupData = try BackupCodec.encode(payload: stateABackupPayload(), passphrase: "restore-pass")
        _ = try await dependencies.backupRestore.restoreBackup(data: backupData, passphrase: "restore-pass")
        try await ApplicationRestoreRefresh.perform(dependencies: dependencies, viewModels: viewModels)

        #expect(transactionMerchants(in: viewModels.transaction) == ["State B Merchant"])
        #expect(dependencies.session.currentUserId == Self.userU1)
    }

    @Test("application refresh resets AI consent to denied default")
    func consentAfterRefresh() async throws {
        let store = YoushuStore()
        let (dependencies, viewModels) = makeComposition(store: store)

        let container = dependencies.repositories
        try await container.users.upsert(User(id: Self.userU1, displayName: "Same User"))
        try await container.accounts.upsert(
            Account(id: Self.accountU1, userId: Self.userU1, name: "Live Account", type: .cash)
        )
        dependencies.session.configureForPreview(userId: Self.userU1)
        try await dependencies.consentService.acceptAssistantPrivacy(userId: Self.userU1)

        await viewModels.account.load()
        await viewModels.privacyAISettings.load()
        #expect(viewModels.privacyAISettings.allowFinancialContextToAI == true)

        let backupData = try BackupCodec.encode(payload: stateABackupPayload(), passphrase: "restore-pass")
        _ = try await dependencies.backupRestore.restoreBackup(data: backupData, passphrase: "restore-pass")
        try await ApplicationRestoreRefresh.perform(dependencies: dependencies, viewModels: viewModels)

        let consent = try await dependencies.consentService.fetchOrDefault(userId: Self.userU1)
        #expect(consent.allowFinancialContextToAI == false)
        #expect(consent.allowScreenshotImageToAI == false)
        #expect(viewModels.privacyAISettings.allowFinancialContextToAI == false)
        #expect(viewModels.privacyAISettings.allowScreenshotImageToAI == false)
        #expect(viewModels.privacyAISettings.retainOriginalImages == false)
        #expect(viewModels.ai.consentState == .unauthorized)

        await viewModels.home.load()
        if case let .content(overview) = viewModels.home.phase {
            #expect(overview.aiSummary?.modelName == "deterministic")
        } else {
            Issue.record("Expected home overview content after refresh")
        }
    }

    @Test("application refresh bumps session data revision")
    func refreshBumpsRevision() async throws {
        let store = YoushuStore()
        let (dependencies, viewModels) = makeComposition(store: store)

        let container = dependencies.repositories
        try await container.users.upsert(User(id: Self.userU1, displayName: "Same User"))
        dependencies.session.configureForPreview(userId: Self.userU1)
        let before = dependencies.session.applicationDataRevision

        let backupData = try BackupCodec.encode(payload: stateABackupPayload(), passphrase: "restore-pass")
        _ = try await dependencies.backupRestore.restoreBackup(data: backupData, passphrase: "restore-pass")
        try await ApplicationRestoreRefresh.perform(dependencies: dependencies, viewModels: viewModels)

        #expect(dependencies.session.applicationDataRevision == before + 1)
    }
}
