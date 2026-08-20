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

    public func save(imageId: String, userId: UUID, data: Data) async throws -> String? {
        let dir = rootURL.appendingPathComponent(userId.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(sanitize(imageId))
        try data.write(to: file, options: [.atomic])
        return "\(userId.uuidString)/\(sanitize(imageId))"
    }

    public func load(imageId: String, userId: UUID) async throws -> Data? {
        let file = rootURL
            .appendingPathComponent(userId.uuidString, isDirectory: true)
            .appendingPathComponent(sanitize(imageId))
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try Data(contentsOf: file)
    }

    public func delete(imageId: String, userId: UUID) async throws {
        let file = rootURL
            .appendingPathComponent(userId.uuidString, isDirectory: true)
            .appendingPathComponent(sanitize(imageId))
        if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
    }

    public func deleteAll(userId: UUID) async throws {
        let dir = rootURL.appendingPathComponent(userId.uuidString, isDirectory: true)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
    }

    private func sanitize(_ id: String) -> String {
        id.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
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
