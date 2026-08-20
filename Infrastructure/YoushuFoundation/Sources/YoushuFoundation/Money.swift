import Foundation

/// Monetary amount. Prefer this over Double for all financial math.
public struct Money: Hashable, Codable, Sendable, Comparable {
    public let amount: Decimal
    public let currencyCode: String

    public init(amount: Decimal, currencyCode: String = "CNY") {
        self.amount = amount
        self.currencyCode = currencyCode.uppercased()
    }

    public init(minorUnits: Int64, currencyCode: String = "CNY", scale: Int = 2) {
        var value = Decimal(minorUnits)
        value /= pow(10, scale)
        self.init(amount: value, currencyCode: currencyCode)
    }

    public static let zeroCNY = Money(amount: 0, currencyCode: "CNY")

    public static func < (lhs: Money, rhs: Money) -> Bool {
        precondition(lhs.currencyCode == rhs.currencyCode, "Cannot compare different currencies")
        return lhs.amount < rhs.amount
    }

    public static func + (lhs: Money, rhs: Money) -> Money {
        precondition(lhs.currencyCode == rhs.currencyCode, "Currency mismatch")
        return Money(amount: lhs.amount + rhs.amount, currencyCode: lhs.currencyCode)
    }

    public static func - (lhs: Money, rhs: Money) -> Money {
        precondition(lhs.currencyCode == rhs.currencyCode, "Currency mismatch")
        return Money(amount: lhs.amount - rhs.amount, currencyCode: lhs.currencyCode)
    }

    public func matchesCurrency(_ other: Money) -> Bool {
        currencyCode == other.currencyCode
    }
}

private func pow(_ base: Decimal, _ exp: Int) -> Decimal {
    var result: Decimal = 1
    if exp >= 0 {
        for _ in 0..<exp { result *= base }
    } else {
        for _ in 0..<(-exp) { result /= base }
    }
    return result
}
