import SwiftUI
import YoushuDesignSystem

public enum MainTab: String, CaseIterable, Identifiable {
    case home
    case transactions
    case debts
    case assets
    case ai

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .home: "首页"
        case .transactions: "账单"
        case .debts: "债务"
        case .assets: "账户"
        case .ai: "AI"
        }
    }

    public var icon: String {
        switch self {
        case .home: "house"
        case .transactions: "list.bullet.rectangle"
        case .debts: "creditcard"
        case .assets: "wallet.pass"
        case .ai: "text.bubble"
        }
    }
}

public struct MainTabView: View {
    @State private var selection: MainTab = .home

    private let homeViewModel: HomeViewModel
    private let transactionViewModel: TransactionViewModel
    private let screenshotViewModel: ScreenshotBookkeepingViewModel
    private let debtViewModel: DebtViewModel
    private let debtScannerViewModel: DebtScannerViewModel
    private let accountViewModel: AccountViewModel
    private let aiViewModel: AIAssistantViewModel
    private let dataBackupViewModel: DataBackupViewModel

    public init(
        homeViewModel: HomeViewModel,
        transactionViewModel: TransactionViewModel,
        screenshotViewModel: ScreenshotBookkeepingViewModel,
        debtViewModel: DebtViewModel,
        debtScannerViewModel: DebtScannerViewModel,
        accountViewModel: AccountViewModel,
        aiViewModel: AIAssistantViewModel,
        dataBackupViewModel: DataBackupViewModel
    ) {
        self.homeViewModel = homeViewModel
        self.transactionViewModel = transactionViewModel
        self.screenshotViewModel = screenshotViewModel
        self.debtViewModel = debtViewModel
        self.debtScannerViewModel = debtScannerViewModel
        self.accountViewModel = accountViewModel
        self.aiViewModel = aiViewModel
        self.dataBackupViewModel = dataBackupViewModel
    }

    public var body: some View {
        TabView(selection: $selection) {
            HomeView(viewModel: homeViewModel)
                .tabItem { Label(MainTab.home.title, systemImage: MainTab.home.icon) }
                .tag(MainTab.home)

            TransactionView(
                viewModel: transactionViewModel,
                screenshotViewModel: screenshotViewModel
            )
                .tabItem { Label(MainTab.transactions.title, systemImage: MainTab.transactions.icon) }
                .tag(MainTab.transactions)

            DebtView(viewModel: debtViewModel, scannerViewModel: debtScannerViewModel)
                .tabItem { Label(MainTab.debts.title, systemImage: MainTab.debts.icon) }
                .tag(MainTab.debts)

            AccountListView(
                viewModel: accountViewModel,
                dataBackupViewModel: dataBackupViewModel
            )
                .tabItem { Label(MainTab.assets.title, systemImage: MainTab.assets.icon) }
                .tag(MainTab.assets)

            AIAssistantView(viewModel: aiViewModel) { tab in
                selection = tab
            }
                .tabItem { Label(MainTab.ai.title, systemImage: MainTab.ai.icon) }
                .tag(MainTab.ai)
        }
        .tint(YSColor.Fallback.brandPrimary)
    }
}
