import Foundation

/// Semantic validation failures for decoded portable backup payloads.
///
/// Cases use fixed entity/field labels only — never passphrase material, UUID values,
/// or untrusted financial content from the backup file.
public enum BackupPayloadValidationError: Error, Equatable, Sendable {
    case unsupportedPayloadFormat(found: Int, supported: Int)
    case duplicateEntityId(entityType: String)
    case missingRequiredOwner(entityType: String)
    case invalidReference(field: String)
    case crossUserReference(field: String)
}
