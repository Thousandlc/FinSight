import SwiftUI
import YoushuDesignSystem
import YoushuDomain

public struct AIAssistantView: View {
    @Bindable private var viewModel: AIAssistantViewModel
    private let onNavigateToTab: ((MainTab) -> Void)?

    public init(
        viewModel: AIAssistantViewModel,
        onNavigateToTab: ((MainTab) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.onNavigateToTab = onNavigateToTab
    }

    public var body: some View {
        Group {
            switch viewModel.consentState {
            case .loading:
                assistantShell { YSLoadingState() }
            case .unauthorized:
                assistantShell {
                    AIAssistantConsentView(
                        isAccepting: viewModel.isAcceptingConsent,
                        onAccept: { Task { await viewModel.acceptConsent() } },
                        onDecline: { viewModel.declineConsent() }
                    )
                }
            case .declined:
                assistantShell {
                    AIAssistantDeclinedView {
                        viewModel.showConsentPrompt()
                    }
                }
            case .authorized:
                assistantContent
            case .error(let message):
                assistantShell {
                    YSErrorState(message: message) {
                        Task { await viewModel.load() }
                    }
                }
            }
        }
        .task { await viewModel.load() }
    }

    private var assistantContent: some View {
        YSPageContainer(title: "AI 财务助手", phase: viewModel.phase, onRetry: retry) { snapshot in
            ScrollView {
                VStack(alignment: .leading, spacing: YSSpacing.md) {
                    askSection
                    if let error = viewModel.askError {
                        Text(error)
                            .font(YSTypography.caption)
                            .foregroundStyle(YSColor.Fallback.expense)
                    }
                    if let answer = snapshot.lastAnswer {
                        AssistantAnswerCardView(
                            presentation: AssistantAnswerPresentationMapper.make(from: answer),
                            onNavigateToTab: onNavigateToTab
                        )
                    }
                    suggestedQuestions(snapshot.suggestedQuestions)
                    insightsSection(snapshot.recentInsights)
                }
                .padding(.horizontal, YSSpacing.md)
                .padding(.vertical, YSSpacing.sm)
            }
        }
    }

    private func assistantShell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        NavigationStack {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(YSColor.Fallback.background)
                .navigationTitle("AI 财务助手")
                .navigationBarTitleDisplayMode(.large)
        }
    }

    private var askSection: some View {
        YSCard {
            VStack(alignment: .leading, spacing: YSSpacing.sm) {
                Text("财务决策入口")
                    .font(YSTypography.headline)
                Text(PrivacyAIDisclosureCopy.assistantAskFootnote)
                    .font(YSTypography.caption2)
                    .foregroundStyle(YSColor.Fallback.textTertiary)
                HStack(spacing: YSSpacing.sm) {
                    TextField("例如：我能不能买3000元的东西？", text: $viewModel.questionText)
                        .textFieldStyle(.roundedBorder)
                    Button("提问") {
                        Task { await viewModel.ask() }
                    }
                    .disabled(viewModel.isAsking || viewModel.questionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Button("刷新洞察") {
                    Task { await viewModel.refreshInsights() }
                }
                .font(YSTypography.caption)
            }
        }
    }

    private func suggestedQuestions(_ questions: [String]) -> some View {
        VStack(alignment: .leading, spacing: YSSpacing.xs) {
            Text("常见问题")
                .font(YSTypography.callout.weight(.medium))
            FlowQuestions(questions: questions) { q in
                Task { await viewModel.ask(q) }
            }
        }
    }

    private func insightsSection(_ insights: [FinancialInsight]) -> some View {
        VStack(alignment: .leading, spacing: YSSpacing.sm) {
            Text("主动洞察")
                .font(YSTypography.headline)
            if insights.isEmpty {
                Text("暂无洞察。记录交易与债务后可刷新生成。")
                    .font(YSTypography.callout)
                    .foregroundStyle(YSColor.Fallback.textSecondary)
            } else {
                ForEach(insights, id: \.id) { insight in
                    YSCard {
                        VStack(alignment: .leading, spacing: YSSpacing.xs) {
                            HStack {
                                Text(insight.title)
                                    .font(YSTypography.headline)
                                Spacer()
                                YSBadge(insight.type.rawValue, tone: .brand)
                            }
                            Text(insight.body)
                                .font(YSTypography.callout)
                                .foregroundStyle(YSColor.Fallback.textSecondary)
                            Text(insight.generatedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(YSTypography.caption2)
                                .foregroundStyle(YSColor.Fallback.textTertiary)
                        }
                    }
                }
            }
        }
    }

    private func retry() {
        Task { await viewModel.load() }
    }
}

private struct FlowQuestions: View {
    let questions: [String]
    let onTap: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: YSSpacing.xs) {
            ForEach(questions, id: \.self) { q in
                Button(q) { onTap(q) }
                    .font(YSTypography.caption)
                    .buttonStyle(.bordered)
            }
        }
    }
}
