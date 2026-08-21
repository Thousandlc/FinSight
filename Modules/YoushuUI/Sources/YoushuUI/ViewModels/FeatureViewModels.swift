import Foundation
import YoushuDesignSystem
import YoushuDomain

@Observable
@MainActor
public final class HomeViewModel {
    public var phase: YSPagePhase<HomeOverview> = .loading

    private let homeProvider: any HomeOverviewProviding
    private let session: AppSession

    public init(homeProvider: any HomeOverviewProviding, session: AppSession) {
        self.homeProvider = homeProvider
        self.session = session
    }

    public func load() async {
        phase = .loading
        guard let userId = session.currentUserId else {
            phase = .error("尚未完成账户初始化")
            return
        }
        do {
            let overview = try await homeProvider.loadOverview(userId: userId)
            // 首页始终展示 PRD 区块结构；无数据时用零值快照，而非整页 Empty。
            phase = .content(overview)
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    public static let emptyConfig = YSEmptyStateConfig(
        icon: "chart.bar.doc.horizontal",
        title: "暂无财务数据",
        message: "添加账户或记录第一笔交易后，这里会展示你的财务总览。",
        actionTitle: "刷新"
    )
}

@Observable
@MainActor
public final class AssetViewModel {
    public var phase: YSPagePhase<AssetListSnapshot> = .loading

    private let provider: any AssetListProviding
    private let session: AppSession

    public init(provider: any AssetListProviding, session: AppSession) {
        self.provider = provider
        self.session = session
    }

    public func load() async {
        phase = .loading
        guard let userId = session.currentUserId else {
            phase = .error("尚未完成账户初始化")
            return
        }
        do {
            let snapshot = try await provider.loadSnapshot(userId: userId)
            phase = snapshot.isEmpty ? .empty(Self.emptyConfig) : .content(snapshot)
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    public static let emptyConfig = YSEmptyStateConfig(
        icon: "chart.pie",
        title: "暂无资产",
        message: "添加现金、投资或固定资产，构建完整的资产负债视图。",
        actionTitle: "刷新"
    )
}

@Observable
@MainActor
public final class AIAssistantViewModel {
    public enum ConsentState: Equatable {
        case loading
        case unauthorized
        case declined
        case authorized
        case error(String)
    }

    public var consentState: ConsentState = .loading
    public var phase: YSPagePhase<AIAssistantSnapshot> = .loading
    public var questionText: String = ""
    public var isAsking: Bool = false
    public var isAcceptingConsent: Bool = false
    public var askError: String?

    private let provider: any AIAssistantProviding
    private let consentService: AIDataConsentService
    private let session: AppSession
    private var lastAnswer: AssistantAnswer?
    private var hasDeclinedConsentInSession = false

    public init(
        provider: any AIAssistantProviding,
        session: AppSession,
        consentService: AIDataConsentService
    ) {
        self.provider = provider
        self.session = session
        self.consentService = consentService
    }

    public func load() async {
        consentState = .loading
        askError = nil
        guard let userId = session.currentUserId else {
            consentState = .error("尚未完成账户初始化")
            return
        }
        do {
            let consent = try await consentService.fetchOrDefault(userId: userId)
            if consent.allowFinancialContextToAI {
                hasDeclinedConsentInSession = false
                consentState = .authorized
                await loadAssistantContent()
            } else if hasDeclinedConsentInSession {
                consentState = .declined
            } else {
                consentState = .unauthorized
            }
        } catch {
            consentState = .error(Self.userFacingError(error))
        }
    }

    public func resetConversationTransientState() {
        lastAnswer = nil
        questionText = ""
        askError = nil
        hasDeclinedConsentInSession = false
    }

    public func reloadConsent() async {
        resetConversationTransientState()
        await load()
    }

    public func acceptConsent() async {
        guard let userId = session.currentUserId else {
            consentState = .error("尚未完成账户初始化")
            return
        }
        isAcceptingConsent = true
        askError = nil
        defer { isAcceptingConsent = false }
        do {
            _ = try await consentService.acceptAssistantPrivacy(userId: userId)
            hasDeclinedConsentInSession = false
            consentState = .authorized
            await loadAssistantContent()
        } catch {
            consentState = .error(Self.userFacingError(error))
        }
    }

    public func declineConsent() {
        hasDeclinedConsentInSession = true
        consentState = .declined
        askError = nil
    }

    public func showConsentPrompt() {
        hasDeclinedConsentInSession = false
        consentState = .unauthorized
    }

    public func ask(_ question: String? = nil) async {
        guard consentState == .authorized else {
            askError = Self.unauthorizedMessage
            return
        }
        let q = (question ?? questionText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        guard let userId = session.currentUserId else {
            askError = "尚未完成账户初始化"
            return
        }
        isAsking = true
        askError = nil
        defer { isAsking = false }
        do {
            let answer = try await provider.ask(question: q, userId: userId)
            lastAnswer = answer
            questionText = ""
            await loadAssistantContent()
        } catch {
            askError = Self.userFacingError(error)
        }
    }

    public func refreshInsights() async {
        guard consentState == .authorized else {
            askError = Self.unauthorizedMessage
            return
        }
        guard let userId = session.currentUserId else { return }
        do {
            _ = try await provider.refreshInsights(userId: userId)
            await loadAssistantContent()
        } catch {
            askError = Self.userFacingError(error)
        }
    }

    private func loadAssistantContent() async {
        phase = .loading
        guard let userId = session.currentUserId else {
            phase = .error("尚未完成账户初始化")
            return
        }
        do {
            var snapshot = try await provider.loadSnapshot(userId: userId)
            snapshot.lastAnswer = lastAnswer
            phase = snapshot.isEmpty ? .empty(Self.emptyConfig) : .content(snapshot)
        } catch {
            phase = .error(Self.userFacingError(error))
        }
    }

    private static let unauthorizedMessage = "你还没有授权 AI 使用你的财务信息。"

    private static func userFacingError(_ error: Error) -> String {
        if let privacy = error as? PrivacyError, case .consentRequired = privacy {
            return unauthorizedMessage
        }
        return PrivacySafeErrorMapper.userMessage(for: error)
    }

    public static let emptyConfig = YSEmptyStateConfig(
        icon: "text.bubble",
        title: "暂无 AI 摘要",
        message: "可以提问「我现在有多少钱？」或刷新生成可解释的财务洞察。",
        actionTitle: "刷新洞察"
    )
}
