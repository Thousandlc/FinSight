import Foundation
import YoushuFoundation

/// 图片生命周期与数据最小化策略。
public enum MediaLifecyclePolicy {
    /// 默认：不永久保存原图；AI 完成后立即清除二进制与 ephemeral 元数据。
    public static let defaultRetainOriginalImages = false
    public static let ephemeralTTL: TimeInterval = 3600

    public static func makeImageId(for data: Data) -> String {
        let hash = stableHash(data)
        return "img-\(data.count)-\(hash)"
    }

    public static func contentHash(for data: Data) -> String {
        stableHash(data)
    }

    private static func stableHash(_ data: Data) -> String {
        // 非加密哈希，仅用于去重/引用；不作为安全摘要。
        var hash: UInt64 = 5381
        for byte in data.prefix(4096) {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        hash = hash &+ UInt64(data.count)
        return String(hash, radix: 16)
    }
}

/// 媒体注册与清理。原图默认不落盘。
public struct MediaLifecycleService: Sendable {
    private let artifacts: any MediaArtifactRepository
    private let binaries: any MediaBinaryStoring

    public init(
        artifacts: any MediaArtifactRepository,
        binaries: any MediaBinaryStoring
    ) {
        self.artifacts = artifacts
        self.binaries = binaries
    }

    /// 注册媒体。仅当 `retainOriginal == true` 时尝试保存二进制。
    public func register(
        data: Data,
        userId: UUID,
        kind: AIRecognitionKind,
        retainOriginal: Bool
    ) async throws -> MediaArtifact {
        let id = MediaLifecyclePolicy.makeImageId(for: data)
        let retention: MediaRetentionPolicy = retainOriginal ? .userRetained : .untilProcessed
        var relativePath: String?
        if retainOriginal {
            relativePath = try await binaries.save(imageId: id, userId: userId, data: data)
        }
        let artifact = MediaArtifact(
            id: id,
            userId: userId,
            kind: kind,
            byteSize: data.count,
            contentHash: MediaLifecyclePolicy.contentHash(for: data),
            retention: retention,
            relativePath: relativePath,
            purgeAfter: retainOriginal ? nil : Date().addingTimeInterval(MediaLifecyclePolicy.ephemeralTTL)
        )
        try await artifacts.upsert(artifact)
        return artifact
    }

    public func markProcessedAndMaybePurge(imageId: String, userId: UUID) async throws {
        guard var artifact = try await artifacts.fetch(id: imageId), artifact.userId == userId else {
            return
        }
        if artifact.retention == .userRetained {
            return
        }
        try await binaries.delete(imageId: imageId, userId: userId)
        artifact.relativePath = nil
        artifact.retention = .ephemeral
        artifact.purgeAfter = Date()
        try await artifacts.upsert(artifact)
        try await artifacts.delete(id: imageId)
    }

    public func deleteImage(imageId: String, userId: UUID) async throws {
        guard let artifact = try await artifacts.fetch(id: imageId), artifact.userId == userId else {
            throw PrivacyError.mediaUnavailable
        }
        do {
            try await binaries.delete(imageId: imageId, userId: userId)
            try await artifacts.delete(id: imageId)
        } catch {
            throw PrivacyError.deletionFailed("image")
        }
    }

    public func purgeExpired(userId: UUID, now: Date = Date()) async throws {
        let list = try await artifacts.fetchAll(userId: userId)
        for artifact in list {
            if let purgeAfter = artifact.purgeAfter, purgeAfter <= now {
                try? await binaries.delete(imageId: artifact.id, userId: userId)
                try? await artifacts.delete(id: artifact.id)
            }
        }
    }

    public func deleteAll(userId: UUID) async throws {
        try await binaries.deleteAll(userId: userId)
        try await artifacts.deleteAll(userId: userId)
    }
}
