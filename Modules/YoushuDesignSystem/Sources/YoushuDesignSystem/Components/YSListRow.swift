import SwiftUI

public struct YSListRow: View {
    private let title: String
    private let subtitle: String?
    private let trailing: String?
    private let icon: String?

    public init(title: String, subtitle: String? = nil, trailing: String? = nil, icon: String? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
        self.icon = icon
    }

    public var body: some View {
        HStack(spacing: YSSpacing.sm) {
            if let icon {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(YSColor.Fallback.brandPrimary)
                    .frame(width: 28, height: 28)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(YSTypography.body)
                    .foregroundStyle(YSColor.Fallback.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(YSTypography.caption)
                        .foregroundStyle(YSColor.Fallback.textSecondary)
                }
            }
            Spacer(minLength: YSSpacing.sm)
            if let trailing {
                Text(trailing)
                    .font(YSTypography.amountSmall)
                    .foregroundStyle(YSColor.Fallback.textSecondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(YSColor.Fallback.textTertiary)
        }
        .padding(.vertical, YSSpacing.sm)
        .padding(.horizontal, YSSpacing.md)
    }
}

public struct YSListSection<Content: View>: View {
    private let title: String?
    @ViewBuilder private var content: () -> Content

    public init(title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: YSSpacing.xs) {
            if let title {
                Text(title)
                    .font(YSTypography.caption)
                    .foregroundStyle(YSColor.Fallback.textSecondary)
                    .padding(.horizontal, YSSpacing.xxs)
            }
            VStack(spacing: 0) {
                content()
            }
            .background(YSColor.Fallback.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: YSRadius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: YSRadius.md, style: .continuous)
                    .strokeBorder(YSColor.Fallback.separator.opacity(0.35), lineWidth: 0.5)
            }
        }
    }
}
