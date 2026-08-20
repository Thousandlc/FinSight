import Foundation

/// AI 数据授权门禁：发送前必须检查。
public struct AIDataConsentService: Sendable {
    private let consents: any AIDataConsentRepository

    public init(consents: any AIDataConsentRepository) {
        self.consents = consents
    }

    public func fetchOrDefault(userId: UUID) async throws -> AIDataConsent {
        if let existing = try await consents.fetch(userId: userId) {
            return existing
        }
        return .deniedDefault(userId: userId)
    }

    public func save(_ consent: AIDataConsent) async throws {
        var value = consent
        value.updatedAt = Date()
        try await consents.upsert(value)
    }

    public func requireScreenshotImage(userId: UUID) async throws -> AIDataConsent {
        let consent = try await fetchOrDefault(userId: userId)
        guard consent.allowScreenshotImageToAI else {
            throw PrivacyError.consentRequired("记账截图")
        }
        return consent
    }

    public func requireDebtScanImage(userId: UUID) async throws -> AIDataConsent {
        let consent = try await fetchOrDefault(userId: userId)
        guard consent.allowDebtScanImageToAI else {
            throw PrivacyError.consentRequired("债务账单图片")
        }
        return consent
    }

    public func allowsFinancialContextTransmission(userId: UUID) async throws -> Bool {
        try await fetchOrDefault(userId: userId).allowFinancialContextToAI
    }

    public func requireFinancialContext(userId: UUID) async throws -> AIDataConsent {
        let consent = try await fetchOrDefault(userId: userId)
        guard consent.allowFinancialContextToAI else {
            throw PrivacyError.consentRequired("财务助手 Context")
        }
        return consent
    }

    public func acceptScreenshotPrivacy(userId: UUID) async throws -> AIDataConsent {
        var consent = try await fetchOrDefault(userId: userId)
        consent = consent.grantingScreenshotSession()
        try await save(consent)
        return consent
    }

    public func acceptDebtScanPrivacy(userId: UUID) async throws -> AIDataConsent {
        var consent = try await fetchOrDefault(userId: userId)
        consent = consent.grantingDebtScanSession()
        try await save(consent)
        return consent
    }

    public func acceptAssistantPrivacy(userId: UUID) async throws -> AIDataConsent {
        var consent = try await fetchOrDefault(userId: userId)
        consent = consent.grantingAssistantContext()
        try await save(consent)
        return consent
    }

    public func revokeAssistantPrivacy(userId: UUID) async throws -> AIDataConsent {
        var consent = try await fetchOrDefault(userId: userId)
        consent = consent.revokingAssistantContext()
        try await save(consent)
        return consent
    }
}
