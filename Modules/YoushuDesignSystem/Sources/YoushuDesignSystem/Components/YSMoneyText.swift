import SwiftUI
import YoushuFoundation

public enum YSMoneyFormatter {
    public static func string(for money: Money, showSign: Bool = false) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = ","
        let amountString = formatter.string(from: money.amount as NSDecimalNumber) ?? "\(money.amount)"
        let symbol = currencySymbol(for: money.currencyCode)
        if showSign && money.amount > 0 {
            return "+\(symbol)\(amountString)"
        }
        return "\(symbol)\(amountString)"
    }

    public static func currencySymbol(for code: String) -> String {
        switch code.uppercased() {
        case "CNY": return "¥"
        case "USD": return "$"
        case "EUR": return "€"
        case "GBP": return "£"
        case "JPY": return "¥"
        default: return code.uppercased() + " "
        }
    }
}

public struct YSMoneyText: View {
    private let money: Money
    private let style: Font
    private let color: Color
    private let showSign: Bool

    public init(
        _ money: Money,
        style: Font = YSTypography.amountMedium,
        color: Color = YSColor.Fallback.textPrimary,
        showSign: Bool = false
    ) {
        self.money = money
        self.style = style
        self.color = color
        self.showSign = showSign
    }

    public var body: some View {
        Text(YSMoneyFormatter.string(for: money, showSign: showSign))
            .font(style)
            .foregroundStyle(color)
            .monospacedDigit()
    }
}
