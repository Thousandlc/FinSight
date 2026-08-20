import Foundation
import YoushuDomain
import YoushuFoundation

/// 可配置的 Mock AI。Unit Test 与本地预览使用；不依赖真实 API。
public struct MockAIProvider: TransactionExtracting, DebtScanning, InsightExplaining, FinancialAssisting {
    public let name = "mock"

    public enum Behavior: Sendable, Equatable {
        case success
        case amountMissing
        case dateMissing
        case ambiguousAmount
        case invalidResponse
        case networkError
        case timeout
        case custom(TransactionDraft)
    }

    public enum DebtScanBehavior: Sendable, Equatable {
        case successMultiDebt
        case duplicateCreditCardPages
        case currentDueOnly
        case distinctAmountsNoInterest
        case empty
        case invalidResponse
        case networkError
        case timeout
        case custom([DebtCandidate])
    }

    public enum AssistantBehavior: Sendable, Equatable {
        case success
        case inventAmount
        case missingDisclaimer
        case emptyBody
        case cannotAnswer
        case networkError
    }

    public var behavior: Behavior
    public var debtScanBehavior: DebtScanBehavior
    public var assistantBehavior: AssistantBehavior

    public init(
        behavior: Behavior = .success,
        debtScanBehavior: DebtScanBehavior = .successMultiDebt,
        assistantBehavior: AssistantBehavior = .success
    ) {
        self.behavior = behavior
        self.debtScanBehavior = debtScanBehavior
        self.assistantBehavior = assistantBehavior
    }

    public func extractTransactionDraft(fromImageData data: Data) async throws -> TransactionDraft {
        guard !data.isEmpty else {
            throw AIRecognitionError.imageUnreadable
        }

        switch behavior {
        case .success:
            return Self.sampleSuccessDraft()
        case .amountMissing:
            return TransactionDraft(
                amount: nil,
                transactionType: .expense,
                merchant: "某商户",
                date: Date(timeIntervalSince1970: 1_700_000_000),
                category: "餐饮",
                currencyCode: "CNY",
                confidence: 0.4,
                source: .screenshot,
                unknowns: ["amount"]
            )
        case .dateMissing:
            return TransactionDraft(
                amount: Decimal(string: "36.50"),
                transactionType: .expense,
                merchant: "地铁出行",
                date: nil,
                category: "交通",
                suggestedAccountName: "微信",
                currencyCode: "CNY",
                confidence: 0.82,
                source: .screenshot,
                unknowns: ["date"]
            )
        case .ambiguousAmount:
            return TransactionDraft(
                amount: nil,
                transactionType: .expense,
                merchant: "超市",
                date: Date(timeIntervalSince1970: 1_700_000_000),
                category: "购物",
                currencyCode: "CNY",
                confidence: 0.55,
                source: .screenshot,
                candidateAmounts: [
                    Decimal(string: "128.00")!,
                    Decimal(string: "28.00")!,
                ],
                unknowns: ["amount"]
            )
        case .invalidResponse:
            throw AIRecognitionError.invalidResponse("JSON missing required envelope")
        case .networkError:
            throw AIRecognitionError.requestFailed("模拟网络错误")
        case .timeout:
            throw AIRecognitionError.networkTimeout
        case .custom(let draft):
            return draft
        }
    }

    public func scanDebts(from documents: [BillDocument]) async throws -> [DebtCandidate] {
        guard !documents.isEmpty, documents.allSatisfy({ !$0.data.isEmpty }) else {
            throw AIRecognitionError.imageUnreadable
        }

        switch debtScanBehavior {
        case .successMultiDebt:
            return Self.sampleMultiDebtCandidates(documents: documents)
        case .duplicateCreditCardPages:
            return Self.sampleDuplicateCreditCardPages(documents: documents)
        case .currentDueOnly:
            let ref = documents[0].referenceId
            return [
                DebtCandidate(
                    lender: "招商银行",
                    productName: "信用卡",
                    debtType: .creditCard,
                    outstandingBalance: nil,
                    currentDue: Decimal(string: "2300"),
                    minimumDue: Decimal(string: "200"),
                    currencyCode: "CNY",
                    confidence: 0.8,
                    sourceDocuments: [ref],
                    unknowns: ["outstandingBalance", "interestRate"]
                ),
            ]
        case .distinctAmountsNoInterest:
            let ref = documents[0].referenceId
            return [
                DebtCandidate(
                    lender: "招商银行",
                    productName: "信用卡",
                    debtType: .creditCard,
                    outstandingBalance: Decimal(string: "12800"),
                    currentDue: Decimal(string: "2300"),
                    minimumDue: Decimal(string: "200"),
                    installmentAmount: nil,
                    remainingInstallments: nil,
                    interestRate: nil,
                    currencyCode: "CNY",
                    confidence: 0.9,
                    sourceDocuments: [ref],
                    unknowns: ["interestRate"]
                ),
            ]
        case .empty:
            return []
        case .invalidResponse:
            throw AIRecognitionError.invalidResponse("DebtCandidate JSON malformed")
        case .networkError:
            throw AIRecognitionError.requestFailed("模拟债务扫描网络错误")
        case .timeout:
            throw AIRecognitionError.networkTimeout
        case .custom(let candidates):
            return candidates
        }
    }

