import Foundation
import Testing
import YoushuDomain

@Suite("Backup user-facing error mapper")
struct BackupUserFacingErrorMapperTests {
    @Test("authentication failure uses ambiguous unlock wording")
    func authenticationFailureMessage() {
        let message = BackupUserFacingErrorMapper.message(for: BackupError.authenticationFailure)
        #expect(message.contains("无法解锁备份"))
        #expect(message.contains("密码可能不正确"))
    }

    @Test("rollback failed maps to critical persistence message")
    func criticalPersistenceMessage() {
        let message = BackupUserFacingErrorMapper.message(for: BackupRestoreError.rollbackFailed)
        #expect(message == BackupUserFacingErrorMapper.criticalPersistenceMessage)
    }

    @Test("commit failure explains data was not replaced")
    func commitFailureMessage() {
        let message = BackupUserFacingErrorMapper.message(for: BackupRestoreError.commitPersistenceFailure)
        #expect(message.contains("未被替换"))
    }

    @Test("backup creation maps backupTooLarge")
    func creationTooLargeMessage() {
        let message = BackupUserFacingErrorMapper.backupCreationMessage(
            for: BackupError.backupTooLarge(byteCount: 100, limit: 50)
        )
        #expect(message.contains("过大"))
    }
}
