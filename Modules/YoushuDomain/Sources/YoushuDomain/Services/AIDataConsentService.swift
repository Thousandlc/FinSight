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

    // MARK: - Screenshot image consent

    public func acceptScreenshotPrivacy(userId: UUID) async throws -> AIDataConsent {
        try await updateConsent(userId: userId) { $0.allowScreenshotImageToAI = true }
    }

    public func revokeScreenshotPrivacy(userId: UUID) async throws -> AIDataConsent {
        try await updateConsent(userId: userId) { $0.allowScreenshotImageToAI = false }
    }

    // MARK: - Debt scan image consent

    public func acceptDebtScanPrivacy(userId: UUID) async throws -> AIDataConsent {
        try await updateConsent(userId: userId) { $0.allowDebtScanImageToAI = true }
    }

    public func revokeDebtScanPrivacy(userId: UUID) async throws -> AIDataConsent {
        try await updateConsent(userId: userId) { $0.allowDebtScanImageToAI = false }
    }

    // MARK: - Financial context consent

    public func acceptAssistantPrivacy(userId: UUID) async throws -> AIDataConsent {
        try await updateConsent(userId: userId) { $0.allowFinancialContextToAI = true }
    }

    public func revokeAssistantPrivacy(userId: UUID) async throws -> AIDataConsent {
        try await updateConsent(userId: userId) { $0.allowFinancialContextToAI = false }
    }

    // MARK: - Original image retention preference (persisted only; operational retention is separate)

    public func setRetainOriginalImages(_ retain: Bool, userId: UUID) async throws -> AIDataConsent {
        try await updateConsent(userId: userId) { $0.retainOriginalImages = retain }
    }

    // MARK: - Private

    /// Reads latest persisted consent, mutates exactly one logical field (or caller-controlled subset), preserves others.
    private func updateConsent(
        userId: UUID,
        mutate: (inout AIDataConsent) -> Void
    ) async throws -> AIDataConsent {
        var consent = try await fetchOrDefault(userId: userId)
        mutate(&consent)
        try await save(consent)
        return consent
    }
}
