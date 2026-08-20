import Foundation

/// Production use-case for creating one encrypted portable Backup Format v1 file.
public protocol BackupCreating: Sendable {
    func createBackup(passphrase: String) async throws -> CreatedBackup
}
