import Foundation
import Testing
import YoushuData
import YoushuDomain

@Suite("Backup import file reader")
struct BackupImportFileReaderTests {
    private func writeTemporaryFile(named name: String, contents: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url, options: .atomic)
        return url
    }

    @Test("valid encrypted file within limit returns exact data")
    func validFileReturnsExactData() throws {
        let expected = Data([0x01, 0x02, 0x03, 0x04])
        let url = try writeTemporaryFile(named: "valid-backup.finsightbackup", contents: expected)
        defer { try? FileManager.default.removeItem(at: url) }

        let reader = BackupImportFileReader()
        let data = try reader.readBoundedData(from: url)

        #expect(data == expected)
    }

    @Test("file larger than limit is rejected before unbounded allocation")
    func oversizedFileRejected() throws {
        let limit = BackupFormatV1Policy.maximumBackupFileByteCount
        let oversizedCount = limit + 1
        let url = try writeTemporaryFile(
            named: "oversized-backup.finsightbackup",
            contents: Data(repeating: 0xAB, count: oversizedCount)
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let reader = BackupImportFileReader()
        #expect(throws: BackupImportFileReaderError.fileTooLarge(byteCount: oversizedCount, limit: limit)) {
            try reader.readBoundedData(from: url)
        }
    }

    @Test("oversized reported size rejects before reading")
    func oversizedReportedSizeRejected() throws {
        let limit = 1024
        let url = URL(fileURLWithPath: "/tmp/unused-backup.finsightbackup")
        let reader = BackupImportFileReader(
            maximumByteCount: limit,
            fileSizeProvider: { _ in limit + 1 }
        )

        #expect(throws: BackupImportFileReaderError.fileTooLarge(byteCount: limit + 1, limit: limit)) {
            try reader.readBoundedData(from: url)
        }
    }

    @Test("empty file is rejected")
    func emptyFileRejected() throws {
        let url = try writeTemporaryFile(named: "empty-backup.finsightbackup", contents: Data())
        defer { try? FileManager.default.removeItem(at: url) }

        let reader = BackupImportFileReader()
        #expect(throws: BackupImportFileReaderError.emptyFile) {
            try reader.readBoundedData(from: url)
        }
    }

    @Test("security scoped access is released after read")
    func securityScopedCleanup() throws {
        let expected = Data([0x10, 0x20])
        let url = try writeTemporaryFile(named: "scoped-backup.finsightbackup", contents: expected)
        defer { try? FileManager.default.removeItem(at: url) }

        let tracker = SecurityScopeTracker()
        let reader = BackupImportFileReader(
            beginSecurityScopedAccess: { _ in
                tracker.begin()
                return true
            },
            endSecurityScopedAccess: { _ in
                tracker.end()
            }
        )

        _ = try reader.readBoundedData(from: url)
        #expect(tracker.began)
        #expect(tracker.ended)
    }

    @Test("read failure maps to safe typed error")
    func missingFileReadFailsSafely() {
        let url = URL(fileURLWithPath: "/nonexistent/path/backup.finsightbackup")
        let reader = BackupImportFileReader()

        #expect(throws: BackupImportFileReaderError.readFailed) {
            try reader.readBoundedData(from: url)
        }
    }
}

private final class SecurityScopeTracker: @unchecked Sendable {
    private(set) var began = false
    private(set) var ended = false

    func begin() { began = true }
    func end() { ended = true }
}
