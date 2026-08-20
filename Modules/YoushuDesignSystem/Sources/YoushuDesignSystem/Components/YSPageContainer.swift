import SwiftUI

public enum YSPagePhase<Content: Equatable & Sendable>: Equatable, Sendable {
    case loading
    case empty(YSEmptyStateConfig)
    case error(String)
    case content(Content)
}

public struct YSPageContainer<ContentModel: Equatable & Sendable, ContentView: View>: View {
    private let title: String
    private let phase: YSPagePhase<ContentModel>
    private let onRetry: () -> Void
    @ViewBuilder private var content: (ContentModel) -> ContentView

    public init(
        title: String,
        phase: YSPagePhase<ContentModel>,
        onRetry: @escaping () -> Void,
        @ViewBuilder content: @escaping (ContentModel) -> ContentView
    ) {
        self.title = title
        self.phase = phase
        self.onRetry = onRetry
        self.content = content
    }

    public var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .loading:
                    YSLoadingState()
                case .empty(let config):
                    YSEmptyState(config: config, action: onRetry)
                case .error(let message):
                    YSErrorState(message: message, retry: onRetry)
                case .content(let model):
                    content(model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(YSColor.Fallback.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
        }
    }
}
