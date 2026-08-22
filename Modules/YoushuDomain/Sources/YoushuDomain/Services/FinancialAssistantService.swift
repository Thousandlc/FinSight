import Foundation
import YoushuFoundation

/// AI 财务助手编排：Context → 确定性事实 → AI 润色 → Validator。禁止写核心财务数据。
public struct FinancialAssistantService: Sendable {
    private let accounts: any AccountRepository
    private let transactions: any TransactionRepository
    private let debts: any DebtRepository
    private let repaymentPlans: any RepaymentPlanRepository
    private let assets: any AssetRepository
    private let budgets: any BudgetRepository
    private let goals: any GoalRepository
    private let insights: any FinancialInsightRepository
    private let users: any UserRepository
    private let assistant: any FinancialAssisting
    private let safeBalance: Money
    private let consentService: AIDataConsentService?

    public init(
        accounts: any AccountRepository,
        transactions: any TransactionRepository,
        debts: any DebtRepository,
        repaymentPlans: any RepaymentPlanRepository,
        assets: any AssetRepository,
        budgets: any BudgetRepository,
        goals: any GoalRepository,
        insights: any FinancialInsightRepository,
        users: any UserRepository,
        assistant: any FinancialAssisting,
        safeBalance: Money = Money(amount: 2_000, currencyCode: "CNY"),
        consentService: AIDataConsentService? = nil
    ) {
        self.accounts = accounts
        self.transactions = transactions
        self.debts = debts
        self.repaymentPlans = repaymentPlans
        self.assets = assets
        self.budgets = budgets
        self.goals = goals
        self.insights = insights
        self.users = users
        self.assistant = assistant
        self.safeBalance = safeBalance
        self.consentService = consentService
    }

    public func loadContext(userId: UUID, asOf: Date = Date()) async throws -> FinancialContext {
        let source = try await loadSource(userId: userId, asOf: asOf)
        return FinancialContextBuilder.build(source)
    }

    public func ask(question: String, userId: UUID, asOf: Date = Date()) async throws -> AssistantAnswer {
        try await requireFinancialContextConsent(userId: userId)
        let context = try await loadContext(userId: userId, asOf: asOf)
        let intent = FinancialQuestionRouter.classify(question)
        let purchaseAmount = FinancialQuestionRouter.extractPurchaseAmount(from: question)
        let pack = FinancialAnswerFactBuilder.build(
            intent: intent,
            context: context,
            purchaseAmount: purchaseAmount
        )

        if pack.dataInsufficient {
            throw AssistantValidationError.dataInsufficient
        }
        if intent == .unknown {
            throw AssistantValidationError.cannotAnswer("暂无法识别该问题，请尝试：\(FinancialQuestionRouter.suggestedQuestions.prefix(3).joined(separator: " / "))")
        }
        if intent == .purchaseAffordability, purchaseAmount == nil {
            throw AssistantValidationError.cannotAnswer("请在问题中写明购买金额，例如「我能不能买3000元的东西？」")
        }

        let request = FinancialAssistantContextMapper.makeRequest(
            question: question,
            intent: intent,
            context: context,
            safeBalance: safeBalance
        )

        let draft: AssistantAnswerDraft
        if intent == .purchaseAffordability, let amount = purchaseAmount {
            let scenario = PurchaseScenarioEngine.evaluate(
                purchaseAmount: Money(amount: amount, currencyCode: context.currencyCode),
                context: context,
                safetyReserve: safeBalance
            )
            draft = try await assistant.phrasePurchaseScenario(request: request, scenario: scenario)
            let validated = try AssistantAnswerValidator.validate(draft: draft, against: scenario.factPack)
            return makeAnswer(question: question, userId: userId, intent: intent, draft: validated, pack: scenario.factPack)
        }

        draft = try await assistant.phraseAnswer(request: request, facts: pack)
        let validated = try AssistantAnswerValidator.validate(draft: draft, against: pack)
        return makeAnswer(question: question, userId: userId, intent: intent, draft: validated, pack: pack)
    }

    public func generateMonthlySummary(userId: UUID, asOf: Date = Date()) async throws -> FinancialInsight {
        let result = try await generateMonthlySummaryWithRiskAssessment(userId: userId, asOf: asOf)
        return result.insight
    }

    /// Monthly summary production path with deterministic risk assessment (assessment is included in gateway request for P0-4.5.4B).
    public func generateMonthlySummaryWithRiskAssessment(
        userId: UUID,
        asOf: Date = Date()
    ) async throws -> MonthlySummaryRiskAssemblyResult {
        try await ObservabilityEmission.run(operation: .monthlySummary) {
            try await self.produceMonthlySummary(userId: userId, asOf: asOf)
        }
    }

