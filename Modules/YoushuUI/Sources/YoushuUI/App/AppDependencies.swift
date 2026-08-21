import Foundation
import YoushuAI
import YoushuData
import YoushuDomain

@MainActor
public struct AppDependencies {
    public typealias SourceAppVersionProvider = @Sendable () -> String?

    public let repositories: RepositoryContainer
    public let overviewServices: OverviewServiceContainer
    public let transactionService: TransactionService
    public let debtLinking: TransactionDebtLinkingService
    public let screenshotBookkeeping: ScreenshotBookkeepingService
    public let debtScanner: DebtScannerService
    public let privacyData: PrivacyDataService
    public let consentService: AIDataConsentService
    public let originalImageRetention: OriginalImageRetentionService
    public let backupCreation: BackupCreationService
    public let backupRestorePreflight: BackupRestorePreflightService
    public let backupRestore: BackupRestoreService
    public let secureTokens: any SecureTokenStoring
    public let session: AppSession

    public init(
        repositories: RepositoryContainer,
        financialAssistingMode: FinancialAssistingMode = .mock,
        gatewayConfiguration: AIGatewayConfiguration? = nil,
        mockAIProvider: MockAIProvider = MockAIProvider(),
        secureTokens: any SecureTokenStoring = InMemorySecureTokenStore(),
        gatewayTransport: (any GatewayHTTPTransport)? = nil,
        sourceAppVersionProvider: @escaping SourceAppVersionProvider = { nil },
        mediaBinaryRootURL: URL? = nil
    ) {
        self.repositories = repositories
        self.secureTokens = secureTokens
        let consent = AIDataConsentService(consents: repositories.aiDataConsents)
        self.consentService = consent
        let binaries: any MediaBinaryStoring = if let mediaBinaryRootURL {
            DirectoryMediaBinaryStore(rootURL: mediaBinaryRootURL)
        } else {
            NoPersistMediaBinaryStore()
        }
        let media = MediaLifecycleService(
            artifacts: repositories.mediaArtifacts,
            binaries: binaries
        )
        self.originalImageRetention = OriginalImageRetentionService(
            consentService: consent,
            media: media
        )
        let financialAssisting: any FinancialAssisting = Self.makeFinancialAssisting(
            mode: financialAssistingMode,
            gatewayConfiguration: gatewayConfiguration,
            mockAIProvider: mockAIProvider,
            secureTokens: secureTokens,
            gatewayTransport: gatewayTransport
        )
        self.overviewServices = OverviewServiceContainer(
            repositories: repositories,
            financialAssisting: financialAssisting,
            consentService: consent
        )
        let linking = TransactionDebtLinkingService(
            debts: repositories.debts,
            events: repositories.debtEvents,
            transactions: repositories.transactions,
            accounts: repositories.accounts,
            pendingLinks: repositories.pendingDebtLinks,
            suspectedDebts: repositories.suspectedDebts,
            debtManager: overviewServices.debtManager,
            matchAssistant: NoOpDebtMatchAssistant()
        )
        self.debtLinking = linking
        let txService = TransactionService(
            accounts: repositories.accounts,
            transactions: repositories.transactions,
            debtLinker: linking
        )
        self.transactionService = txService
        self.screenshotBookkeeping = ScreenshotBookkeepingService(
            extractor: mockAIProvider,
            transactionService: txService,
            accounts: repositories.accounts,
            consentService: consent,
            media: media,
            recognitionRecords: repositories.aiRecognitionRecords
        )
        self.debtScanner = DebtScannerService(
            scanner: mockAIProvider,
            debtService: overviewServices.debtManager,
            consentService: consent,
            media: media,
            recognitionRecords: repositories.aiRecognitionRecords
        )
        self.privacyData = PrivacyDataService(
            users: repositories.users,
            transactions: repositories.transactions,
            debts: repositories.debts,
            debtEvents: repositories.debtEvents,
            accounts: repositories.accounts,
            recognitionRecords: repositories.aiRecognitionRecords,
            consents: repositories.aiDataConsents,
            media: media,
            transactionManager: txService,
            debtManager: overviewServices.debtManager
        )
        let versionProvider = sourceAppVersionProvider
        self.backupCreation = BackupCreationService(
            store: repositories.store,
            metadataProvider: {
                BackupCreationMetadata(sourceAppVersion: versionProvider())
            }
        )
        self.backupRestorePreflight = BackupRestorePreflightService()
        self.backupRestore = BackupRestoreService(store: repositories.store)
        self.session = AppSession(users: repositories.users)
    }

