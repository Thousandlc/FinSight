import Foundation
import YoushuDomain

public enum PrivacyAISettingField: Equatable, Sendable {
    case screenshot
    case debtScan
    case financialContext
    case retainOriginalImages
}

public enum PrivacyAISettingsPhase: Equatable, Sendable {
    case loading
    case ready
    case error(String)
}

public enum PrivacyWipePhase: Equatable, Sendable {
    case idle
    case confirming
    case deleting
    case failed(String)
    case mediaCleanupIncomplete(String)
}

@Observable
@MainActor
public final class PrivacyAISettingsViewModel {
    public var phase: PrivacyAISettingsPhase = .loading
    public var allowScreenshotImageToAI = false
    public var allowDebtScanImageToAI = false
    public var allowFinancialContextToAI = false
    public var retainOriginalImages = false
    public var actionError: String?
    public var retentionCleanupWarning: String?
    public var mutatingField: PrivacyAISettingField?
    public var wipePhase: PrivacyWipePhase = .idle
    public var wipeStatusMessage: String?
    public var applicationWipeReset: (@MainActor () async throws -> Void)?

    private let consentService: AIDataConsentService
    private let originalImageRetention: OriginalImageRetentionService
    private let privacyData: PrivacyDataService
    private let session: AppSession
    private let onConsentChanged: (@Sendable () async -> Void)?
    private var mutationGeneration = 0
    private var wipeGeneration = 0
    private var pendingMediaCleanupUserId: UUID?

    public init(
        consentService: AIDataConsentService,
        originalImageRetention: OriginalImageRetentionService,
        privacyData: PrivacyDataService,
        session: AppSession,
        onConsentChanged: (@Sendable () async -> Void)? = nil,
        applicationWipeReset: (@MainActor () async throws -> Void)? = nil
    ) {
        self.consentService = consentService
        self.originalImageRetention = originalImageRetention
        self.privacyData = privacyData
        self.session = session
        self.onConsentChanged = onConsentChanged
        self.applicationWipeReset = applicationWipeReset
    }

    public var isWipeBusy: Bool {
        if case .deleting = wipePhase { return true }
        return false
    }

    public var isBusy: Bool {
        mutatingField != nil || phase == .loading || isWipeBusy
    }

    public var showsRetentionCleanupRetry: Bool {
        retentionCleanupWarning != nil && !retainOriginalImages
    }

    public var showsWipeMediaCleanupRetry: Bool {
        if case .mediaCleanupIncomplete = wipePhase { return true }
        return false
    }

    public var wipeFailureMessage: String? {
        switch wipePhase {
        case .failed(let message), .mediaCleanupIncomplete(let message):
            return message
        case .idle, .confirming, .deleting:
            return nil
        }
    }

    public func load() async {
        phase = .loading
        actionError = nil
        await reloadFromStore(showLoading: true)
    }

    public func setScreenshotAIEnabled(_ enabled: Bool) async {
        await mutate(.screenshot) { userId in
            if enabled {
                try await consentService.acceptScreenshotPrivacy(userId: userId)
            } else {
                try await consentService.revokeScreenshotPrivacy(userId: userId)
            }
        }
    }

    public func setDebtScanAIEnabled(_ enabled: Bool) async {
        await mutate(.debtScan) { userId in
            if enabled {
                try await consentService.acceptDebtScanPrivacy(userId: userId)
            } else {
                try await consentService.revokeDebtScanPrivacy(userId: userId)
            }
        }
    }

    public func setFinancialContextAIEnabled(_ enabled: Bool) async {
        await mutate(.financialContext) { userId in
            if enabled {
                try await consentService.acceptAssistantPrivacy(userId: userId)
            } else {
                try await consentService.revokeAssistantPrivacy(userId: userId)
            }
        }
        if actionError == nil {
            await onConsentChanged?()
        }
    }

    public func setRetainOriginalImagesEnabled(_ enabled: Bool) async {
        if enabled {
            await mutate(.retainOriginalImages) { userId in
                try await consentService.setRetainOriginalImages(true, userId: userId)
            }
            if actionError == nil {
                retentionCleanupWarning = nil
            }
            return
        }
        await disableRetention(field: .retainOriginalImages)
    }

    public func retryRetentionCleanup() async {
        await disableRetention(field: .retainOriginalImages)
    }

    public func requestDeleteAllLocalData() {
        guard !isWipeBusy else { return }
        guard mutatingField == nil else { return }
        wipeStatusMessage = nil
        wipePhase = .confirming
    }

    public func cancelDeleteAllLocalData() {
        guard wipePhase == .confirming else { return }
        wipePhase = .idle
    }

