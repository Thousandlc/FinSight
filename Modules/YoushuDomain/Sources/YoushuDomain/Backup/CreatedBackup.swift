import Foundation

/// Completed encrypted Backup Format v1 artifact returned to callers.
///
/// Carries no passphrase, derived key, salt, nonce, plaintext payload, or raw store snapshot.
public struct CreatedBackup: Sendable, Equatable {
    public let data: Data
    public let suggestedFilename: String
    public let createdAt: Date
    public let formatVersion: Int
    public let sourceStoreSchemaVersion: Int
    public let sourceAppVersion: String?

    public init(
        data: Data,
        suggestedFilename: String,
        createdAt: Date,
        formatVersion: Int,
        sourceStoreSchemaVersion: Int,
        sourceAppVersion: String? = nil
    ) {
        self.data = data
        self.suggestedFilename = suggestedFilename
        self.createdAt = createdAt
        self.formatVersion = formatVersion
        self.sourceStoreSchemaVersion = sourceStoreSchemaVersion
        self.sourceAppVersion = sourceAppVersion
    }
}
