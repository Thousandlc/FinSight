import Foundation

/// Import capability covered by confirmed-import provenance (ADR-036).
public enum ConfirmedImportCapability: String, Sendable, Equatable, Codable, CaseIterable {
    case transactionScreenshot
    case debtScan
}

/// Typed reference to one confirmed financial fact produced by an import operation.
public enum ConfirmedImportEntityReference: Sendable, Equatable, Hashable, Codable {
    case transaction(UUID)
    case debt(UUID)
}

/// Local import/provenance lifecycle metadata — not a financial fact (ADR-036).
public struct ConfirmedImportProvenance: Identifiable, Sendable, Equatable, Hashable, Codable {
    public let id: UUID
    public var userId: UUID
    public var capability: ConfirmedImportCapability
    /// Per-input full-file fingerprints; multiplicity is meaningful (not a set).
    public var sourceFingerprints: [ImportSourceFingerprint]
    public var operationFingerprint: ImportOperationFingerprint
    /// Confirmed entities; logical set semantics (no duplicate ids).
    public var confirmedEntityReferences: [ConfirmedImportEntityReference]
    public var confirmedAt: Date

    public init(
        id: UUID = UUID(),
        userId: UUID,
        capability: ConfirmedImportCapability,
        sourceFingerprints: [ImportSourceFingerprint],
        confirmedEntityReferences: [ConfirmedImportEntityReference],
        confirmedAt: Date = Date()
    ) throws {
        try Self.validate(
            capability: capability,
            sourceFingerprints: sourceFingerprints,
            confirmedEntityReferences: confirmedEntityReferences
        )
        self.id = id
        self.userId = userId
        self.capability = capability
        self.sourceFingerprints = sourceFingerprints
        self.operationFingerprint = ImportFingerprintCanonicalizer.operationFingerprint(
            capability: capability,
            sourceFingerprints: sourceFingerprints
        )
        self.confirmedEntityReferences = Self.normalizedEntityReferences(confirmedEntityReferences)
        self.confirmedAt = confirmedAt
    }

    /// Adds one confirmed entity reference without duplication.
    public func addingConfirmedEntity(_ reference: ConfirmedImportEntityReference) throws -> ConfirmedImportProvenance {
        try Self.validateEntityReference(reference, for: capability)
        guard !confirmedEntityReferences.contains(reference) else { return self }
        var copy = self
        copy.confirmedEntityReferences.append(reference)
        return copy
    }

    /// Removes one confirmed entity reference. Returns nil when no references remain.
    public func removingConfirmedEntity(_ reference: ConfirmedImportEntityReference) -> ConfirmedImportProvenance? {
        let remaining = confirmedEntityReferences.filter { $0 != reference }
        guard !remaining.isEmpty else { return nil }
        var copy = self
        copy.confirmedEntityReferences = remaining
        return copy
    }

    private static func validate(
        capability: ConfirmedImportCapability,
        sourceFingerprints: [ImportSourceFingerprint],
        confirmedEntityReferences: [ConfirmedImportEntityReference]
    ) throws {
        guard !sourceFingerprints.isEmpty else {
            throw DomainError.validationFailed("Confirmed import requires at least one source fingerprint")
        }
        guard !confirmedEntityReferences.isEmpty else {
            throw DomainError.validationFailed("Confirmed import requires at least one confirmed entity reference")
        }
        switch capability {
        case .transactionScreenshot:
            guard sourceFingerprints.count == 1 else {
                throw DomainError.validationFailed("Transaction screenshot provenance requires exactly one source fingerprint")
            }
        case .debtScan:
            break
        }
        for reference in confirmedEntityReferences {
            try validateEntityReference(reference, for: capability)
        }
    }

    private static func validateEntityReference(
        _ reference: ConfirmedImportEntityReference,
        for capability: ConfirmedImportCapability
    ) throws {
        switch (capability, reference) {
        case (.transactionScreenshot, .transaction):
            return
        case (.debtScan, .debt):
            return
        case (.transactionScreenshot, .debt):
            throw DomainError.validationFailed("Transaction screenshot provenance cannot reference Debt")
        case (.debtScan, .transaction):
            throw DomainError.validationFailed("Debt scan provenance cannot reference Transaction")
        }
    }

    private static func normalizedEntityReferences(
        _ references: [ConfirmedImportEntityReference]
    ) -> [ConfirmedImportEntityReference] {
        var seen = Set<ConfirmedImportEntityReference>()
        var ordered: [ConfirmedImportEntityReference] = []
        for reference in references where seen.insert(reference).inserted {
            ordered.append(reference)
        }
        return ordered
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case userId
        case capability
        case sourceFingerprints
        case operationFingerprint
        case confirmedEntityReferences
        case confirmedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(UUID.self, forKey: .id)
        let userId = try container.decode(UUID.self, forKey: .userId)
        let capability = try container.decode(ConfirmedImportCapability.self, forKey: .capability)
        let sourceFingerprints = try container.decode([ImportSourceFingerprint].self, forKey: .sourceFingerprints)
        let storedOperationFingerprint = try container.decode(
            ImportOperationFingerprint.self,
            forKey: .operationFingerprint
        )
        let confirmedEntityReferences = try container.decode(
            [ConfirmedImportEntityReference].self,
            forKey: .confirmedEntityReferences
        )
        let confirmedAt = try container.decode(Date.self, forKey: .confirmedAt)
        try Self.validate(
            capability: capability,
            sourceFingerprints: sourceFingerprints,
            confirmedEntityReferences: confirmedEntityReferences
        )
        let computedOperationFingerprint = ImportFingerprintCanonicalizer.operationFingerprint(
            capability: capability,
            sourceFingerprints: sourceFingerprints
        )
        guard storedOperationFingerprint == computedOperationFingerprint else {
            throw DomainError.validationFailed("Stored operation fingerprint does not match canonical input identity")
        }
        self.id = id
        self.userId = userId
        self.capability = capability
        self.sourceFingerprints = sourceFingerprints
        self.operationFingerprint = storedOperationFingerprint
        self.confirmedEntityReferences = Self.normalizedEntityReferences(confirmedEntityReferences)
        self.confirmedAt = confirmedAt
    }
}