    public func explain(userId: UUID, titleHint: String) async throws -> FinancialInsight {
        FinancialInsight(
            userId: userId,
            type: .summary,
            title: titleHint.isEmpty ? "Mock Insight" : titleHint,
            body: "AI provider is mocked in this build.",
            modelName: name
        )
    }

    // MARK: - FinancialAssisting

    public func phraseAnswer(
        request: AssistantRequestDTO,
        facts: AnswerFactPack
    ) async throws -> AssistantAnswerDraft {
        try applyAssistantBehavior()
        if assistantBehavior == .cannotAnswer {
            throw AssistantValidationError.cannotAnswer("Mock：无法回答该问题")
        }
        if assistantBehavior == .emptyBody {
            return AssistantAnswerDraft(title: "回答", body: "", citedFactKeys: [])
        }
        if assistantBehavior == .inventAmount {
            return AssistantAnswerDraft(
                title: "编造示例",
                body: "根据测算你有 ¥999999。",
                citedFactKeys: ["availableCash"]
            )
        }
        if assistantBehavior == .missingDisclaimer, facts.requiresDisclaimer {
            return AssistantAnswerDraft(
                title: "建议",
                body: "你应该立刻存很多钱。",
                citedFactKeys: Array(facts.amounts.keys),
                disclaimer: nil
            )
        }

        return Self.composeFromFacts(intent: request.intent, facts: facts, context: request.context)
    }

    public func phraseMonthlySummary(
        request: AssistantRequestDTO,
        facts: MonthlySummaryFacts,
        riskAssessment: FinancialRiskAssessment
    ) async throws -> AssistantAnswerDraft {
        try applyAssistantBehavior()
        if assistantBehavior == .inventAmount {
            return AssistantAnswerDraft(title: "本月摘要", body: "本月神秘支出 ¥888888。")
        }
        if assistantBehavior == .emptyBody {
            return AssistantAnswerDraft(title: "本月摘要", body: " ")
        }

        let explanations = MonthlySummaryExplanationBuilder.build(assessment: riskAssessment)
        try AssistantExplanationAlignmentValidator.validate(
            riskExplanations: explanations.risk,
            unknownExplanations: explanations.unknown,
            assessment: riskAssessment,
            facts: facts
        )

        var body = "本月主要压力来自\(facts.primaryPressure)。预计月底结余约 \(Self.money(facts.estimatedMonthEndBalance))。"
        if !explanations.unknown.isEmpty {
            body += " " + explanations.unknown.map(\.text).joined(separator: " ")
        }
        if !explanations.risk.isEmpty {
            body += " " + explanations.risk.map(\.text).joined(separator: " ")
        }

        var keyFacts: [AssistantKeyFact] = [
            Self.moneyKeyFact(label: "可用资金", source: "availableCash", kind: .balance, amount: facts.availableCash),
            Self.moneyKeyFact(label: "预计月底结余", source: "estimatedMonthEndBalance", kind: .balance, amount: facts.estimatedMonthEndBalance),
            AssistantKeyFact(
                label: "主要压力",
                value: .text(facts.primaryPressure),
                kind: .other,
                source: "primaryPressure"
            ),
        ]
        var references: [AssistantReference] = [
            AssistantReference(key: "availableCash"),
            AssistantReference(key: "estimatedMonthEndBalance"),
            AssistantReference(key: "primaryPressure"),
        ]
        if let pct = facts.debtPaymentToIncomePercent {
            keyFacts.append(
                AssistantKeyFact(
                    label: "债务还款占比",
                    value: .percent(pct),
                    kind: .debt,
                    source: "debtPaymentToIncomePercent"
                )
            )
            references.append(AssistantReference(key: "debtPaymentToIncomePercent"))
        }

        return AssistantAnswerDraft(
            title: "本月财务摘要",
            body: body,
            answer: body,
            citedFactKeys: ["monthlyIncome", "monthlyDebtPayment", "primaryPressure", "estimatedMonthEndBalance"],
            unknowns: AssistantExplanationAlignmentValidator.mapUnknownTexts(explanations.unknown),
            confidence: 0.9,
            keyFacts: keyFacts,
            warnings: [],
            actions: [],
            references: references
        )
    }

