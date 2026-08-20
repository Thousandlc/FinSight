import Foundation
import YoushuFoundation

/// UI 层消费的回答展示模型。View 不得重新计算金额或解析 FactPack。
public struct AssistantAnswerPresentation: Equatable, Sendable {
    public struct KeyFactPresentation: Equatable, Sendable, Identifiable {
        public var id: String { label + source }
        public var label: String
        public var displayValue: KeyFactDisplayValue
        /// 保留 source 供测试与调试；第一版 UI 不展示。
        public var source: String

        public init(label: String, displayValue: KeyFactDisplayValue, source: String) {
            self.label = label
            self.displayValue = displayValue
            self.source = source
        }
    }

    public enum KeyFactDisplayValue: Equatable, Sendable {
        case money(Money)
        case text(String)
        case percent(Decimal)
        case date(Date)
    }

    public struct WarningPresentation: Equatable, Sendable, Identifiable {
        public var id: String { title + source }
        public var title: String
        public var message: String
        public var severity: AssistantWarningSeverity
        public var source: String

        public init(title: String, message: String, severity: AssistantWarningSeverity, source: String) {
            self.title = title
            self.message = message
            self.severity = severity
            self.source = source
        }
    }

    public struct ActionPresentation: Equatable, Sendable, Identifiable {
        public var id: String { title + destination.rawValue }
        public var title: String
        public var destination: AssistantActionDestination
        public var isNavigable: Bool

        public init(title: String, destination: AssistantActionDestination, isNavigable: Bool) {
            self.title = title
            self.destination = destination
            self.isNavigable = isNavigable
        }
    }

    public var title: String
    public var question: String
    public var body: String
    public var factSources: [String]
    public var keyFacts: [KeyFactPresentation]
    public var warnings: [WarningPresentation]
    public var actions: [ActionPresentation]

    public init(
        title: String,
        question: String,
        body: String,
        factSources: [String] = [],
        keyFacts: [KeyFactPresentation] = [],
        warnings: [WarningPresentation] = [],
        actions: [ActionPresentation] = []
    ) {
        self.title = title
        self.question = question
        self.body = body
        self.factSources = factSources
        self.keyFacts = keyFacts
        self.warnings = warnings
        self.actions = actions
    }
}

public enum AssistantAnswerPresentationMapper {
    public static func make(from answer: AssistantAnswer) -> AssistantAnswerPresentation {
        AssistantAnswerPresentation(
            title: answer.title,
            question: answer.question,
            body: answer.body,
            factSources: answer.factSources,
            keyFacts: answer.keyFacts.map(mapKeyFact),
            warnings: answer.warnings.map(mapWarning),
            actions: answer.actions.compactMap(mapAction)
        )
    }

    public static func isNavigable(_ destination: AssistantActionDestination) -> Bool {
        switch destination {
        case .cashFlow, .debt, .transactions, .accounts:
            return true
        }
    }

    private static func mapKeyFact(_ fact: AssistantKeyFact) -> AssistantAnswerPresentation.KeyFactPresentation {
        AssistantAnswerPresentation.KeyFactPresentation(
            label: fact.label,
            displayValue: mapValue(fact.value),
            source: fact.source
        )
    }

    private static func mapValue(_ value: AssistantKeyFactValue) -> AssistantAnswerPresentation.KeyFactDisplayValue {
        switch value {
        case .money(let dto):
            return .money(Money(amount: dto.amount, currencyCode: dto.currencyCode))
        case .text(let text):
            return .text(text)
        case .percent(let value):
            return .percent(value)
        case .date(let date):
            return .date(date)
        }
    }

    private static func mapWarning(_ warning: AssistantWarning) -> AssistantAnswerPresentation.WarningPresentation {
        AssistantAnswerPresentation.WarningPresentation(
            title: warning.title,
            message: warning.message,
            severity: warning.severity,
            source: warning.source
        )
    }

    private static func mapAction(_ action: AssistantAction) -> AssistantAnswerPresentation.ActionPresentation? {
        let navigable = isNavigable(action.destination)
        guard navigable else { return nil }
        return AssistantAnswerPresentation.ActionPresentation(
            title: action.title,
            destination: action.destination,
            isNavigable: navigable
        )
    }
}
