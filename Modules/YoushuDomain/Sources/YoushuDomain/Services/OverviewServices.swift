import Foundation
import YoushuFoundation

/// Loads home overview from repositories. Returns empty snapshot when no data.
public struct HomeOverviewService: HomeOverviewProviding {
    private let accounts: any AccountRepository
    private let transactions: any TransactionRepository
    private let debts: any DebtRepository
    private let repaymentPlans: any RepaymentPlanRepository
    private let assets: any AssetRepository
    private let budgets: any BudgetRepository
    private let goals: any GoalRepository
    private let insights: any FinancialInsightRepository
    private let users: any UserRepository
    private let financialAssistant: (any FinancialAssisting)?
    private let consentService: AIDataConsentService?
    private let safeBalance: Money

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
        financialAssistant: (any FinancialAssisting)? = nil,
        consentService: AIDataConsentService? = nil,
        safeBalance: Money = Money(amount: 2_000, currencyCode: "CNY")
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
        self.financialAssistant = financialAssistant
        self.consentService = consentService
        self.safeBalance = safeBalance
    }

    public func loadOverview(userId: UUID) async throws -> HomeOverview {
        let accountList = try await accounts.fetchAll(userId: userId)
        let txList = try await transactions.fetchAll(userId: userId)
        let debtList = try await debts.fetchAll(userId: userId)
        let planList = try await repaymentPlans.fetchAll(userId: userId)
        let assetList = try await assets.fetchAll(userId: userId)
        let budgetList = try await budgets.fetchAll(userId: userId)
        let goalList = try await goals.fetchAll(userId: userId)
        let insightList = try await insights.fetchAll(userId: userId)

        guard !accountList.isEmpty || !txList.isEmpty else {
            return HomeOverview(hasAccounts: false, hasTransactions: false)
        }

        let asOf = Date()
        let context = FinancialContextBuilder.build(
            .init(
                accounts: accountList,
                transactions: txList,
                debts: debtList,
                repaymentPlans: planList,
                assets: assetList,
                budgets: budgetList,
                goals: goalList,
                asOf: asOf,
                safeBalance: safeBalance
            )
        )
        let summary = FinancialSummary(
            availableCash: context.availableCash,
            monthlyIncome: context.monthlyIncome,
            monthlyExpense: context.monthlyExpense,
            monthlyDebtPayment: context.monthlyDebtPayment,
            estimatedMonthEndBalance: context.estimatedMonthEndBalance,
            financialHealthScore: context.financialHealthScore
        )
        let projections = CashFlowEngine.projectAllHorizons(
            .init(
                accounts: accountList,
                transactions: txList,
                debts: debtList,
                repaymentPlans: planList,
                asOf: asOf,
                horizonDays: CashFlowHorizon.days30.rawValue,
                safeBalance: Money(amount: safeBalance.amount, currencyCode: context.currencyCode)
            )
        )
        let primaryRisk = projections.first(where: { $0.horizon == .days30 })?.risk
            ?? projections.compactMap(\.risk).first

        let storedSummary = insightList
            .filter { $0.type == .summary }
            .sorted { $0.generatedAt > $1.generatedAt }
            .first

        let aiSummary = try await resolveAISummary(
            userId: userId,
            source: .init(
                accounts: accountList,
                transactions: txList,
                debts: debtList,
                repaymentPlans: planList,
                assets: assetList,
                budgets: budgetList,
                goals: goalList,
                asOf: asOf,
                safeBalance: safeBalance
            ),
            context: context,
            stored: storedSummary,
            primaryRisk: primaryRisk
        )

        return HomeOverview(
            availableFunds: summary.availableCash,
            monthlyIncome: summary.monthlyIncome,
            monthlyLivingExpense: summary.monthlyExpense,
            monthlyDebtRepayment: summary.monthlyDebtPayment,
            projectedMonthEndBalance: summary.estimatedMonthEndBalance,
            financialHealthScore: summary.financialHealthScore,
            aiSummary: aiSummary,
            cashFlowProjections: projections,
            cashFlowRisk: primaryRisk,
            hasAccounts: !accountList.isEmpty,
            hasTransactions: !txList.isEmpty
        )
    }

    private func resolveAISummary(
        userId: UUID,
        source: FinancialContextBuilder.Source,
        context: FinancialContext,
        stored: FinancialInsight?,
        primaryRisk: CashFlowRisk?
    ) async throws -> FinancialInsight {
        guard try await allowsFinancialContextTransmission(userId: userId) else {
            return makeDeterministicSummary(
                userId: userId,
                context: context,
                primaryRisk: primaryRisk
            )
        }

        let user = try await users.fetch(id: userId)
        let freshnessContext = MonthlySummaryFreshnessBuilder.buildContext(
            source: source,
            context: context,
            debtInventoryEstablishment: user?.debtInventoryEstablishment ?? .unestablished,
            debtImportInProgress: user?.debtImportInProgress ?? false,
            safeBalance: safeBalance
        )
        let currentMetadata = MonthlySummaryFreshnessBuilder.persistenceMetadata(
            from: freshnessContext.facts,
            assessment: freshnessContext.assessment
        )

        if let stored,
           StoredInsightFreshnessEvaluator.isCurrent(
               stored: stored.freshnessMetadata,
               current: currentMetadata
           ) {
            return stored
        }

        let staleStoredCandidate = stored

        if let assistant = financialAssistant {
            let recorder = ObservabilityOperationRecorder(operation: .monthlySummary)
            let generated: FinancialInsight
            do {
                generated = try await ObservabilityEmission.$recorder.withValue(recorder) {
                    try await self.generateRemoteAISummary(
                        userId: userId,
                        context: context,
                        assistant: assistant,
                        freshnessContext: freshnessContext
                    )
                }
            } catch is CancellationError {
                recorder.noteFailure(
                    ObservabilityErrorMapping.classify(code: .cancelled, stage: .clientTransport)
                )
                ObservabilityEmission.emitTerminal(recorder, outcome: .cancelled)
                return makeDeterministicSummary(
                    userId: userId,
                    context: context,
                    primaryRisk: primaryRisk
                )
            } catch {
                // Optional AI enrichment failure: Home availability policy lives here (ADR-020).
                // Deterministic Home metrics are already computed; fall back locally.
                recorder.noteFailure(error.observabilityClassification)
                ObservabilityEmission.emitTerminal(recorder, outcome: .degraded)
                return makeDeterministicSummary(
                    userId: userId,
                    context: context,
                    primaryRisk: primaryRisk
                )
            }

            if staleStoredCandidate != nil {
                do {
                    try await insights.upsert(generated)
                } catch {
                    // ADR-032: monthly `.summary` is a current-state cache, not a core fact.
                    // ADR-020: optional enrichment durability must not fail deterministic Home.
                    // The validated insight already exists in memory (same as first-generation
                    // Home, which does not persist). Show it ephemerally; durable cache is unchanged.
                    recorder.noteFailure(
                        error.observabilityClassification.stage == .insightPersistence
                            ? error.observabilityClassification
                            : ObservabilityErrorMapping.classify(
                                code: .persistenceFailure,
                                stage: .insightPersistence
                            )
                    )
                    ObservabilityEmission.emitTerminal(recorder, outcome: .degraded)
                    return generated
                }
            }
            ObservabilityEmission.emitTerminal(recorder, outcome: .success)
            return generated
        }

        return makeDeterministicSummary(
            userId: userId,
            context: context,
            primaryRisk: primaryRisk
        )
    }

    private func allowsFinancialContextTransmission(userId: UUID) async throws -> Bool {
        guard let consentService else { return true }
        return try await consentService.allowsFinancialContextTransmission(userId: userId)
    }

    private func generateRemoteAISummary(
        userId: UUID,
        context: FinancialContext,
        assistant: any FinancialAssisting,
        freshnessContext: MonthlySummaryFreshnessContext
    ) async throws -> FinancialInsight {
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
        var body = validated.body
        if let disclaimer = validated.disclaimer, !body.contains(disclaimer) {
            body += "\n\n\(disclaimer)"
        }
        let freshnessMetadata = MonthlySummaryFreshnessBuilder.persistenceMetadata(
            from: facts,
            assessment: assessment
        )
        return FinancialInsight(
            userId: userId,
            type: .summary,
            title: validated.title,
            body: body,
            modelName: assistant.name,
            freshnessMetadata: freshnessMetadata
        )
    }

    private func makeDeterministicSummary(
        userId: UUID,
        context: FinancialContext,
        primaryRisk: CashFlowRisk?
    ) -> FinancialInsight {
        FinancialInsight(
            userId: userId,
            type: .summary,
            title: primaryRisk == nil ? "本月财务摘要" : "现金流风险提示",
            body: CashFlowExplanationBuilder.buildSummary(
                from: FinancialSummary(
                    availableCash: context.availableCash,
                    monthlyIncome: context.monthlyIncome,
                    monthlyExpense: context.monthlyExpense,
                    monthlyDebtPayment: context.monthlyDebtPayment,
                    estimatedMonthEndBalance: context.estimatedMonthEndBalance,
                    financialHealthScore: context.financialHealthScore
                ),
                risk: primaryRisk
            ),
            modelName: "deterministic"
        )
    }
}