    public func phrasePurchaseScenario(
        request: AssistantRequestDTO,
        scenario: PurchaseScenario
    ) async throws -> AssistantAnswerDraft {
        try applyAssistantBehavior()
        if assistantBehavior == .missingDisclaimer {
            return AssistantAnswerDraft(
                title: "购买评估",
                body: "直接买吧。",
                citedFactKeys: ["purchaseAmount"]
            )
        }
        if assistantBehavior == .inventAmount {
            return AssistantAnswerDraft(
                title: "购买评估",
                body: "买完还剩 ¥1。",
                citedFactKeys: ["cashAfterPurchase"],
                disclaimer: AssistantAnswerValidator.defaultAdviceDisclaimer
            )
        }

        let verdict: String
        switch scenario.affordability {
        case .affordable:
            verdict = "按当前账本数据，这笔支出在安全储备内相对可承受。"
        case .caution:
            verdict = "可以买，但可能挤压安全现金储备或近期现金流。"
        case .notRecommended:
            verdict = "按当前可用资金，不建议现在购买。"
        }
        var body = "\(verdict) 购买金额 \(Self.money(scenario.purchaseAmount))，当前可用 \(Self.money(scenario.currentCash))，买后约 \(Self.money(scenario.cashAfterPurchase))。"
        if scenario.breachesSafetyReserve {
            body += " 买后将低于安全储备 \(Self.money(scenario.safetyReserve))。"
        }
        if let goal = scenario.goalImpact {
            body += " \(goal)。"
        }
        body += " 假设未来收入与固定支出大致维持本月水平。"
        var warnings: [AssistantWarning] = []
        var actions: [AssistantAction] = [
            AssistantAction(title: "查看账户余额", destination: .accounts),
        ]
        if scenario.breachesSafetyReserve {
            warnings.append(
                AssistantWarning(
                    title: "安全储备不足",
                    message: "购买后可用资金将低于安全储备。",
                    severity: .risk,
                    source: "safetyReserve"
                )
            )
            actions.append(AssistantAction(title: "查看未来现金流", destination: .cashFlow))
        }
        let keyFacts: [AssistantKeyFact] = [
            Self.moneyKeyFact(label: "购买金额", source: "purchaseAmount", kind: .purchase, amount: scenario.purchaseAmount),
            Self.moneyKeyFact(label: "当前可用", source: "currentCash", kind: .balance, amount: scenario.currentCash),
            Self.moneyKeyFact(label: "买后可用", source: "cashAfterPurchase", kind: .balance, amount: scenario.cashAfterPurchase),
            Self.moneyKeyFact(label: "安全储备", source: "safetyReserve", kind: .cashFlow, amount: scenario.safetyReserve),
        ]
        return AssistantAnswerDraft(
            title: "购买可行性",
            body: body,
            answer: body,
            citedFactKeys: ["purchaseAmount", "currentCash", "cashAfterPurchase", "safetyReserve"],
            disclaimer: AssistantAnswerValidator.defaultAdviceDisclaimer,
            confidence: 0.85,
            keyFacts: keyFacts,
            warnings: warnings,
            actions: actions,
            references: [
                AssistantReference(key: "purchaseAmount"),
                AssistantReference(key: "currentCash"),
                AssistantReference(key: "cashAfterPurchase"),
                AssistantReference(key: "safetyReserve"),
            ]
        )
    }

