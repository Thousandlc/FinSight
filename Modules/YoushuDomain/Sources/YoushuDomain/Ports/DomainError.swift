import Foundation

public enum DomainError: Error, Equatable, Sendable {
    case notFound(entity: String, id: UUID)
    case invalidRelation(String)
    case validationFailed(String)
    case userMismatch
}
