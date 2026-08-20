import Foundation

public protocol DebtManaging: Sendable {
    func create(_ input: CreateDebtInput, userId: UUID) async throws -> Debt
    func update(_ input: UpdateDebtInput, userId: UUID) async throws -> Debt
    func delete(debtId: UUID, userId: UUID) async throws
    func recordRepayment(_ input: RecordDebtRepaymentInput, userId: UUID) async throws -> Debt
}

public protocol DebtDetailProviding: Sendable {
    func loadDetail(debtId: UUID, userId: UUID) async throws -> DebtDetailSnapshot
}
