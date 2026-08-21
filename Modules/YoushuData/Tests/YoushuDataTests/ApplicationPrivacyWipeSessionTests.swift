import Foundation
import Testing
import YoushuDomain
@testable import YoushuData

@Suite("Privacy wipe session bootstrap")
@MainActor
struct ApplicationPrivacyWipeSessionTests {
    @Test("H bootstrap after deleting the only user creates a new valid session")
    func bootstrapAfterDeletingSoleUser() async throws {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userA = UUID(uuidString: "00000000-0000-0000-0000-000000000d01")!
        try await container.users.upsert(User(id: userA, displayName: "A"))
        let session = AppSession(users: container.users)
        session.configureForPreview(userId: userA)
        #expect(session.currentUserId == userA)

        try await container.users.delete(id: userA)
        #expect(try await container.users.fetch(id: userA) == nil)

        try await session.bootstrap()
        let newUserId = try #require(session.currentUserId)
        #expect(newUserId != userA)
        #expect(try await container.users.fetch(id: newUserId) != nil)
        #expect(session.isReady)
    }
}
