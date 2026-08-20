import Foundation

public protocol AccountListProviding: Sendable {
    func loadSnapshot(userId: UUID) async throws -> AccountListSnapshot
    func loadDetail(accountId: UUID, userId: UUID) async throws -> AccountDetailSnapshot
}

public protocol AccountManaging: Sendable {
    func create(_ input: CreateAccountInput, userId: UUID) async throws -> Account
    func update(_ input: UpdateAccountInput, userId: UUID) async throws -> Account
    func delete(accountId: UUID, userId: UUID) async throws
}
