import Foundation
import YoushuData
import YoushuDomain

/// UI composition wrapper for post-restore application refresh.
@MainActor
public enum ApplicationRestoreRefresh {
    public struct ViewModels {
        public let home: HomeViewModel
        public let transaction: TransactionViewModel
        public let screenshot: ScreenshotBookkeepingViewModel
        public let debt: DebtViewModel
        public let debtScanner: DebtScannerViewModel
        public let account: AccountViewModel
        public let ai: AIAssistantViewModel
        public let privacyAISettings: PrivacyAISettingsViewModel

        public init(
            home: HomeViewModel,
            transaction: TransactionViewModel,
            screenshot: ScreenshotBookkeepingViewModel,
            debt: DebtViewModel,
            debtScanner: DebtScannerViewModel,
            account: AccountViewModel,
            ai: AIAssistantViewModel,
            privacyAISettings: PrivacyAISettingsViewModel
        ) {
            self.home = home
            self.transaction = transaction
            self.screenshot = screenshot
            self.debt = debt
            self.debtScanner = debtScanner
            self.account = account
            self.ai = ai
            self.privacyAISettings = privacyAISettings
        }
    }

    public static func perform(
        dependencies: AppDependencies,
        viewModels: ViewModels
    ) async throws {
        let controller = ApplicationRestoreRefreshController(
            actions: .init(
                resyncSession: {
                    try await dependencies.session.resyncCurrentUserFromStore()
                },
                bumpDataRevision: {
                    dependencies.session.bumpApplicationDataRevision()
                },
                resetTransientState: {
                    resetTransientState(viewModels)
                },
                reloadPresentation: {
                    await reloadPresentation(viewModels)
                }
            )
        )
        try await controller.perform()
    }

    static func resetTransientState(_ viewModels: ViewModels) {
        viewModels.debt.selectedDebtId = nil
        viewModels.debt.detail = nil
        viewModels.debt.isPresentingForm = false
        viewModels.debt.isPresentingRepayment = false
        viewModels.debt.isPresentingScanner = false

        viewModels.account.selectedAccountId = nil
        viewModels.account.detailPhase = .loading
        viewModels.account.isPresentingForm = false
        viewModels.account.pendingDeleteSummary = nil
        viewModels.account.isPresentingPrivacyAISettings = false

        viewModels.transaction.isPresentingForm = false
        viewModels.transaction.isPresentingScreenshotBookkeeping = false
        viewModels.transaction.editingItem = nil
        viewModels.transaction.pendingDeleteItem = nil

        viewModels.ai.resetConversationTransientState()
        viewModels.screenshot.prepareForPresentation()
        viewModels.debtScanner.prepareForPresentation()
    }

    static func reloadPresentation(_ viewModels: ViewModels) async {
        await viewModels.home.load()
        await viewModels.transaction.load()
        await viewModels.debt.load()
        await viewModels.account.load()
        await viewModels.ai.reloadConsent()
        await viewModels.privacyAISettings.load()
        await viewModels.screenshot.loadAccounts()
    }
}
