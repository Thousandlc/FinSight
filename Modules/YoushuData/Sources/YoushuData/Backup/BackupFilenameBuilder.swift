import Foundation

/// Builds safe presentation filenames for encrypted backup files.
///
/// Filename semantics are not part of backup compatibility; the envelope contents are authoritative.
enum BackupFilenameBuilder {
    static func suggestedFilename(createdAt: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let stamp = formatter.string(from: createdAt)
        return "FinSight-Backup-\(stamp).\(FinSightBackupEnvelopeV1.suggestedFileExtension)"
    }
}
