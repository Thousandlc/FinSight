import Foundation
import Testing
import YoushuData
import YoushuDomain
import YoushuFoundation

@Suite("Backup payload v1 validator")
struct BackupPayloadV1ValidatorTests {
    private static let userId = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    private static let accountId = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
    private static let debtId = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
    private static let assetId = UUID(uuidString: "00000000-0000-0000-0000-000000000501")!
    private static let goalId = UUID(uuidString: "00000000-0000-0000-0000-000000000601")!
    private static let budgetId = UUID(uuidString: "00000000-0000-0000-0000-000000000701")!
    private static let subscriptionId = UUID(uuidString: "00000000-0000-0000-0000-000000000801")!
    private static let planId = UUID(uuidString: "00000000-0000-0000-0000-000000000901")!
    private static let eventId = UUID(uuidString: "00000000-0000-0000-0000-000000000A01")!
    private static let fixedCreatedAt = Date(timeIntervalSince1970: 1_700_000_000)

    private func basePayload() -> BackupPayloadV1 {
        BackupPayloadV1(
            metadata: BackupPayloadMetadataV1(
                createdAt: Self.fixedCreatedAt,
                sourceStoreSchemaVersion: YoushuSnapshot.currentSchemaVersion
            ),
            financialData: BackupFinancialDataV1(
                users: [
                    BackupUserV1(
                        id: Self.userId,
                        displayName: "Owner",
                        preferredCurrency: "CNY",
                        debtInventoryEstablishment: .unestablished,
                        createdAt: Self.fixedCreatedAt,
                        updatedAt: Self.fixedCreatedAt
                    ),
                ],
                accounts: [
                    Account(id: Self.accountId, userId: Self.userId, name: "Cash", type: .cash),
                ],
                transactions: [],
                assets: [
                    Asset(
                        id: Self.assetId,
                        userId: Self.userId,
                        name: "Fund",
                        type: .cashEquivalent,
                        currentValue: Money(amount: 100, currencyCode: "CNY")
                    ),
                ],
                debts: [
                    Debt(id: Self.debtId, userId: Self.userId, status: .active),
                ],
                debtEvents: [
                    DebtEvent(id: Self.eventId, debtId: Self.debtId, userId: Self.userId, type: .created),
                ],
                repaymentPlans: [
                    RepaymentPlan(
                        id: Self.planId,
                        debtId: Self.debtId,
                        userId: Self.userId,
                        installmentAmount: Money(amount: 10, currencyCode: "CNY"),
                        frequency: .monthly,
                        startDate: Self.fixedCreatedAt
                    ),
                ],
                budgets: [
                    Budget(
                        id: Self.budgetId,
                        userId: Self.userId,
                        name: "Monthly",
                        limit: Money(amount: 100, currencyCode: "CNY")
                    ),
                ],
                goals: [
                    Goal(
                        id: Self.goalId,
                        userId: Self.userId,
                        name: "Save",
                        type: .savings,
                        targetAmount: Money(amount: 100, currencyCode: "CNY")
                    ),
                ],
                subscriptions: [
                    Subscription(
                        id: Self.subscriptionId,
                        userId: Self.userId,
                        name: "Sub",
                        amount: Money(amount: 10, currencyCode: "CNY")
                    ),
                ]
            )
        )
    }

    @Test("valid minimal payload passes validator")
    func validPayload() throws {
        try BackupPayloadV1Validator.validate(basePayload())
    }

    @Test("empty payload passes validator")
    func emptyPayload() throws {
        let payload = BackupPayloadV1(
            metadata: BackupPayloadMetadataV1(
                createdAt: Self.fixedCreatedAt,
                sourceStoreSchemaVersion: 1
            ),
            financialData: BackupFinancialDataV1()
        )
        try BackupPayloadV1Validator.validate(payload)
    }

