import Foundation
import Observation
import YoushuDomain

@Observable
@MainActor
public final class AppSession {
    public private(set) var currentUserId: UUID?
    public private(set) var isReady = false
    /// Bumped after restore refresh so composition layers can recreate long-lived views when needed.
    public private(set) var applicationDataRevision: Int = 0

    private let users: any UserRepository

    public init(users: any UserRepository) {
        self.users = users
    }

    public func bootstrap() async throws {
        if let existing = try await users.fetchAll().first {
            currentUserId = existing.id
            isReady = true
            return
        }
        let user = User(displayName: "我")
        try await users.upsert(user)
        currentUserId = user.id
        isReady = true
    }

    /// Re-adopts the first persisted user after a full-replace restore changed user IDs.
    public func resyncCurrentUserFromStore() async throws {
        if let existing = try await users.fetchAll().first {
            currentUserId = existing.id
        } else {
            currentUserId = nil
        }
        isReady = true
    }

    /// Marks that application-facing cached state must be rebuilt after restore.
    public func bumpApplicationDataRevision() {
        applicationDataRevision += 1
    }

    /// Preview / test helper only.
    public func configureForPreview(userId: UUID) {
        currentUserId = userId
        isReady = true
    }
}
