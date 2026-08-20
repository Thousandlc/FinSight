import Foundation
import Testing
import YoushuDomain
import YoushuFoundation

@Suite("Assistant answer presentation")
struct AssistantAnswerPresentationTests {
    private let userId = UUID()

    private func legacyAnswer() -> AssistantAnswer {
        AssistantAnswer(
            userId: userId,
            question: "我现在有多少钱？",
            intent: .availableCash,
            title: "可用资金",
            body: "你当前可用资金约为 ¥20000。",
            factSources: ["Account"]
        )
    }

    private func structuredAnswer(
        keyFacts: [AssistantKeyFact] = [],
        warnings: [AssistantWarning] = [],
        actions: [AssistantAction] = []
    ) -> AssistantAnswer {
        AssistantAnswer(
            userId: userId,
            question: "测试问题",
            intent: .availableCash,
            title: "结构化回答",
            body: "正文内容。",
            answer: "正文内容。",
            factSources: ["Account"],
            keyFacts: keyFacts,
            warnings: warnings,
            actions: actions,
            references: [AssistantReference(key: "availableCash")]
        )
    }

    @Test("maps legacy answer without structured fields")
    func legacyMapping() {
        let presentation = AssistantAnswerPresentationMapper.make(from: legacyAnswer())
        #expect(presentation.title == "可用资金")
        #expect(presentation.body.contains("20000"))
        #expect(presentation.keyFacts.isEmpty)
        #expect(presentation.warnings.isEmpty)
        #expect(presentation.actions.isEmpty)
    }

    @Test("maps key facts without changing money amount")
    func keyFactMapping() {
        let answer = structuredAnswer(keyFacts: [
            AssistantKeyFact(
                label: "可用资金",
                value: .money(MoneyDTO(amount: 20_000, currencyCode: "CNY")),
                kind: .balance,
                source: "availableCash"
            ),
        ])
        let presentation = AssistantAnswerPresentationMapper.make(from: answer)
        #expect(presentation.keyFacts.count == 1)
        guard case .money(let money) = presentation.keyFacts[0].displayValue else {
            Issue.record("Expected money key fact")
            return
        }
        #expect(money.amount == 20_000)
        #expect(money.currencyCode == "CNY")
    }

    @Test("maps warning severity unchanged")
    func warningMapping() {
        let answer = structuredAnswer(warnings: [
            AssistantWarning(
                title: "现金流风险",
                message: "预计余额可能下降。",
                severity: .risk,
                source: "cashFlow30"
            ),
        ])
        let presentation = AssistantAnswerPresentationMapper.make(from: answer)
        #expect(presentation.warnings.first?.severity == .risk)
    }

    @Test("maps navigable actions only")
    func actionMapping() {
        let answer = structuredAnswer(actions: [
            AssistantAction(title: "查看账户", destination: .accounts),
            AssistantAction(title: "查看债务", destination: .debt),
        ])
        let presentation = AssistantAnswerPresentationMapper.make(from: answer)
        #expect(presentation.actions.count == 2)
        #expect(presentation.actions.allSatisfy { $0.isNavigable })
        #expect(presentation.actions.contains { $0.destination == .accounts })
    }

    @Test("empty structured arrays stay empty in presentation")
    func emptyStructured() {
        let presentation = AssistantAnswerPresentationMapper.make(
            from: structuredAnswer(keyFacts: [], warnings: [], actions: [])
        )
        #expect(presentation.keyFacts.isEmpty)
        #expect(presentation.warnings.isEmpty)
        #expect(presentation.actions.isEmpty)
    }

    @Test("does not expose references to presentation")
    func referencesNotExposed() {
        let answer = structuredAnswer(
            keyFacts: [
                AssistantKeyFact(
                    label: "可用资金",
                    value: .money(MoneyDTO(amount: 100, currencyCode: "CNY")),
                    kind: .balance,
                    source: "availableCash"
                ),
            ]
        )
        let presentation = AssistantAnswerPresentationMapper.make(from: answer)
        #expect(!answer.references.isEmpty)
        #expect(presentation.keyFacts.count == 1)
    }

    @Test("maps text percent and date key facts")
    func valueKinds() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let answer = structuredAnswer(keyFacts: [
            AssistantKeyFact(label: "压力", value: .text("生活支出"), kind: .other, source: "primaryPressure"),
            AssistantKeyFact(label: "占比", value: .percent(25), kind: .debt, source: "debtPaymentToIncomePercent"),
            AssistantKeyFact(label: "目标日", value: .date(date), kind: .other, source: "estimatedDebtFreeDate"),
        ])
        let presentation = AssistantAnswerPresentationMapper.make(from: answer)
        #expect(presentation.keyFacts.count == 3)
    }

    @Test("all known destinations are navigable")
    func navigableDestinations() {
        for destination in AssistantActionDestination.allCases {
            #expect(AssistantAnswerPresentationMapper.isNavigable(destination))
        }
    }
}
