import SwiftUI

public enum YSBadgeTone {
    case neutral
    case positive
    case warning
    case debt
    case brand
}

public struct YSBadge: View {
    private let text: String
    private let tone: YSBadgeTone

    public init(_ text: String, tone: YSBadgeTone = .neutral) {
        self.text = text
        self.tone = tone
    }

    public var body: some View {
        Text(text)
            .font(YSTypography.caption2.weight(.medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, YSSpacing.xs)
            .padding(.vertical, YSSpacing.xxs)
            .background(background)
            .clipShape(Capsule())
    }

    private var foreground: Color {
        switch tone {
        case .neutral: YSColor.Fallback.textSecondary
        case .positive: YSColor.Fallback.positive
        case .warning: YSColor.Fallback.warning
        case .debt: YSColor.Fallback.debt
        case .brand: YSColor.Fallback.brandPrimary
        }
    }

    private var background: Color {
        foreground.opacity(0.12)
    }
}