    public func confirmDeleteAllLocalData() async {
        guard wipePhase == .confirming else { return }
        guard let userId = session.currentUserId else {
            wipePhase = .failed("尚未完成账户初始化")
            return
        }
        wipePhase = .deleting
        wipeStatusMessage = nil
        wipeGeneration += 1
        let generation = wipeGeneration
        let deletedUserId = userId
        do {
            let result = try await privacyData.wipeAllUserData(userId: deletedUserId)
            guard generation == wipeGeneration else { return }
            if let applicationWipeReset {
                try await applicationWipeReset()
            }
            guard generation == wipeGeneration else { return }
            switch result {
            case .complete:
                pendingMediaCleanupUserId = nil
                wipeStatusMessage = PrivacyAIDisclosureCopy.wipeSuccessMessage
                wipePhase = .idle
            case .mediaCleanupIncomplete:
                pendingMediaCleanupUserId = deletedUserId
                wipeStatusMessage = nil
                wipePhase = .mediaCleanupIncomplete(PrivacyError.mediaCleanupIncomplete.userMessage)
            }
        } catch {
            guard generation == wipeGeneration else { return }
            wipePhase = .failed(PrivacySafeErrorMapper.userMessage(for: error))
        }
    }

    public func retryWipeMediaCleanup() async {
        guard case .mediaCleanupIncomplete = wipePhase else { return }
        guard let leftoverUserId = pendingMediaCleanupUserId else { return }
        wipePhase = .deleting
        wipeGeneration += 1
        let generation = wipeGeneration
        do {
            try await privacyData.retryWipeMediaCleanup(userId: leftoverUserId)
            guard generation == wipeGeneration else { return }
            pendingMediaCleanupUserId = nil
            wipeStatusMessage = PrivacyAIDisclosureCopy.wipeMediaRetrySuccessMessage
            wipePhase = .idle
        } catch {
            guard generation == wipeGeneration else { return }
            wipePhase = .mediaCleanupIncomplete(PrivacySafeErrorMapper.userMessage(for: error))
        }
    }

    private func disableRetention(field: PrivacyAISettingField) async {
        guard let userId = session.currentUserId else {
            actionError = "尚未完成账户初始化"
            return
        }
        mutatingField = field
        actionError = nil
        mutationGeneration += 1
        let generation = mutationGeneration
        defer {
            if generation == mutationGeneration {
                mutatingField = nil
            }
        }
        do {
            _ = try await originalImageRetention.disableRetention(userId: userId)
            guard generation == mutationGeneration else { return }
            await applyPersistedConsent()
            retentionCleanupWarning = nil
            actionError = nil
        } catch let error as PrivacyError {
            guard generation == mutationGeneration else { return }
            await applyPersistedConsent()
            if case .retentionCleanupFailed = error {
                actionError = nil
                retentionCleanupWarning = PrivacySafeErrorMapper.userMessage(for: error)
            } else {
                actionError = PrivacySafeErrorMapper.userMessage(for: error)
            }
        } catch {
            guard generation == mutationGeneration else { return }
            await applyPersistedConsent()
            actionError = PrivacySafeErrorMapper.userMessage(for: error)
        }
    }

    private func mutate(
        _ field: PrivacyAISettingField,
        operation: (UUID) async throws -> AIDataConsent
    ) async {
        guard let userId = session.currentUserId else {
            actionError = "尚未完成账户初始化"
            return
        }
        mutatingField = field
        actionError = nil
        mutationGeneration += 1
        let generation = mutationGeneration
        defer {
            if generation == mutationGeneration {
                mutatingField = nil
            }
        }
        do {
            let consent = try await operation(userId)
            guard generation == mutationGeneration else { return }
            apply(consent)
            phase = .ready
            actionError = nil
        } catch {
            guard generation == mutationGeneration else { return }
            await reloadFromStore(showLoading: false)
            actionError = PrivacySafeErrorMapper.userMessage(for: error)
        }
    }

    private func reloadFromStore(showLoading: Bool) async {
        guard let userId = session.currentUserId else {
            phase = .error("尚未完成账户初始化")
            applyDeniedDefaults()
            return
        }
        do {
            let consent = try await consentService.fetchOrDefault(userId: userId)
            apply(consent)
            phase = .ready
        } catch {
            if showLoading {
                phase = .error(PrivacySafeErrorMapper.userMessage(for: error))
            } else {
                actionError = PrivacySafeErrorMapper.userMessage(for: error)
            }
        }
    }

    private func applyPersistedConsent() async {
        await reloadFromStore(showLoading: false)
    }

    private func apply(_ consent: AIDataConsent) {
        allowScreenshotImageToAI = consent.allowScreenshotImageToAI
        allowDebtScanImageToAI = consent.allowDebtScanImageToAI
        allowFinancialContextToAI = consent.allowFinancialContextToAI
        retainOriginalImages = consent.retainOriginalImages
    }

    private func applyDeniedDefaults() {
        allowScreenshotImageToAI = false
        allowDebtScanImageToAI = false
        allowFinancialContextToAI = false
        retainOriginalImages = false
    }
}
