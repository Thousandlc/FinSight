import Foundation
import YoushuFoundation

public struct User: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var displayName: String
    public var preferredCurrency: String
    public var debtInventoryEstablishment: DebtInventoryEstablishmentState
    public var debtInventoryEstablishmentSource: DebtInventoryEstablishmentSource?
    public var debtInventoryEstablishedAt: Date?
    public var debtImportInProgress: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        displayName: String,
        preferredCurrency: String = "CNY",
        debtInventoryEstablishment: DebtInventoryEstablishmentState = .unestablished,
        debtInventoryEstablishmentSource: DebtInventoryEstablishmentSource? = nil,
        debtInventoryEstablishedAt: Date? = nil,
        debtImportInProgress: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.preferredCurrency = preferredCurrency.uppercased()
        self.debtInventoryEstablishment = debtInventoryEstablishment
        self.debtInventoryEstablishmentSource = debtInventoryEstablishmentSource
        self.debtInventoryEstablishedAt = debtInventoryEstablishedAt
        self.debtImportInProgress = debtImportInProgress
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, displayName, preferredCurrency
        case debtInventoryEstablishment, debtInventoryEstablishmentSource
        case debtInventoryEstablishedAt, debtImportInProgress
        case createdAt, updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        preferredCurrency = try container.decodeIfPresent(String.self, forKey: .preferredCurrency) ?? "CNY"
        debtInventoryEstablishment = try container.decodeIfPresent(
            DebtInventoryEstablishmentState.self,
            forKey: .debtInventoryEstablishment
        ) ?? .unestablished
        debtInventoryEstablishmentSource = try container.decodeIfPresent(
            DebtInventoryEstablishmentSource.self,
            forKey: .debtInventoryEstablishmentSource
        )
        debtInventoryEstablishedAt = try container.decodeIfPresent(Date.self, forKey: .debtInventoryEstablishedAt)
        debtImportInProgress = try container.decodeIfPresent(Bool.self, forKey: .debtImportInProgress) ?? false
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}
