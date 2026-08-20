import Foundation
import YoushuDomain

/// Shared decode → validate → candidate pipeline for preflight and restore commit.
enum BackupRestoreValidationPipeline {
    static func decodeValidateAndBuild(
        data: Data,
        passphrase: String
    ) throws -> (payload: BackupPayloadV1, candidate: YoushuSnapshot) {
        let payload = try BackupCodec.decode(backupData: data, passphrase: passphrase)
        try BackupPayloadV1Validator.validate(payload)
        let candidate = BackupRestoreCandidateBuilder.build(from: payload)
        try BackupRestoreCandidateValidator.validate(candidate)
        return (payload, candidate)
    }
}
