import SwiftUI

/// 知数设计系统色彩。克制、专业，避免互联网金融广告风。
public enum YSColor {
    // Brand
    public static let brandPrimary = Color("YSBrandPrimary", bundle: .module)
    public static let brandSecondary = Color("YSBrandSecondary", bundle: .module)

    // Surfaces
    public static let background = Color("YSBackground", bundle: .module)
    public static let surface = Color("YSSurface", bundle: .module)
    public static let surfaceElevated = Color("YSSurfaceElevated", bundle: .module)

    // Text
    public static let textPrimary = Color("YSTextPrimary", bundle: .module)
    public static let textSecondary = Color("YSTextSecondary", bundle: .module)
    public static let textTertiary = Color("YSTextTertiary", bundle: .module)

    // Semantic
    public static let income = Color("YSIncome", bundle: .module)
    public static let expense = Color("YSExpense", bundle: .module)
    public static let debt = Color("YSDebt", bundle: .module)
    public static let warning = Color("YSWarning", bundle: .module)
    public static let positive = Color("YSPositive", bundle: .module)

    // Chrome
    public static let separator = Color("YSSeparator", bundle: .module)
    public static let tabBar = Color("YSTabBar", bundle: .module)

    /// Fallback palette when asset catalog colors are unavailable (e.g. some previews).
    public enum Fallback {
        public static let brandPrimary = Color(red: 0.12, green: 0.35, blue: 0.42)
        public static let brandSecondary = Color(red: 0.20, green: 0.48, blue: 0.55)
        public static let background = Color(uiColor: .systemGroupedBackground)
        public static let surface = Color(uiColor: .secondarySystemGroupedBackground)
        public static let surfaceElevated = Color(uiColor: .systemBackground)
        public static let textPrimary = Color(uiColor: .label)
        public static let textSecondary = Color(uiColor: .secondaryLabel)
        public static let textTertiary = Color(uiColor: .tertiaryLabel)
        public static let income = Color(red: 0.18, green: 0.52, blue: 0.42)
        public static let expense = Color(red: 0.35, green: 0.38, blue: 0.42)
        public static let debt = Color(red: 0.72, green: 0.48, blue: 0.22)
        public static let warning = Color(red: 0.78, green: 0.45, blue: 0.18)
        public static let positive = Color(red: 0.22, green: 0.55, blue: 0.48)
        public static let separator = Color(uiColor: .separator)
        public static let tabBar = Color(uiColor: .systemBackground)
    }
}

public extension Color {
    static func ys(_ name: String, fallback: Color) -> Color {
        Color(name, bundle: .module)
    }
}
