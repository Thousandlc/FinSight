import SwiftUI
import YoushuDesignSystem
import YoushuDomain
import YoushuUI
import YoushuUIPreviewMocks

#Preview("首页 · 有数据") {
    HomeView(viewModel: PreviewAppFactory.homeViewModel(state: .content(PreviewMockData.homeOverview)))
}

#Preview("首页 · 正常现金流") {
    HomeView(viewModel: PreviewAppFactory.homeViewModel(state: .content(PreviewMockData.homeOverview)))
}

#Preview("首页 · 风险现金流") {
    HomeView(viewModel: PreviewAppFactory.homeViewModel(state: .content(PreviewMockData.homeOverviewWithRisk)))
}

#Preview("首页 · 数据不足") {
    HomeView(viewModel: PreviewAppFactory.homeViewModel(state: .content(PreviewMockData.homeOverviewInsufficientData)))
}

#Preview("首页 · 无现金流预测") {
    HomeView(viewModel: PreviewAppFactory.homeViewModel(state: .content(PreviewMockData.homeOverviewEmptyCashFlow)))
}

#Preview("账单 · 有数据") {
    TransactionView(
        viewModel: PreviewAppFactory.transactionViewModel(state: .content(PreviewMockData.transactions)),
        screenshotViewModel: PreviewAppFactory.screenshotViewModel()
    )
}

#Preview("账户 · 有数据") {
    AccountListView(
        viewModel: PreviewAppFactory.accountViewModel(state: .content(PreviewMockData.accountList)),
        dataBackupViewModel: PreviewAppFactory.dataBackupViewModel(),
        privacyAISettingsViewModel: PreviewAppFactory.privacyAISettingsViewModel()
    )
}

#Preview("账户 · 空状态") {
    AccountListView(
        viewModel: PreviewAppFactory.accountViewModel(state: .empty(AccountViewModel.emptyConfig)),
        dataBackupViewModel: PreviewAppFactory.dataBackupViewModel(),
        privacyAISettingsViewModel: PreviewAppFactory.privacyAISettingsViewModel()
    )
}

#Preview("隐私与 AI") {
    NavigationStack {
        PrivacyAISettingsView(viewModel: PreviewAppFactory.privacyAISettingsViewModel())
    }
}

#Preview("AI 助手 · 未授权") {
    AIAssistantView(viewModel: PreviewAppFactory.aiViewModel())
}

#Preview("AI 助手 · 已授权") {
    AIAssistantView(
        viewModel: PreviewAppFactory.aiViewModel(
            state: .content(PreviewMockData.aiAssistantWithPlainAnswer),
            consentAuthorized: true
        )
    )
}

#Preview("AI 助手 · 结构化回答") {
    AIAssistantView(
        viewModel: PreviewAppFactory.aiViewModel(
            state: .content(PreviewMockData.aiAssistantWithStructuredAnswer),
            consentAuthorized: true
        )
    )
}

#Preview("AI 回答 · 纯文本") {
    AssistantAnswerPreviewShell(
        presentation: PreviewMockData.assistantPresentation(from: PreviewMockData.assistantAnswerPlain())
    )
}

#Preview("AI 回答 · 关键数据") {
    AssistantAnswerPreviewShell(
        presentation: PreviewMockData.assistantPresentation(from: PreviewMockData.assistantAnswerWithKeyFacts())
    )
}

#Preview("AI 回答 · 注意") {
    AssistantAnswerPreviewShell(
        presentation: PreviewMockData.assistantPresentation(from: PreviewMockData.assistantAnswerWithWarning(severity: .warning))
    )
}

#Preview("AI 回答 · 风险") {
    AssistantAnswerPreviewShell(
        presentation: PreviewMockData.assistantPresentation(from: PreviewMockData.assistantAnswerWithWarning(severity: .risk))
    )
}

#Preview("AI 回答 · 操作") {
    AssistantAnswerPreviewShell(
        presentation: PreviewMockData.assistantPresentation(from: PreviewMockData.assistantAnswerWithActions())
    )
}

#Preview("AI 回答 · 完整结构化") {
    AssistantAnswerPreviewShell(
        presentation: PreviewMockData.assistantPresentation(from: PreviewMockData.assistantAnswerFullStructured())
    )
}

#Preview("AI 回答 · 空结构化") {
    AssistantAnswerPreviewShell(
        presentation: PreviewMockData.assistantPresentation(from: PreviewMockData.assistantAnswerPlain())
    )
}

#Preview("AI 助手 · 暂不使用") {
    AIAssistantView(viewModel: PreviewAppFactory.aiViewModel(consentDeclined: true))
}

#Preview("Tab · 完整壳") {
    MainTabView(
        homeViewModel: PreviewAppFactory.homeViewModel(state: .content(PreviewMockData.homeOverview)),
        transactionViewModel: PreviewAppFactory.transactionViewModel(state: .empty(TransactionViewModel.emptyConfig)),
        screenshotViewModel: PreviewAppFactory.screenshotViewModel(),
        debtViewModel: PreviewAppFactory.debtViewModel(state: .empty(DebtViewModel.emptyConfig)),
        debtScannerViewModel: PreviewAppFactory.debtScannerViewModel(),
        accountViewModel: PreviewAppFactory.accountViewModel(state: .content(PreviewMockData.accountList)),
        aiViewModel: PreviewAppFactory.aiViewModel(state: .empty(AIAssistantViewModel.emptyConfig)),
        dataBackupViewModel: PreviewAppFactory.dataBackupViewModel(),
        privacyAISettingsViewModel: PreviewAppFactory.privacyAISettingsViewModel()
    )
}

#Preview("Tab · 深色模式") {
    MainTabView(
        homeViewModel: PreviewAppFactory.homeViewModel(state: .content(PreviewMockData.homeOverview)),
        transactionViewModel: PreviewAppFactory.transactionViewModel(),
        screenshotViewModel: PreviewAppFactory.screenshotViewModel(),
        debtViewModel: PreviewAppFactory.debtViewModel(),
        debtScannerViewModel: PreviewAppFactory.debtScannerViewModel(),
        accountViewModel: PreviewAppFactory.accountViewModel(),
        aiViewModel: PreviewAppFactory.aiViewModel(),
        dataBackupViewModel: PreviewAppFactory.dataBackupViewModel(),
        privacyAISettingsViewModel: PreviewAppFactory.privacyAISettingsViewModel()
    )
    .preferredColorScheme(.dark)
}

private struct AssistantAnswerPreviewShell: View {
    let presentation: AssistantAnswerPresentation

    var body: some View {
        NavigationStack {
            ScrollView {
                AssistantAnswerCardView(presentation: presentation)
                    .padding(YSSpacing.md)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(YSColor.Fallback.background)
            .navigationTitle("AI 回答预览")
        }
    }
}