public struct TransactionListService: TransactionListProviding {
    private let transactions: any TransactionRepository
    private let accounts: any AccountRepository

    public init(transactions: any TransactionRepository, accounts: any AccountRepository) {
        self.transactions = transactions
        self.accounts = accounts
    }

    public func loadSnapshot(userId: UUID) async throws -> TransactionListSnapshot {
        let list = try await transactions.fetchAll(userId: userId)
        let accountList = try await accounts.fetchAll(userId: userId)
        let sections = TransactionGrouper.group(transactions: list, accounts: accountList)
        let currency = accountList.first?.currencyCode ?? list.first?.currencyCode ?? "CNY"
        let stats = MonthlyStatsCalculator.compute(
            transactions: list,
            month: Date(),
            currencyCode: currency
        )
        return TransactionListSnapshot(sections: sections, monthlyStats: stats)
    }
}

public struct AssetListService: AssetListProviding {
    private let assets: any AssetRepository

    public init(assets: any AssetRepository) {
        self.assets = assets
    }

    public func loadSnapshot(userId: UUID) async throws -> AssetListSnapshot {
        let list = try await assets.fetchAll(userId: userId)
        guard let currency = list.first?.currentValue.currencyCode else {
            return AssetListSnapshot(assets: list)
        }
        let total = list.reduce(Money(amount: 0, currencyCode: currency)) { $0 + $1.currentValue }
        return AssetListSnapshot(assets: list, totalValue: total)
    }
}