    public func phraseInsight(
        request: AssistantRequestDTO,
        facts: InsightFactPack
    ) async throws -> AssistantAnswerDraft {
        try applyAssistantBehavior()
        let detail = facts.facts["message"]
            ?? facts.facts["explanation"]
            ?? facts.titleHint
        var body = detail
        var keyFacts: [AssistantKeyFact] = []
        var warnings: [AssistantWarning] = []
        var actions: [AssistantAction] = []
        var references: [AssistantReference] = []

        for (source, amount) in facts.amounts {
            keyFacts.append(Self.moneyKeyFact(label: source, source: source, kind: Self.kind(for: source), amount: amount))
            references.append(AssistantReference(key: source))
        }

        switch facts.type {
        case .cashFlow:
            warnings.append(
                AssistantWarning(
                    title: facts.titleHint,
                    message: detail,
                    severity: .risk,
                    source: "cashFlow30"
                )
            )
            references.append(AssistantReference(key: "cashFlow30"))
            actions.append(AssistantAction(title: "查看未来现金流", destination: .cashFlow))
        case .debtRisk:
            let warningSource = facts.amounts.keys.first ?? "monthlyDebtPayment"
            warnings.append(
                AssistantWarning(
                    title: facts.titleHint,
                    message: detail,
                    severity: .warning,
                    source: warningSource
                )
            )
            actions.append(AssistantAction(title: "查看债务", destination: .debt))
        case .spendingPattern:
            warnings.append(
                AssistantWarning(
                    title: facts.titleHint,
                    message: detail,
                    severity: .warning,
                    source: "monthlyExpense"
                )
            )
            actions.append(AssistantAction(title: "查看交易", destination: .transactions))
        case .actionSuggestion:
            actions.append(AssistantAction(title: "查看账户", destination: .accounts))
        default:
            break
        }

        if let amount = facts.amounts.values.first {
            body += " 关键金额 \(Self.money(amount))。"
        }
        body += " 来源：\(facts.sourceLabels.joined(separator: " / "))。"
        let disclaimer = facts.type == .actionSuggestion
            ? AssistantAnswerValidator.defaultAdviceDisclaimer
            : nil
        return AssistantAnswerDraft(
            title: facts.titleHint,
            body: body,
            answer: body,
            citedFactKeys: Array(facts.amounts.keys) + Array(facts.facts.keys),
            disclaimer: disclaimer,
            confidence: 0.8,
            keyFacts: keyFacts,
            warnings: warnings,
            actions: actions,
            references: references
        )
    }

    private func applyAssistantBehavior() throws {
        if assistantBehavior == .networkError {
            throw AIRecognitionError.requestFailed("模拟助手网络错误")
        }
    }

