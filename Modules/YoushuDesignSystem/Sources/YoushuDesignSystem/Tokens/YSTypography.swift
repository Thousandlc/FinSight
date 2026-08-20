import SwiftUI

public enum YSTypography {
    public static let largeTitle = Font.system(.largeTitle, design: .default).weight(.semibold)
    public static let title = Font.system(.title2, design: .default).weight(.semibold)
    public static let title3 = Font.system(.title3, design: .default).weight(.medium)
    public static let headline = Font.system(.headline, design: .default).weight(.semibold)
    public static let body = Font.system(.body, design: .default)
    public static let callout = Font.system(.callout, design: .default)
    public static let caption = Font.system(.caption, design: .default)
    public static let caption2 = Font.system(.caption2, design: .default)

    /// 金额展示：等宽数字，便于对齐。
    public static let amountLarge = Font.system(.title, design: .rounded).weight(.semibold).monospacedDigit()
    public static let amountMedium = Font.system(.title3, design: .rounded).weight(.medium).monospacedDigit()
    public static let amountSmall = Font.system(.subheadline, design: .rounded).weight(.medium).monospacedDigit()
}

public enum YSSpacing {
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 8
    public static let sm: CGFloat = 12
    public static let md: CGFloat = 16
    public static let lg: CGFloat = 20
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
}

public enum YSRadius {
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let pill: CGFloat = 999
}
