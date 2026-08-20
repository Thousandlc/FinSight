import Foundation

/// Application-layer orchestration executed after a successful restore persistence commit.
///
/// Data layer owns store replacement; this controller resynchronizes session identity and
/// reloads presentation surfaces so cached ViewModel state cannot show pre-restore data.
@MainActor
public struct ApplicationRestoreRefreshController {
    public struct Actions {
        public var resyncSession: () async throws -> Void
        public var bumpDataRevision: () -> Void
        public var resetTransientState: () -> Void
        public var reloadPresentation: () async -> Void

        public init(
            resyncSession: @escaping () async throws -> Void,
            bumpDataRevision: @escaping () -> Void,
            resetTransientState: @escaping () -> Void,
            reloadPresentation: @escaping () async -> Void
        ) {
            self.resyncSession = resyncSession
            self.bumpDataRevision = bumpDataRevision
            self.resetTransientState = resetTransientState
            self.reloadPresentation = reloadPresentation
        }
    }

    private let actions: Actions

    public init(actions: Actions) {
        self.actions = actions
    }

    public func perform() async throws {
        try await actions.resyncSession()
        actions.bumpDataRevision()
        actions.resetTransientState()
        await actions.reloadPresentation()
    }
}