    @Test("rejects unsupported portable format version in metadata")
    func unsupportedFormatVersion() {
        var payload = basePayload()
        payload.metadata.formatVersion = 2
        #expect(throws: BackupPayloadValidationError.unsupportedPayloadFormat(found: 2, supported: 1)) {
            try BackupPayloadV1Validator.validate(payload)
        }
    }

    @Test("rejects duplicate ids in remaining collections")
    func duplicateRemainingCollections() {
        var payload = basePayload()
        payload.financialData.users.append(
            BackupUserV1(
                id: Self.userId,
                displayName: "Dup",
                preferredCurrency: "CNY",
                debtInventoryEstablishment: .unestablished,
                createdAt: Self.fixedCreatedAt,
                updatedAt: Self.fixedCreatedAt
            )
        )
        #expect(throws: BackupPayloadValidationError.duplicateEntityId(entityType: "User")) {
            try BackupPayloadV1Validator.validate(payload)
        }

        payload = basePayload()
        payload.financialData.assets.append(
            Asset(
                id: Self.assetId,
                userId: Self.userId,
                name: "Dup",
                type: .cashEquivalent,
                currentValue: Money(amount: 1, currencyCode: "CNY")
            )
        )
        #expect(throws: BackupPayloadValidationError.duplicateEntityId(entityType: "Asset")) {
            try BackupPayloadV1Validator.validate(payload)
        }

        payload = basePayload()
        payload.financialData.debtEvents.append(
            DebtEvent(id: Self.eventId, debtId: Self.debtId, userId: Self.userId, type: .repayment)
        )
        #expect(throws: BackupPayloadValidationError.duplicateEntityId(entityType: "DebtEvent")) {
            try BackupPayloadV1Validator.validate(payload)
        }

        payload = basePayload()
        payload.financialData.repaymentPlans.append(
            RepaymentPlan(
                id: Self.planId,
                debtId: Self.debtId,
                userId: Self.userId,
                installmentAmount: Money(amount: 1, currencyCode: "CNY"),
                frequency: .monthly,
                startDate: Self.fixedCreatedAt
            )
        )
        #expect(throws: BackupPayloadValidationError.duplicateEntityId(entityType: "RepaymentPlan")) {
            try BackupPayloadV1Validator.validate(payload)
        }

        payload = basePayload()
        payload.financialData.budgets.append(
            Budget(
                id: Self.budgetId,
                userId: Self.userId,
                name: "Dup",
                limit: Money(amount: 1, currencyCode: "CNY")
            )
        )
        #expect(throws: BackupPayloadValidationError.duplicateEntityId(entityType: "Budget")) {
            try BackupPayloadV1Validator.validate(payload)
        }

        payload = basePayload()
        payload.financialData.goals.append(
            Goal(
                id: Self.goalId,
                userId: Self.userId,
                name: "Dup",
                type: .savings,
                targetAmount: Money(amount: 1, currencyCode: "CNY")
            )
        )
        #expect(throws: BackupPayloadValidationError.duplicateEntityId(entityType: "Goal")) {
            try BackupPayloadV1Validator.validate(payload)
        }

        payload = basePayload()
        payload.financialData.subscriptions.append(
            Subscription(
                id: Self.subscriptionId,
                userId: Self.userId,
                name: "Dup",
                amount: Money(amount: 1, currencyCode: "CNY")
            )
        )
        #expect(throws: BackupPayloadValidationError.duplicateEntityId(entityType: "Subscription")) {
            try BackupPayloadV1Validator.validate(payload)
        }
    }

    @Test("allows optional orphan references not enforced by live store")
    func optionalOrphanReferencesAllowed() throws {
        var payload = basePayload()
        payload.financialData.assets[0].linkedAccountId = UUID()
        payload.financialData.goals[0].relatedDebtId = UUID()
        payload.financialData.subscriptions[0].accountId = UUID()
        payload.financialData.accounts[0].linkedDebtId = UUID()
        payload.financialData.debts[0].linkedAccountId = UUID()
        try BackupPayloadV1Validator.validate(payload)
    }

    @Test("rejects debt event related transaction when missing or cross-user")
    func debtEventRelatedTransactionRules() {
        var payload = basePayload()
        payload.financialData.debtEvents[0].relatedTransactionId = UUID()
        #expect(throws: BackupPayloadValidationError.invalidReference(field: "DebtEvent.relatedTransactionId")) {
            try BackupPayloadV1Validator.validate(payload)
        }

        let otherUserId = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
        let otherAccountId = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
        payload = basePayload()
        payload.financialData.users.append(
            BackupUserV1(
                id: otherUserId,
                displayName: "Other",
                preferredCurrency: "CNY",
                debtInventoryEstablishment: .unestablished,
                createdAt: Self.fixedCreatedAt,
                updatedAt: Self.fixedCreatedAt
            )
        )
        payload.financialData.accounts.append(
            Account(id: otherAccountId, userId: otherUserId, name: "Other Cash", type: .cash)
        )
        let txId = UUID(uuidString: "00000000-0000-0000-0000-000000000401")!
        payload.financialData.transactions = [
            Transaction(
                id: txId,
                userId: otherUserId,
                accountId: otherAccountId,
                amount: Money(amount: 1, currencyCode: "CNY"),
                transactionType: .expense
            ),
        ]
        payload.financialData.debtEvents[0].relatedTransactionId = txId
        #expect(throws: BackupPayloadValidationError.crossUserReference(field: "DebtEvent.relatedTransactionId")) {
            try BackupPayloadV1Validator.validate(payload)
        }
    }

    @Test("does not reject backup solely because sourceStoreSchemaVersion exceeds current store")
    func sourceSchemaProvenanceNotRestoreGate() throws {
        var payload = basePayload()
        payload.metadata.sourceStoreSchemaVersion = YoushuSnapshot.currentSchemaVersion + 10
        try BackupPayloadV1Validator.validate(payload)
    }
}