    private func produceMonthlySummary(
        userId: UUID,
        asOf: Date
    ) async throws -> MonthlySummaryRiskAssemblyResult {
        try await requireFinancialContextConsent(userId: userId)
        let source = try await loadSource(userId: userId, asOf: asOf)
        let context = FinancialContextBuilder.build(source)
        let inventorySemantics = try await loadDebtInventorySemantics(userId: userId)
        let freshnessContext = MonthlySummaryFreshnessBuilder.buildContext(
            source: source,
            context: context,
            debtInventoryEstablishment: inventorySemantics.establishment,
            debtImportInProgress: inventorySemantics.importInProgress,
            safeBalance: safeBalance
        )
        let facts = freshnessContext.facts
        let assessment = freshnessContext.assessment
        let request = FinancialAssistantContextMapper.makeRequest(
            question: "",
            intent: .unknown,
            context: context,
            safeBalance: safeBalance
        )
        let aiDraft = try await assistant.phraseMonthlySummary(
            request: request,
            facts: facts,
            riskAssessment: assessment
        )
        let policyDraft = MonthlySummaryPolicyProjection.applyPolicyOwnership(
            to: aiDraft,
            assessment: assessment
        )
        let validated = try AssistantAnswerValidator.validateSummary(draft: policyDraft, facts: facts)
        let freshnessMetadata = MonthlySummaryFreshnessBuilder.persistenceMetadata(
            from: facts,
            assessment: assessment
        )
        let insight = FinancialInsight(
            userId: userId,
            type: .summary,
            title: validated.title,
            body: composedBody(validated),
            sourceAccountIds: [],
            modelName: assistant.name,
            generatedAt: asOf,
            freshnessMetadata: freshnessMetadata
        )
        try await persistInsight(insight)
        return MonthlySummaryRiskAssemblyResult(insight: insight, riskAssessment: assessment)
    }

    /// Evaluates deterministic monthly-summary risk assessment from production repositories (no AI call).
    public func evaluateMonthlySummaryRisk(userId: UUID, asOf: Date = Date()) async throws -> FinancialRiskAssessment {
        let source = try await loadSource(userId: userId, asOf: asOf)
        let context = FinancialContextBuilder.build(source)
        let baseFacts = FinancialContextBuilder.monthlySummaryFacts(from: context)
        let facts = MonthlySummaryFactsEnricher.enrich(baseFacts, context: context, safeBalance: safeBalance)
        let inventorySemantics = try await loadDebtInventorySemantics(userId: userId)
        return FinancialRiskAssessmentService.assess(
            FinancialRiskAssessmentService.assemblyContext(
                source: source,
                context: context,
                enrichedFacts: facts,
                safeBalance: safeBalance,
                debtInventoryLoadSucceeded: true,
                debtInventoryEstablishment: inventorySemantics.establishment,
                debtImportInProgress: inventorySemantics.importInProgress,
                evaluatedAt: asOf
            )
        )
    }

    /// 生成主动洞察并写入 Insight 仓库（不修改 Account/Transaction/Debt 金额）。
    public func refreshProactiveInsights(userId: UUID, asOf: Date = Date()) async throws -> [FinancialInsight] {
        try await ObservabilityEmission.run(operation: .insight) {
            try await self.refreshProactiveInsightsUntraced(userId: userId, asOf: asOf)
        }
    }

    private func refreshProactiveInsightsUntraced(userId: UUID, asOf: Date) async throws -> [FinancialInsight] {
        try await requireFinancialContextConsent(userId: userId)
        let source = try await loadSource(userId: userId, asOf: asOf)
        let context = FinancialContextBuilder.build(source)
        let packs = FinancialInsightGenerator.generate(
            context: context,
            accounts: source.accounts,
            transactions: source.transactions,
            debts: source.debts,
            safeBalance: safeBalance
        )
        let request = FinancialAssistantContextMapper.makeRequest(
            question: "",
            intent: .unknown,
            context: context,
            safeBalance: safeBalance
        )
        var created: [FinancialInsight] = []
        for pack in packs {
            let draft = try await assistant.phraseInsight(request: request, facts: pack)
            let answerPack = AnswerFactPack(
                intent: .unknown,
                facts: pack.facts,
                amounts: pack.amounts,
                sourceLabels: pack.sourceLabels,
                requiresDisclaimer: pack.type == .actionSuggestion
            )
            let validated = try AssistantAnswerValidator.validate(draft: draft, against: answerPack)
            let insight = FinancialInsight(
                userId: userId,
                type: pack.type,
                title: validated.title,
                body: composedBody(validated),
                sourceTransactionIds: pack.sourceTransactionIds,
                sourceDebtIds: pack.sourceDebtIds,
                sourceAccountIds: pack.sourceAccountIds,
                modelName: assistant.name,
                generatedAt: asOf
            )
            try await persistInsight(insight)
            created.append(insight)
        }
        return created
    }

