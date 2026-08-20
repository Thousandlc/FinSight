#if canImport(SwiftData)
import Foundation
import SwiftData
import YoushuDomain

/// Future SwiftData mapping layer. Not used by the MVP JSON store.
/// Kept so the iOS app can migrate without reshaping Domain entities.

@Model
public final class SDUser {
    @Attribute(.unique) public var id: UUID
    public var displayName: String
    public var preferredCurrency: String
    public var debtInventoryEstablishmentRaw: String
    public var debtInventoryEstablishmentSourceRaw: String?
    public var debtInventoryEstablishedAt: Date?
    public var debtImportInProgress: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID,
        displayName: String,
        preferredCurrency: String,
        debtInventoryEstablishmentRaw: String = DebtInventoryEstablishmentState.unestablished.rawValue,
        debtInventoryEstablishmentSourceRaw: String? = nil,
        debtInventoryEstablishedAt: Date? = nil,
        debtImportInProgress: Bool = false,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.displayName = displayName
        self.preferredCurrency = preferredCurrency
        self.debtInventoryEstablishmentRaw = debtInventoryEstablishmentRaw
        self.debtInventoryEstablishmentSourceRaw = debtInventoryEstablishmentSourceRaw
        self.debtInventoryEstablishedAt = debtInventoryEstablishedAt
        self.debtImportInProgress = debtImportInProgress
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
public final class SDAccount {
    @Attribute(.unique) public var id: UUID
    public var userId: UUID
    public var name: String
    public var typeRaw: String
    public var currencyCode: String
    public var openingAmount: Decimal
    public var institutionName: String?
    public var isArchived: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID,
        userId: UUID,
        name: String,
        typeRaw: String,
        currencyCode: String,
        openingAmount: Decimal,
        institutionName: String?,
        isArchived: Bool,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.typeRaw = typeRaw
        self.currencyCode = currencyCode
        self.openingAmount = openingAmount
        self.institutionName = institutionName
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
public final class SDTransaction {
    @Attribute(.unique) public var id: UUID
    public var userId: UUID
    public var accountId: UUID
    public var amount: Decimal
    public var currencyCode: String
    public var date: Date
    public var merchant: String?
    public var category: String?
    public var transactionTypeRaw: String
    public var note: String?
    public var tags: [String]
    public var sourceImageId: String?
    public var relatedDebtId: UUID?
    public var recognitionConfidence: Double?
    public var sourceRaw: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID,
        userId: UUID,
        accountId: UUID,
        amount: Decimal,
        currencyCode: String,
        date: Date,
        merchant: String?,
        category: String?,
        transactionTypeRaw: String,
        note: String?,
        tags: [String],
        sourceImageId: String?,
        relatedDebtId: UUID?,
        recognitionConfidence: Double?,
        sourceRaw: String,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.userId = userId
        self.accountId = accountId
        self.amount = amount
        self.currencyCode = currencyCode
        self.date = date
        self.merchant = merchant
        self.category = category
        self.transactionTypeRaw = transactionTypeRaw
        self.note = note
        self.tags = tags
        self.sourceImageId = sourceImageId
        self.relatedDebtId = relatedDebtId
        self.recognitionConfidence = recognitionConfidence
        self.sourceRaw = sourceRaw
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@Model
public final class SDDebt {
    @Attribute(.unique) public var id: UUID
    public var userId: UUID
    public var lender: String?
    public var productName: String?
    public var debtTypeRaw: String
    public var outstandingBalance: Decimal?
    public var currencyCode: String
    public var statusRaw: String
    public var sourceRaw: String
    public var profileCompleteness: Double
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID,
        userId: UUID,
        lender: String?,
        productName: String?,
        debtTypeRaw: String,
        outstandingBalance: Decimal?,
        currencyCode: String,
        statusRaw: String,
        sourceRaw: String,
        profileCompleteness: Double,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.userId = userId
        self.lender = lender
        self.productName = productName
        self.debtTypeRaw = debtTypeRaw
        self.outstandingBalance = outstandingBalance
        self.currencyCode = currencyCode
        self.statusRaw = statusRaw
        self.sourceRaw = sourceRaw
        self.profileCompleteness = profileCompleteness
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
#else
/// Marker so the file is never an empty compilation unit on non-Apple hosts.
enum SwiftDataModelsUnavailable: Sendable {}
#endif
