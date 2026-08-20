import Foundation

/// 用户数据删除编排。失败时抛出 PrivacyError，不泄漏内部细节。
public struct PrivacyDataService: Sendable {
    private let users: any UserRepository
    private let transactions: any TransactionRepository
    private let debts: any DebtRepository
    private let debtEvents: any DebtEventRepository
    private let accounts: any AccountRepository
    private let recognitionRecords: any AIRecognitionRecordRepository
    private let consents: any AIDataConsentRepository
    private let media: MediaLifecycleService
    private let transactionManager: (any TransactionManaging)?
    private let debtManager: (any DebtManaging)?

    public init(
        users: any UserRepository,
        transactions: any TransactionRepository,
        debts: any DebtRepository,
        debtEvents: any DebtEventRepository,
        accounts: any AccountRepository,
        recognitionRecords: any AIRecognitionRecordRepository,
        consents: any AIDataConsentRepository,
        media: MediaLifecycleService,
        transactionManager: (any TransactionManaging)? = nil,
        debtManager: (any DebtManaging)? = nil
    ) {
        self.users = users
        self.transactions = transactions
        self.debts = debts
        self.debtEvents = debtEvents
        self.accounts = accounts
        self.recognitionRecords = recognitionRecords
        self.consents = consents
        self.media = media
        self.transactionManager = transactionManager
        self.debtManager = debtManager
    }

    public func deleteTransaction(id: UUID, userId: UUID) async throws {
        do {
            if let manager = transactionManager {
                try await manager.delete(transactionId: id, userId: userId)
            } else {
                guard let tx = try await transactions.fetch(id: id), tx.userId == userId else {
                    throw DomainError.notFound(entity: "Transaction", id: id)
                }
                try await transactions.delete(id: id)
            }
        } catch let error as DomainError {
            throw error
        } catch {
            throw PrivacyError.deletionFailed("transaction")
        }
    }

    public func deleteDebt(id: UUID, userId: UUID) async throws {
        do {
            if let manager = debtManager {
                try await manager.delete(debtId: id, userId: userId)
            } else {
                guard let debt = try await debts.fetch(id: id), debt.userId == userId else {
                    throw DomainError.notFound(entity: "Debt", id: id)
                }
                try await debts.delete(id: id)
            }
        } catch let error as DomainError {
            throw error
        } catch {
            throw PrivacyError.deletionFailed("debt")
        }
    }

    public func deleteBillImage(imageId: String, userId: UUID) async throws {
        try await media.deleteImage(imageId: imageId, userId: userId)
        let records = try await recognitionRecords.fetchAll(userId: userId)
        for record in records where record.sourceImageId == imageId {
            try? await recognitionRecords.delete(id: record.id)
        }
    }

    public func deleteAIRecognitionRecord(id: UUID, userId: UUID) async throws {
        guard let record = try await recognitionRecords.fetch(id: id), record.userId == userId else {
            throw DomainError.notFound(entity: "AIRecognitionRecord", id: id)
        }
        if let imageId = record.sourceImageId {
            try? await media.deleteImage(imageId: imageId, userId: userId)
        }
        do {
            try await recognitionRecords.delete(id: id)
        } catch {
            throw PrivacyError.deletionFailed("recognition")
        }
    }

    public func deleteAllAIRecognitionRecords(userId: UUID) async throws {
        let records = try await recognitionRecords.fetchAll(userId: userId)
        for record in records {
            if let imageId = record.sourceImageId {
                try? await media.deleteImage(imageId: imageId, userId: userId)
            }
        }
        try await recognitionRecords.deleteAll(userId: userId)
    }

    /// 删除该用户全部本地账本与隐私相关数据（不可恢复）。
    public func wipeAllUserData(userId: UUID) async throws {
        do {
            try await media.deleteAll(userId: userId)
            try await recognitionRecords.deleteAll(userId: userId)
            try await consents.delete(userId: userId)
            try await users.delete(id: userId)
        } catch {
            throw PrivacyError.deletionFailed("wipe")
        }
    }
}