    private static func makeFinancialAssisting(
        mode: FinancialAssistingMode,
        gatewayConfiguration: AIGatewayConfiguration?,
        mockAIProvider: MockAIProvider,
        secureTokens: any SecureTokenStoring,
        gatewayTransport: (any GatewayHTTPTransport)?
    ) -> any FinancialAssisting {
        switch mode {
        case .mock:
            return mockAIProvider
        case .remoteMonthlySummaryOnly:
            let remote: RemoteFinancialAIProvider?
            if let gatewayConfiguration {
                #if canImport(FoundationNetworking)
                let transport = gatewayTransport ?? URLSessionGatewayHTTPTransport()
                #else
                guard let gatewayTransport else {
                    return FinancialAssistingRouter(
                        mode: .remoteMonthlySummaryOnly,
                        mock: mockAIProvider,
                        remote: nil
                    )
                }
                let transport = gatewayTransport
                #endif
                let client = AIGatewayClient(
                    configuration: gatewayConfiguration,
                    transport: transport,
                    tokenStore: secureTokens
                )
                remote = RemoteFinancialAIProvider(client: client)
            } else {
                remote = nil
            }
            return FinancialAssistingRouter(
                mode: .remoteMonthlySummaryOnly,
                mock: mockAIProvider,
                remote: remote
            )
        }
    }

    @MainActor
    public func makeHomeViewModel() -> HomeViewModel {
        HomeViewModel(homeProvider: overviewServices.home, session: session)
    }

    @MainActor
    public func makeTransactionViewModel(onDataChanged: (@Sendable () async -> Void)? = nil) -> TransactionViewModel {
        TransactionViewModel(
            provider: overviewServices.transactions,
            transactionService: transactionService,
            accounts: repositories.accounts,
            session: session,
            onDataChanged: onDataChanged
        )
    }

    @MainActor
    public func makeScreenshotBookkeepingViewModel(onSaved: (@Sendable () async -> Void)? = nil) -> ScreenshotBookkeepingViewModel {
        ScreenshotBookkeepingViewModel(
            bookkeeping: screenshotBookkeeping,
            accounts: repositories.accounts,
            session: session,
            onSaved: onSaved
        )
    }

    @MainActor
    public func makeDebtViewModel(onDataChanged: (@Sendable () async -> Void)? = nil) -> DebtViewModel {
        DebtViewModel(
            provider: overviewServices.debts,
            debtService: overviewServices.debtManager,
            detailProvider: overviewServices.debtDetail,
            accounts: repositories.accounts,
            session: session,
            onDataChanged: onDataChanged
        )
    }

    @MainActor
    public func makeDebtScannerViewModel(onCompleted: (@Sendable () async -> Void)? = nil) -> DebtScannerViewModel {
        DebtScannerViewModel(
            scanner: debtScanner,
            session: session,
            onCompleted: onCompleted
        )
    }

    @MainActor
    public func makeAccountViewModel(
        onDataChanged: (@Sendable () async -> Void)? = nil
    ) -> AccountViewModel {
        AccountViewModel(
            provider: overviewServices.accounts,
            accountService: overviewServices.accountManager,
            session: session,
            onDataChanged: onDataChanged
        )
    }

    @MainActor
    public func makePrivacyAISettingsViewModel(
        onConsentChanged: (@Sendable () async -> Void)? = nil
    ) -> PrivacyAISettingsViewModel {
        PrivacyAISettingsViewModel(
            consentService: consentService,
            originalImageRetention: originalImageRetention,
            session: session,
            onConsentChanged: onConsentChanged
        )
    }

    @MainActor
    public func makeDataBackupViewModel(
        applicationRefresh: @escaping () async throws -> Void
    ) -> DataBackupViewModel {
        DataBackupViewModel(
            backupCreation: backupCreation,
            backupRestorePreflight: backupRestorePreflight,
            backupRestore: backupRestore,
            applicationRefresh: applicationRefresh
        )
    }

    @MainActor
    public func makeAIViewModel() -> AIAssistantViewModel {
        AIAssistantViewModel(
            provider: overviewServices.aiAssistant,
            session: session,
            consentService: consentService
        )
    }

    @MainActor
    public func bootstrap() async throws {
        try await session.bootstrap()
        try await ensureDefaultAccounts()
    }

    @MainActor
    private func ensureDefaultAccounts() async throws {
        guard let userId = session.currentUserId else { return }
        let existing = try await repositories.accounts.fetchAll(userId: userId)
        guard existing.isEmpty else { return }
        try await overviewServices.accountManager.create(
            CreateAccountInput(name: "现金", type: .cash),
            userId: userId
        )
        try await overviewServices.accountManager.create(
            CreateAccountInput(name: "银行卡", type: .bankCard),
            userId: userId
        )
    }
}
