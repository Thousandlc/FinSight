import Foundation

/// Application reset after a successful local-data wipe.
///
/// Distinct from restore: the deleted user identity is gone and must not remain
/// `AppSession.currentUserId`. Canonical `AppDependencies.bootstrap()` creates a
/// new local user when none remain, or adopts the first remaining persisted user.
@MainActor
public enum ApplicationPrivacyWipeReset {
    public static func perform(
        dependencies: AppDependencies,
        viewModels: ApplicationRestoreRefresh.ViewModels
    ) async throws {
        try await dependencies.bootstrap()
        dependencies.session.bumpApplicationDataRevision()
        ApplicationRestoreRefresh.resetTransientState(viewModels)
        viewModels.account.isPresentingPrivacyAISettings = true
        await ApplicationRestoreRefresh.reloadPresentation(viewModels)
    }
}
