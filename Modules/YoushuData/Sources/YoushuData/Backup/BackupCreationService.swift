import Foundation
import YoushuDomain

/// Runtime metadata supplied when creating a backup.
///
/// `sourceAppVersion` is optional until the app composition layer injects it; this type deliberately
/// avoids UIKit/SwiftUI dependencies.
public struct BackupCreationMetadata: Sendable, Equatable {
    public var createdAt: Date
    public var sourceAppVersion: String?

    public init(createdAt: Date = Date(), sourceAppVersion: String? = nil) {
        self.createdAt = createdAt
        self.sourceAppVersion = sourceAppVersion
    }
}

/// Creates one encrypted portable Backup Format v1 file from the current local store.
///
/// Flow: actor-isolated `YoushuStore.currentSnapshot()` → `BackupSnapshotMapper` → `BackupCodec`.
/// Never serializes the raw store snapshot as the portable backup contract.
public struct BackupCreationService: BackupCreating, Sendable {
    private let store: YoushuStore
    private let metadataProvider: @Sendable () -> BackupCreationMetadata

    public init(
        store: YoushuStore,
        metadataProvider: @escaping @Sendable () -> BackupCreationMetadata = { BackupCreationMetadata() }
    ) {
        self.store = store
        self.metadataProvider = metadataProvider
    }

    public func createBackup(passphrase: String) async throws -> CreatedBackup {
        let creationMetadata = metadataProvider()
        let snapshot = await store.currentSnapshot()
        let payload = BackupSnapshotMapper.makePayload(
            from: snapshot,
            createdAt: creationMetadata.createdAt,
            sourceAppVersion: creationMetadata.sourceAppVersion
        )
        let encryptedData = try BackupCodec.encode(payload: payload, passphrase: passphrase)
        return CreatedBackup(
            data: encryptedData,
            suggestedFilename: BackupFilenameBuilder.suggestedFilename(createdAt: creationMetadata.createdAt),
            createdAt: creationMetadata.createdAt,
            formatVersion: BackupPayloadV1.formatVersion,
            sourceStoreSchemaVersion: snapshot.schemaVersion,
            sourceAppVersion: creationMetadata.sourceAppVersion
        )
    }
}
