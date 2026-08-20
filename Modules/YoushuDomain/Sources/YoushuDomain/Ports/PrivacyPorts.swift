import Foundation

public protocol AIDataConsentRepository: Sendable {
    func upsert(_ consent: AIDataConsent) async throws
    func fetch(userId: UUID) async throws -> AIDataConsent?
    func delete(userId: UUID) async throws
}

public protocol AIRecognitionRecordRepository: Sendable {
    func upsert(_ record: AIRecognitionRecord) async throws
    func fetch(id: UUID) async throws -> AIRecognitionRecord?
    func fetchAll(userId: UUID) async throws -> [AIRecognitionRecord]
    func delete(id: UUID) async throws
    func deleteAll(userId: UUID) async throws
}

public protocol MediaArtifactRepository: Sendable {
    func upsert(_ artifact: MediaArtifact) async throws
    func fetch(id: String) async throws -> MediaArtifact?
    func fetchAll(userId: UUID) async throws -> [MediaArtifact]
    func delete(id: String) async throws
    func deleteAll(userId: UUID) async throws
}

/// 原图二进制存储。默认实现可不落盘。
public protocol MediaBinaryStoring: Sendable {
    func save(imageId: String, userId: UUID, data: Data) async throws -> String?
    func load(imageId: String, userId: UUID) async throws -> Data?
    func delete(imageId: String, userId: UUID) async throws
    func deleteAll(userId: UUID) async throws
}

/// API Token 等密钥存储。禁止写入普通日志或 Snapshot JSON。
public protocol SecureTokenStoring: Sendable {
    func save(token: String, account: String) throws
    func load(account: String) throws -> String?
    func delete(account: String) throws
}
