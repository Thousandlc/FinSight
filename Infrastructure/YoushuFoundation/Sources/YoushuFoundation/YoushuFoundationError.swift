import Foundation

public enum YoushuFoundationError: Error, Sendable, Equatable {
    case currencyMismatch(lhs: String, rhs: String)
    case invalidAmount
}
