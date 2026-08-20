import Foundation
import YoushuDomain

/// Errors when reading an untrusted external backup file from the Files picker.
public enum BackupImportFileReaderError: Error, Equatable, Sendable {
    case accessDenied
    case readFailed
    case emptyFile
    case fileTooLarge(byteCount: Int, limit: Int)
}

/// Bounded, security-scoped reader for encrypted backup files selected via the system Files UI.
///
/// This boundary sits below SwiftUI and rejects oversize files before uncontrolled allocation.
/// The returned `Data` is the exact encrypted envelope bytes and must be reused for preflight
/// and restore within the same user confirmation flow.
public struct BackupImportFileReader: Sendable {
    public typealias SecurityScopedAccess = @Sendable (URL) -> Bool
    public typealias SecurityScopedRelease = @Sendable (URL) -> Void
    public typealias FileSizeProvider = @Sendable (URL) throws -> Int?

    private let maximumByteCount: Int
    private let beginSecurityScopedAccess: SecurityScopedAccess
    private let endSecurityScopedAccess: SecurityScopedRelease
    private let fileSizeProvider: FileSizeProvider

    public init(
        maximumByteCount: Int = BackupFormatV1Policy.maximumBackupFileByteCount,
        beginSecurityScopedAccess: SecurityScopedAccess? = nil,
        endSecurityScopedAccess: SecurityScopedRelease? = nil,
        fileSizeProvider: FileSizeProvider? = nil
    ) {
        self.maximumByteCount = maximumByteCount
        self.beginSecurityScopedAccess = beginSecurityScopedAccess ?? Self.defaultBeginSecurityScopedAccess
        self.endSecurityScopedAccess = endSecurityScopedAccess ?? Self.defaultEndSecurityScopedAccess
        self.fileSizeProvider = fileSizeProvider ?? Self.defaultFileSizeProvider
    }

    /// Reads encrypted backup bytes from an external file URL with an explicit upper bound.
    public func readBoundedData(from url: URL) throws -> Data {
        let didAccess = beginSecurityScopedAccess(url)
        defer {
            if didAccess {
                endSecurityScopedAccess(url)
            }
        }

        let reportedSize: Int?
        do {
            reportedSize = try fileSizeProvider(url)
        } catch {
            reportedSize = nil
        }

        if let fileSize = reportedSize {
            guard fileSize > 0 else {
                throw BackupImportFileReaderError.emptyFile
            }
            guard fileSize <= maximumByteCount else {
                throw BackupImportFileReaderError.fileTooLarge(
                    byteCount: fileSize,
                    limit: maximumByteCount
                )
            }
        }

        let data: Data
        do {
            data = try readWithUpperBound(from: url)
        } catch let error as BackupImportFileReaderError {
            throw error
        } catch {
            throw BackupImportFileReaderError.readFailed
        }

        guard !data.isEmpty else {
            throw BackupImportFileReaderError.emptyFile
        }
        guard data.count <= maximumByteCount else {
            throw BackupImportFileReaderError.fileTooLarge(
                byteCount: data.count,
                limit: maximumByteCount
            )
        }
        return data
    }

    private func readWithUpperBound(from url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var buffer = Data()
        buffer.reserveCapacity(min(maximumByteCount, 64 * 1024))

        while true {
            let chunk = try handle.read(upToCount: 64 * 1024) ?? Data()
            if chunk.isEmpty {
                break
            }
            if buffer.count + chunk.count > maximumByteCount {
                throw BackupImportFileReaderError.fileTooLarge(
                    byteCount: buffer.count + chunk.count,
                    limit: maximumByteCount
                )
            }
            buffer.append(chunk)
        }
        return buffer
    }

    private static let defaultBeginSecurityScopedAccess: SecurityScopedAccess = { url in
        #if os(iOS) || os(macOS)
        return url.startAccessingSecurityScopedResource()
        #else
        _ = url
        return false
        #endif
    }

    private static let defaultEndSecurityScopedAccess: SecurityScopedRelease = { url in
        #if os(iOS) || os(macOS)
        url.stopAccessingSecurityScopedResource()
        #else
        _ = url
        #endif
    }

    private static let defaultFileSizeProvider: FileSizeProvider = { url in
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .totalFileAllocatedSizeKey])
        if let fileSize = values.fileSize {
            return fileSize
        }
        if let allocatedSize = values.totalFileAllocatedSize {
            return allocatedSize
        }
        return nil
    }
}