    private static func composeFromFacts(
        intent: FinancialQuestionIntent,
        facts: AnswerFactPack,
        context: FinancialAssistantContextDTO
    ) -> AssistantAnswerDraft {
        let disclaimer = facts.requiresDisclaimer ? AssistantAnswerValidator.defaultAdviceDisclaimer : nil
        switch intent {
        case .availableCash:
            let cash = facts.amounts["availableCash"] ?? moneyFromDTO(context.balance.availableCash)
            let body = "根据账户与交易记录，你当前可用资金约为 \(money(cash))。来源：Account / Transaction。"
            return AssistantAnswerDraft(
                title: "可用资金",
                body: body,
                answer: body,
                citedFactKeys: ["availableCash"],
                unknowns: facts.unknowns,
                confidence: 0.95,
                keyFacts: [Self.moneyKeyFact(label: "可用资金", source: "availableCash", kind: .balance, amount: cash)],
                actions: [AssistantAction(title: "查看账户", destination: .accounts)],
                references: [AssistantReference(key: "availableCash")]
            )
        case .totalDebt:
            let debt = facts.amounts["totalDebt"] ?? moneyFromDTO(context.debt.totalOutstanding)
            let monthly = facts.amounts["estimatedMonthlyRepayment"] ?? moneyFromDTO(context.debt.estimatedMonthlyRepayment)
            let body = "根据已登记债务，未结清总额约为 \(money(debt))，预计月供约 \(money(monthly))。来源：Debt。"
            return AssistantAnswerDraft(
                title: "总债务",
                body: body,
                answer: body,
                citedFactKeys: ["totalDebt", "estimatedMonthlyRepayment"],
                disclaimer: disclaimer,
                unknowns: facts.unknowns,
                keyFacts: [
                    Self.moneyKeyFact(label: "总债务", source: "totalDebt", kind: .debt, amount: debt),
                    Self.moneyKeyFact(label: "预计月供", source: "estimatedMonthlyRepayment", kind: .debt, amount: monthly),
                ],
                actions: [AssistantAction(title: "查看债务", destination: .debt)],
                references: [
                    AssistantReference(key: "totalDebt"),
                    AssistantReference(key: "estimatedMonthlyRepayment"),
                ]
            )
        case .spendingBreakdown:
            var body = "本月生活支出合计 \(money(facts.amounts["monthlyExpense"] ?? moneyFromDTO(context.monthly.expense)))。"
            var keyFacts = [
                Self.moneyKeyFact(
                    label: "本月支出",
                    source: "monthlyExpense",
                    kind: .expense,
                    amount: facts.amounts["monthlyExpense"] ?? moneyFromDTO(context.monthly.expense)
                ),
            ]
            if let name = facts.facts["category_0"], let amount = facts.amounts["categoryAmount_0"] {
                body += " 其中「\(name)」约 \(money(amount))，是最大分类。"
                keyFacts.append(Self.moneyKeyFact(label: name, source: "categoryAmount_0", kind: .expense, amount: amount))
            }
            body += " 来源：Transaction。"
            var references = [AssistantReference(key: "monthlyExpense")]
            if facts.amounts["categoryAmount_0"] != nil {
                references.append(AssistantReference(key: "categoryAmount_0"))
            }
            return AssistantAnswerDraft(
                title: "本月支出构成",
                body: body,
                answer: body,
                citedFactKeys: ["monthlyExpense", "categoryAmount_0"],
                unknowns: facts.unknowns,
                keyFacts: keyFacts,
                actions: [AssistantAction(title: "查看交易", destination: .transactions)],
                references: references
            )
        case .debtFreeDate:
            let dateText = facts.facts["estimatedDebtFreeDate"] ?? "尚不确定"
            let body = "在维持当前月供假设下，预计约在 \(dateText) 前后还清已登记债务。总债务 \(money(facts.amounts["totalDebt"] ?? moneyFromDTO(context.debt.totalOutstanding)))。来源：Debt。"
            var keyFacts: [AssistantKeyFact] = [
                Self.moneyKeyFact(
                    label: "总债务",
                    source: "totalDebt",
                    kind: .debt,
                    amount: facts.amounts["totalDebt"] ?? moneyFromDTO(context.debt.totalOutstanding)
                ),
            ]
            if let dateFact = facts.facts["estimatedDebtFreeDate"] {
                keyFacts.append(
                    AssistantKeyFact(
                        label: "预计清偿时间",
                        value: .text(dateFact),
                        kind: .debt,
                        source: "estimatedDebtFreeDate"
                    )
                )
            }
            var warnings: [AssistantWarning] = []
            if facts.facts["estimatedDebtFreeDate"] != nil {
                warnings.append(
                    AssistantWarning(
                        title: "清偿时间估算",
                        message: "基于当前月供假设，实际结果可能变化。",
                        severity: .safe,
                        source: "estimatedDebtFreeDate"
                    )
                )
            }
            var references: [AssistantReference] = [AssistantReference(key: "totalDebt")]
            if facts.facts["estimatedDebtFreeDate"] != nil {
                references.append(AssistantReference(key: "estimatedDebtFreeDate"))
            }
            return AssistantAnswerDraft(
                title: "预计清偿时间",
                body: body,
                answer: body,
                citedFactKeys: ["estimatedDebtFreeDate", "totalDebt"],
                disclaimer: disclaimer,
                unknowns: facts.unknowns,
                keyFacts: keyFacts,
                warnings: warnings,
                actions: [AssistantAction(title: "查看债务", destination: .debt)],
                references: references
            )
        case .monthlySavings:
            let save = facts.amounts["recommendedMonthlySavings"] ?? .zeroCNY
            let method = facts.facts["method"] ?? "按结余比例估算"
            let body = "按确定性规则估算，每月可考虑储蓄约 \(money(save))（\(method)）。"
            return AssistantAnswerDraft(
                title: "每月储蓄建议",
                body: body,
                answer: body,
                citedFactKeys: ["recommendedMonthlySavings"],
                disclaimer: disclaimer,
                unknowns: facts.unknowns,
                keyFacts: [
                    Self.moneyKeyFact(label: "建议储蓄", source: "recommendedMonthlySavings", kind: .savings, amount: save),
                ],
                actions: [AssistantAction(title: "查看账户", destination: .accounts)],
                references: [AssistantReference(key: "recommendedMonthlySavings")]
            )
        case .purchaseAffordability, .unknown:
            let body = "已根据授权财务 Context 整理事实，请查看数据来源说明。"
            return AssistantAnswerDraft(
                title: "财务助手",
                body: body,
                answer: body,
                citedFactKeys: Array(facts.amounts.keys),
                disclaimer: disclaimer,
                unknowns: facts.unknowns,
                references: facts.amounts.keys.map { AssistantReference(key: $0) }
            )
        }
    }