public struct AIAssistantService: AIAssistantProviding {
    private let insights: any FinancialInsightRepository
    private let assistant: FinancialAssistantService

    public init(
        insights: any FinancialInsightRepository,
        assistant: FinancialAssistantService
    ) {
        self.insights = insights
        self.assistant = assistant
    }

    public func loadSnapshot(userId: UUID) async throws -> AIAssistantSnapshot {
        let list = try await insights.fetchAll(userId: userId)
            .sorted { $0.generatedAt > $1.generatedAt }
        return AIAssistantSnapshot(recentInsights: list)
    }

    public func ask(question: String, userId: UUID) async throws -> AssistantAnswer {
        try await assistant.ask(question: question, userId: userId)
    }

    public func refreshInsights(userId: UUID) async throws -> [FinancialInsight] {
        do {
            _ = try await assistant.generateMonthlySummary(userId: userId)
        } catch let error as PrivacyError {
            throw error
        } catch {
            // Monthly summary remains best-effort; proactive insights still run afterward.
        }
        return try await assistant.refreshProactiveInsights(userId: userId)
    }
}

public struct RepositoryCurrentUserProvider: CurrentUserProviding {
    private let users: any UserRepository

    public init(users: any UserRepository) {
        self.users = users
    }

    public func currentUserId() async throws -> UUID? {
        try await users.fetchAll().first?.id
    }
}
