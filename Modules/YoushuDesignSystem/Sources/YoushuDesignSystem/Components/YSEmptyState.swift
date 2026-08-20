import SwiftUI

public struct YSEmptyStateConfig: Equatable, Sendable {
    public let icon: String
    public let title: String
    public let message: String
    public let actionTitle: String?

    public init(icon: String, title: String, message: String, actionTitle: String? = nil) {
        self.icon = icon
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
    }
}

public struct YSEmptyState: View {
    private let config: YSEmptyStateConfig
    private let action: (() -> Void)?

    public init(config: YSEmptyStateConfig, action: (() -> Void)? = nil) {
        self.config = config
        self.action = action
    }

    public var body: some View {
        VStack(spacing: YSSpacing.md) {
            Image(systemName: config.icon)
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(YSColor.Fallback.textTertiary)
            Text(config.title)
                .font(YSTypography.headline)
                .foregroundStyle(YSColor.Fallback.textPrimary)
            Text(config.message)
                .font(YSTypography.callout)
                .foregroundStyle(YSColor.Fallback.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, YSSpacing.lg)
            if let actionTitle = config.actionTitle, let action {
                YSButton(actionTitle, kind: .secondary, action: action)
                    .frame(maxWidth: 220)
                    .padding(.top, YSSpacing.xs)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(YSSpacing.xl)
    }
}

public struct YSErrorState: View {
    private let message: String
    private let retryTitle: String
    private let retry: () -> Void

    public init(message: String, retryTitle: String = "重试", retry: @escaping () -> Void) {
        self.message = message
        self.retryTitle = retryTitle
        self.retry = retry
    }

    public var body: some View {
        VStack(spacing: YSSpacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(YSColor.Fallback.warning)
            Text("加载失败")
                .font(YSTypography.headline)
            Text(message)
                .font(YSTypography.callout)
                .foregroundStyle(YSColor.Fallback.textSecondary)
                .multilineTextAlignment(.center)
            YSButton(retryTitle, kind: .secondary, action: retry)
                .frame(maxWidth: 160)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(YSSpacing.xl)
    }
}

public struct YSLoadingState: View {
    private let message: String

    public init(message: String = "加载中…") {
        self.message = message
    }

    public var body: some View {
        VStack(spacing: YSSpacing.md) {
            ProgressView()
            Text(message)
                .font(YSTypography.callout)
                .foregroundStyle(YSColor.Fallback.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
