import Foundation

/// 默认不落盘的原图存储（数据最小化）。
public struct NoPersistMediaBinaryStore: MediaBinaryStoring {
    public init() {}

    public func save(imageId: String, userId: UUID, data: Data) async throws -> String? {
        // 即使调用方请求 retain，本实现仍拒绝持久化二进制，仅返回 nil 路径。
        _ = (imageId, userId, data)
        return nil
    }

    public func load(imageId: String, userId: UUID) async throws -> Data? {
        _ = (imageId, userId)
        return nil
    }

    public func delete(imageId: String, userId: UUID) async throws {
        _ = (imageId, userId)
    }

    public func deleteAll(userId: UUID) async throws {
        _ = userId
    }
}

/// 可选的本地目录原图存储（仅当用户明确 retainOriginalImages 时使用）。
public actor DirectoryMediaBinaryStore: MediaBinaryStoring {
    private let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    public var rootDirectory: URL { rootURL }

    public func save(imageId: String, userId: UUID, data: Data) async throws -> String? {
        let dir = userDirectory(userId: userId)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        Self.applyExcludedFromBackupResource(to: dir)
        let file = dir.appendingPathComponent(sanitize(imageId))
        try Self.writeProtected(data: data, to: file)
        Self.applyExcludedFromBackupResource(to: file)
        return "\(userId.uuidString)/\(sanitize(imageId))"
    }

    public func load(imageId: String, userId: UUID) async throws -> Data? {
        let file = fileURL(imageId: imageId, userId: userId)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try Data(contentsOf: file)
    }

    public func delete(imageId: String, userId: UUID) async throws {
        let file = fileURL(imageId: imageId, userId: userId)
        if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
    }

    public func deleteAll(userId: UUID) async throws {
        let dir = userDirectory(userId: userId)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
    }

    public func fileURL(imageId: String, userId: UUID) -> URL {
        userDirectory(userId: userId).appendingPathComponent(sanitize(imageId))
    }

    private func userDirectory(userId: UUID) -> URL {
        rootURL.appendingPathComponent(userId.uuidString, isDirectory: true)
    }

    private func sanitize(_ id: String) -> String {
        id.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
    }

    private static func writeProtected(data: Data, to file: URL) throws {
        #if os(iOS)
        try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: file, options: [.atomic])
        #endif
    }

    private static func applyExcludedFromBackupResource(to url: URL) {
        #if os(iOS) || os(macOS)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try? mutableURL.setResourceValues(values)
        #endif
    }
}

/// 内存 Token 存储（测试 / 无 Keychain 环境）。禁止写入日志。
public final class InMemorySecureTokenStore: SecureTokenStoring, @unchecked Sendable {
    private var values: [String: String] = [:]
    private let lock = NSLock()

    public init() {}

    public func save(token: String, account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values[account] = token
    }

    public func load(account: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[account]
    }

    public func delete(account: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values.removeValue(forKey: account)
    }
}
