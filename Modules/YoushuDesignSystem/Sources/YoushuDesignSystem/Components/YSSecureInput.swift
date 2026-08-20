import SwiftUI

public struct YSSecureInput: View {
    @Binding private var text: String
    private let title: String
    private let placeholder: String

    public init(
        title: String,
        text: Binding<String>,
        placeholder: String = ""
    ) {
        self.title = title
        self._text = text
        self.placeholder = placeholder
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: YSSpacing.xxs) {
            Text(title)
                .font(YSTypography.caption)
                .foregroundStyle(YSColor.Fallback.textSecondary)
            SecureField(placeholder, text: $text)
                .textContentType(.password)
                .font(YSTypography.body)
                .padding(.horizontal, YSSpacing.sm)
                .padding(.vertical, YSSpacing.sm)
                .background(YSColor.Fallback.surface)
                .clipShape(RoundedRectangle(cornerRadius: YSRadius.sm, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: YSRadius.sm, style: .continuous)
                        .strokeBorder(YSColor.Fallback.separator.opacity(0.5), lineWidth: 0.5)
                }
        }
        .accessibilityElement(children: .combine)
    }
}
