import Foundation
import YoushuFoundation

// MARK: - Structured answer components

public enum AssistantKeyFactKind: String, Codable, Sendable, Equatable, CaseIterable {
    case balance
    case income
    case expense
    case debt
    case cashFlow
    case savings
    case purchase
    case other
}

public enum AssistantKeyFactValue: Codable, Equatable, Sendable {
    case money(MoneyDTO)
    case text(String)
    case percent(Decimal)
    case date(Date)

    private enum CodingKeys: String, CodingKey {
        case type, amount, currencyCode, value, date
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "money":
            self = .money(MoneyDTO(
                amount: try container.decode(Decimal.self, forKey: .amount),
                currencyCode: try container.decode(String.self, forKey: .currencyCode)
            ))
        case "text":
            self = .text(try container.decode(String.self, forKey: .value))
        case "percent":
            self = .percent(try container.decode(Decimal.self, forKey: .value))
        case "date":
            self = .date(try container.decode(Date.self, forKey: .date))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown AssistantKeyFactValue type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .money(let dto):
            try container.encode("money", forKey: .type)
            try container.encode(dto.amount, forKey: .amount)
            try container.encode(dto.currencyCode, forKey: .currencyCode)
        case .text(let value):
            try container.encode("text", forKey: .type)
            try container.encode(value, forKey: .value)
        case .percent(let value):
            try container.encode("percent", forKey: .type)
            try container.encode(value, forKey: .value)
        case .date(let value):
            try container.encode("date", forKey: .type)
            try container.encode(value, forKey: .date)
        }
    }
}

public struct AssistantKeyFact: Codable, Equatable, Sendable {
    public var label: String
    public var value: AssistantKeyFactValue
    public var kind: AssistantKeyFactKind
    public var source: String

    public init(label: String, value: AssistantKeyFactValue, kind: AssistantKeyFactKind, source: String) {
        self.label = label
        self.value = value
        self.kind = kind
        self.source = source
    }
}

public enum AssistantWarningSeverity: String, Codable, Sendable, Equatable, CaseIterable {
    case safe
    case warning
    case risk
}

public struct AssistantWarning: Codable, Equatable, Sendable {
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

public enum AssistantActionDestination: String, Codable, Sendable, Equatable, CaseIterable {
    case cashFlow
    case debt
    case transactions
    case accounts
}

public struct AssistantAction: Codable, Equatable, Sendable {
    public var title: String
    public var destination: AssistantActionDestination

    public init(title: String, destination: AssistantActionDestination) {
        self.title = title
        self.destination = destination
    }
}

public struct AssistantReference: Codable, Equatable, Sendable {
    public var key: String

    public init(key: String) {
        self.key = key
    }
}

/// Navigation / section reference keys that may be cited even when absent from the current fact pack.
public enum AssistantReferenceKey: String, Codable, Sendable, Equatable, CaseIterable {
    case cashFlow30
    case cashFlow
    case debt
    case transactions
    case accounts
}

/// Provider / UI 共享的结构化回答片段（不含 userId 等会话字段）。
public struct AssistantStructuredAnswer: Codable, Equatable, Sendable {
    public var answer: String
    public var keyFacts: [AssistantKeyFact]
    public var warnings: [AssistantWarning]
    public var actions: [AssistantAction]
    public var references: [AssistantReference]

    public init(
        answer: String,
        keyFacts: [AssistantKeyFact] = [],
        warnings: [AssistantWarning] = [],
        actions: [AssistantAction] = [],
        references: [AssistantReference] = []
    ) {
        self.answer = answer
        self.keyFacts = keyFacts
        self.warnings = warnings
        self.actions = actions
        self.references = references
    }
}

public enum AssistantStructuredAnswerSerializerError: Error, Equatable, Sendable {
    case invalidUTF8
}

public enum AssistantStructuredAnswerSerializer {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public static func encode(_ answer: AssistantStructuredAnswer) throws -> Data {
        try encoder.encode(answer)
    }

    public static func decode(_ data: Data) throws -> AssistantStructuredAnswer {
        try decoder.decode(AssistantStructuredAnswer.self, from: data)
    }

    public static func jsonString(_ answer: AssistantStructuredAnswer) throws -> String {
        let data = try encode(answer)
        guard let string = String(data: data, encoding: .utf8) else {
            throw AssistantStructuredAnswerSerializerError.invalidUTF8
        }
        return string
    }
}
