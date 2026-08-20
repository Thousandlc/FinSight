import SwiftUI

public struct YSCard<Content: View>: View {
    private let padding: CGFloat
    @ViewBuilder private var content: () -> Content

    public init(padding: CGFloat = YSSpacing.md, @ViewBuilder content: @escaping () -> Content) {
        self.padding = padding
        self.content = content
    }

    public var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(YSColor.Fallback.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: YSRadius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: YSRadius.md, style: .continuous)
                    .strokeBorder(YSColor.Fallback.separator.opacity(0.35), lineWidth: 0.5)
            }
    }
}

public struct YSMetricCard: View {
    public let title: String
    public let value: String
    public let subtitle: String?
    public let accent: Color

    public init(title: String, value: String, subtitle: String? = nil, accent: Color = YSColor.Fallback.textPrimary) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.accent = accent
    }

    public var body: some View {
        YSCard {
            VStack(alignment: .leading, spacing: YSSpacing.xs) {
                Text(title)
                    .font(YSTypography.caption)
                    .foregroundStyle(YSColor.Fallback.textSecondary)
                Text(value)
                    .font(YSTypography.amountMedium)
                    .foregroundStyle(accent)
                if let subtitle {
                    Text(subtitle)
                        .font(YSTypography.caption2)
                        .foregroundStyle(YSColor.Fallback.textTertiary)
                }
            }
        }
    }
}
