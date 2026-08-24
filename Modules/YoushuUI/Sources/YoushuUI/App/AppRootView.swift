import SwiftUI
import YoushuDesignSystem
import YoushuDomain

public struct AppRootView: View {
    private let dependencies: AppDependencies

    @State private var homeViewModel: HomeViewModel
    @State private var transactionViewModel: TransactionViewModel
    @State private var screenshotViewModel: ScreenshotBookkeepingViewModel
    @State private var debtViewModel: DebtViewModel
    @State private var debtScannerViewModel: DebtScannerViewModel
    @State private var accountViewModel: AccountViewModel
    @State private var aiViewModel: AIAssistantViewModel
    @State private var dataBackupViewModel: DataBackupViewModel
    @State private var privacyAISettingsViewModel: PrivacyAISettingsViewModel
    @State private var bootstrapError: String?
    @State private var isBootstrapping = true

    public init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        let homeVM = dependencies.makeHomeViewModel()
        let aiVM = dependencies.makeAIViewModel()
        let accountVM = dependencies.makeAccountViewModel(
            onDataChanged: {
                await homeVM.load()
            }
        )
        let privacyAISettingsVM = dependencies.makePrivacyAISettingsViewModel {
            await aiVM.reloadConsent()
            await homeVM.load()
        }
        let transactionVM = dependencies.makeTransactionViewModel(onDataChanged: {
            await homeVM.load()
            await accountVM.load()
        })
        let screenshotVM = dependencies.makeScreenshotBookkeepingViewModel(
            onSaved: {
                await transactionVM.load()
                await homeVM.load()
                await accountVM.load()
            },
            onViewExistingTransaction: { transactionId in
                await transactionVM.openTransactionForEditing(transactionId: transactionId)
            }
        )
        let debtVM = dependencies.makeDebtViewModel(onDataChanged: {
            await homeVM.load()
            await accountVM.load()
        })
        let debtScannerVM = dependencies.makeDebtScannerViewModel(
            onCompleted: {
                await debtVM.load()
                await homeVM.load()
            },
            onViewExistingDebt: { debtId in
                await debtVM.openDebtDetail(debtId: debtId)
            }
        )
        let refreshViewModels = ApplicationRestoreRefresh.ViewModels(
            home: homeVM,
            transaction: transactionVM,
            screenshot: screenshotVM,
            debt: debtVM,
            debtScanner: debtScannerVM,
            account: accountVM,
            ai: aiVM,
            privacyAISettings: privacyAISettingsVM
        )
        let dataBackupVM = dependencies.makeDataBackupViewModel {
            try await ApplicationRestoreRefresh.perform(
                dependencies: dependencies,
                viewModels: refreshViewModels
            )
        }
        privacyAISettingsVM.applicationWipeReset = {
            try await ApplicationPrivacyWipeReset.perform(
                dependencies: dependencies,
                viewModels: refreshViewModels
            )
        }
        _homeViewModel = State(initialValue: homeVM)
        _accountViewModel = State(initialValue: accountVM)
        _transactionViewModel = State(initialValue: transactionVM)
        _screenshotViewModel = State(initialValue: screenshotVM)
        _debtViewModel = State(initialValue: debtVM)
        _debtScannerViewModel = State(initialValue: debtScannerVM)
        _aiViewModel = State(initialValue: aiVM)
        _dataBackupViewModel = State(initialValue: dataBackupVM)
        _privacyAISettingsViewModel = State(initialValue: privacyAISettingsVM)
    }

    public var body: some View {
        Group {
            if isBootstrapping {
                YSLoadingState(message: "正在初始化…")
            } else if let bootstrapError {
                YSErrorState(message: bootstrapError) {
                    Task { await bootstrap() }
                }
            } else {
                @Bindable var session = dependencies.session
                MainTabView(
                    homeViewModel: homeViewModel,
                    transactionViewModel: transactionViewModel,
                    screenshotViewModel: screenshotViewModel,
                    debtViewModel: debtViewModel,
                    debtScannerViewModel: debtScannerViewModel,
                    accountViewModel: accountViewModel,
                    aiViewModel: aiViewModel,
                    dataBackupViewModel: dataBackupViewModel,
                    privacyAISettingsViewModel: privacyAISettingsViewModel
                )
                .id(session.applicationDataRevision)
            }
        }
        .background(YSColor.Fallback.background)
        .task { await bootstrap() }
    }

    @MainActor
    private func bootstrap() async {
        isBootstrapping = true
        bootstrapError = nil
        do {
            try await dependencies.bootstrap()
            isBootstrapping = false
        } catch {
            bootstrapError = error.localizedDescription
            isBootstrapping = false
        }
    }
}
