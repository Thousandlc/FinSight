import SwiftUI

public enum YSButtonStyleKind {
    case primary
    case secondary
    case ghost
}

public struct YSButton: View {
    private let title: String
    private let kind: YSButtonStyleKind
    private let isLoading: Bool
    private let action: () -> Void

    public init(
        _ title: String,
        kind: YSButtonStyleKind = .primary,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.kind = kind
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: YSSpacing.xs) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(title)
                    .font(YSTypography.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, YSSpacing.sm)
            .padding(.horizontal, YSSpacing.md)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .clipShape(RoundedRectangle(cornerRadius: YSRadius.sm, style: .continuous))
            .overlay {
                if kind == .secondary || kind == .ghost {
                    RoundedRectangle(cornerRadius: YSRadius.sm, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    private var backgroundColor: Color {
        switch kind {
        case .primary: YSColor.Fallback.brandPrimary
        case .secondary: YSColor.Fallback.surfaceElevated
        case .ghost: .clear
        }
    }

    private var foregroundColor: Color {
        switch kind {
        case .primary: .white
        case .secondary, .ghost: YSColor.Fallback.brandPrimary
        }
    }

    private var borderColor: Color {
        YSColor.Fallback.separator.opacity(kind == .ghost ? 0 : 0.6)
    }
}
