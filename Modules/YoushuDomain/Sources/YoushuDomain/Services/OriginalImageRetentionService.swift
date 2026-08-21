import Foundation

/// Orchestrates original-image retention preference transitions with media lifecycle cleanup.
/// `AIDataConsentService` remains the canonical persisted consent owner.
public struct OriginalImageRetentionService: Sendable {
    private let consentService: AIDataConsentService
    private let media: MediaLifecycleService

    public init(consentService: AIDataConsentService, media: MediaLifecycleService) {
        self.consentService = consentService
        self.media = media
    }

    /// Disables retention preference first, then purges previously user-retained originals.
    /// Preference remains `false` even if cleanup partially fails.
    public func disableRetention(userId: UUID) async throws -> Int {
        _ = try await consentService.setRetainOriginalImages(false, userId: userId)
        return try await media.purgeUserRetainedOriginals(userId: userId)
    }
}
