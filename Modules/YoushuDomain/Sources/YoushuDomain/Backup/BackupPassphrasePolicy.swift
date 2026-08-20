import Foundation

/// Shared Backup v1 passphrase input policy enforced below UI.
///
/// Does not trim, normalize, or apply password-complexity rules beyond non-empty.
public enum BackupPassphrasePolicy {
    /// Rejects empty passphrases before any KDF or encryption work.
    public static func validate(_ passphrase: String) throws {
        guard !passphrase.isEmpty else {
            throw BackupError.invalidPassphrase
        }
    }
}