    private static func money(_ value: Money) -> String {
        "¥\(value.amount)"
    }

    private static func moneyKeyFact(
        label: String,
        source: String,
        kind: AssistantKeyFactKind,
        amount: Money
    ) -> AssistantKeyFact {
        AssistantKeyFact(
            label: label,
            value: .money(MoneyDTO(amount)),
            kind: kind,
            source: source
        )
    }

    private static func kind(for source: String) -> AssistantKeyFactKind {
        switch source {
        case "availableCash", "currentCash", "cashAfterPurchase", "estimatedMonthEndBalance", "minimumBalance":
            return .balance
        case "monthlyIncome":
            return .income
        case "monthlyExpense", "categoryAmount_0":
            return .expense
        case "totalDebt", "estimatedMonthlyRepayment", "dueAmount":
            return .debt
        case "safeBalance", "safetyReserve":
            return .cashFlow
        case "recommendedMonthlySavings":
            return .savings
        case "purchaseAmount":
            return .purchase
        default:
            return .other
        }
    }

    private static func moneyFromDTO(_ dto: MoneyDTO) -> Money {
        Money(amount: dto.amount, currencyCode: dto.currencyCode)
    }

    public static func sampleSuccessDraft() -> TransactionDraft {
        TransactionDraft(
            amount: Decimal(string: "36.50"),
            transactionType: .expense,
            merchant: "地铁出行",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            category: "交通",
            suggestedAccountName: "微信",
            currencyCode: "CNY",
            note: nil,
            confidence: 0.91,
            source: .screenshot,
            candidateAmounts: [Decimal(string: "36.50")!],
            unknowns: []
        )
    }

    public static func sampleMultiDebtCandidates(documents: [BillDocument]) -> [DebtCandidate] {
        let refs = documents.map(\.referenceId)
        return [
            DebtCandidate(
                lender: "招商银行",
                productName: "信用卡",
                debtType: .creditCard,
                outstandingBalance: Decimal(string: "8200"),
                currentDue: Decimal(string: "1500"),
                minimumDue: Decimal(string: "300"),
                dueDate: Date(timeIntervalSince1970: 1_701_000_000),
                interestRate: nil,
                currencyCode: "CNY",
                confidence: 0.9,
                sourceDocuments: [refs.first ?? "doc-1"],
                unknowns: ["interestRate"]
            ),
            DebtCandidate(
                lender: "马上消费",
                productName: "消费分期",
                debtType: .bnpl,
                outstandingBalance: Decimal(string: "3600"),
                currentDue: Decimal(string: "600"),
                installmentAmount: Decimal(string: "600"),
                remainingInstallments: 6,
                interestRate: nil,
                currencyCode: "CNY",
                confidence: 0.84,
                sourceDocuments: [refs.count > 1 ? refs[1] : (refs.first ?? "doc-2")],
                unknowns: ["interestRate"]
            ),
        ]
    }

    public static func sampleDuplicateCreditCardPages(documents: [BillDocument]) -> [DebtCandidate] {
        let refs = documents.map(\.referenceId)
        let r0 = refs.indices.contains(0) ? refs[0] : "page-1"
        let r1 = refs.indices.contains(1) ? refs[1] : "page-2"
        let r2 = refs.indices.contains(2) ? refs[2] : "page-3"
        return [
            DebtCandidate(
                lender: "招商银行",
                productName: "信用卡",
                debtType: .creditCard,
                outstandingBalance: nil,
                currentDue: Decimal(string: "2300"),
                minimumDue: Decimal(string: "200"),
                currencyCode: "CNY",
                confidence: 0.75,
                sourceDocuments: [r0],
                unknowns: ["outstandingBalance", "interestRate"]
            ),
            DebtCandidate(
                lender: "招商银行",
                productName: "信用卡",
                debtType: .creditCard,
                outstandingBalance: Decimal(string: "12800"),
                currentDue: Decimal(string: "2300"),
                minimumDue: Decimal(string: "200"),
                currencyCode: "CNY",
                confidence: 0.9,
                sourceDocuments: [r1],
                unknowns: ["interestRate"]
            ),
            DebtCandidate(
                lender: "招商银行",
                productName: "信用卡",
                debtType: .creditCard,
                outstandingBalance: Decimal(string: "12800"),
                installmentAmount: Decimal(string: "800"),
                remainingInstallments: 10,
                currencyCode: "CNY",
                confidence: 0.86,
                sourceDocuments: [r2],
                unknowns: ["interestRate"]
            ),
        ]
    }
}