    public func evaluatePurchase(amount: Decimal, userId: UUID, asOf: Date = Date()) async throws -> (PurchaseScenario, AssistantAnswer) {
        try await requireFinancialContextConsent(userId: userId)
        let context = try await loadContext(userId: userId, asOf: asOf)
        let scenario = PurchaseScenarioEngine.evaluate(
            purchaseAmount: Money(amount: amount, currencyCode: context.currencyCode),
            context: context,
            safetyReserve: safeBalance
        )
        let request = FinancialAssistantContextMapper.makeRequest(
            question: "我能不能买\(amount)元的东西？",
            intent: .purchaseAffordability,
            context: context,
            safeBalance: safeBalance
        )
        let draft = try await assistant.phrasePurchaseScenario(request: request, scenario: scenario)
        let validated = try AssistantAnswerValidator.validate(draft: draft, against: scenario.factPack)
        let answer = makeAnswer(
            question: "我能不能买\(amount)元的东西？",
            userId: userId,
            intent: .purchaseAffordability,
            draft: validated,
            pack: scenario.factPack
        )
        return (scenario, answer)
    }

    // MARK: - Private

    private struct DebtInventorySemantics: Sendable {
        var establishment: DebtInventoryEstablishmentState
        var importInProgress: Bool
    }

    private func loadDebtInventorySemantics(userId: UUID) async throws -> DebtInventorySemantics {
        let user = try await users.fetch(id: userId)
        return DebtInventorySemantics(
            establishment: user?.debtInventoryEstablishment ?? .unestablished,
            importInProgress: user?.debtImportInProgress ?? false
        )
    }

    private func persistInsight(_ insight: FinancialInsight) async throws {
        do {
            try await insights.upsert(insight)
        } catch {
            ObservabilityEmission.recorder?.noteFailure(
                error.observabilityClassification.stage == .insightPersistence
                    ? error.observabilityClassification
                    : ObservabilityErrorMapping.classify(code: .persistenceFailure, stage: .insightPersistence)
            )
            throw error
        }
    }

    private func requireFinancialContextConsent(userId: UUID) async throws {
        if let consentService {
            guard try await consentService.allowsFinancialContextTransmission(userId: userId) else {
                throw PrivacyError.consentRequired("财务助手 Context")
            }
        }
    }

    private func loadSource(userId: UUID, asOf: Date) async throws -> FinancialContextBuilder.Source {
        async let accountList = accounts.fetchAll(userId: userId)
        async let txList = transactions.fetchAll(userId: userId)
        async let debtList = debts.fetchAll(userId: userId)
        async let planList = repaymentPlans.fetchAll(userId: userId)
        async let assetList = assets.fetchAll(userId: userId)
        async let budgetList = budgets.fetchAll(userId: userId)
        async let goalList = goals.fetchAll(userId: userId)
        return .init(
            accounts: try await accountList,
            transactions: try await txList,
            debts: try await debtList,
            repaymentPlans: try await planList,
            assets: try await assetList,
            budgets: try await budgetList,
            goals: try await goalList,
            asOf: asOf,
            safeBalance: safeBalance
        )
    }

    private func makeAnswer(
        question: String,
        userId: UUID,
        intent: FinancialQuestionIntent,
        draft: AssistantAnswerDraft,
        pack: AnswerFactPack
    ) -> AssistantAnswer {
        let composed = composedBody(draft)
        return AssistantAnswer(
            userId: userId,
            question: question,
            intent: intent,
            title: draft.title,
            body: composed,
            answer: draft.answer,
            disclaimer: draft.disclaimer,
            factSources: pack.sourceLabels,
            unknowns: draft.unknowns,
            modelName: assistant.name,
            keyFacts: draft.keyFacts,
            warnings: draft.warnings,
            actions: draft.actions,
            references: draft.references
        )
    }

    private func composedBody(_ draft: AssistantAnswerDraft) -> String {
        var parts = [draft.body]
        if let disclaimer = draft.disclaimer, !disclaimer.isEmpty,
           !draft.body.contains(disclaimer) {
            parts.append(disclaimer)
        }
        if !draft.unknowns.isEmpty {
            parts.append("不确定信息：\(draft.unknowns.joined(separator: "；"))")
        }
        return parts.joined(separator: "\n\n")
    }
}
