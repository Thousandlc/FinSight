import Foundation
import YoushuDomain
import YoushuFoundation

// MARK: - Optional fact

enum OptionalFact<Value: Equatable & Sendable & Codable>: Equatable, Sendable, Codable {
    case known(Value)
    case unknown

    enum CodingKeys: String, CodingKey {
        case presence
        case value
    }

    var knownValue: Value? {
        if case .known(let value) = self { return value }
        return nil
    }

    var isUnknown: Bool {
        if case .unknown = self { return true }
        return false
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let presence = try container.decode(String.self, forKey: .presence)
        switch presence {
        case "unknown":
            self = .unknown
        case "known":
            self = .known(try container.decode(Value.self, forKey: .value))
        default:
            throw RecognitionQualityCorpusError.invalidPresence(presence)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .unknown:
            try container.encode("unknown", forKey: .presence)
        case .known(let value):
            try container.encode("known", forKey: .presence)
            try container.encode(value, forKey: .value)
        }
    }
}

enum FieldOutcome: String, Codable, Sendable, Equatable {
    case correct
    case incorrect
    case missing
    case correctlyUnknown
    case invented
}

enum RecognitionCapability: String, Codable, Sendable, Equatable {
    case transactionScreenshot
    case debtScreenshot
}

enum RecognitionFixtureSourceKind: String, Codable, Sendable, Equatable {
    case synthetic
    case explicitlyDeidentifiedTestFixture = "explicitly-deidentified-test-fixture"
}

struct DateComparisonSpec: Codable, Sendable, Equatable {
    var precision: String
    var timeZone: String

    static let utcDay = DateComparisonSpec(precision: "day", timeZone: "UTC")
}

// MARK: - Ground truth

struct TransactionGroundTruthV1: Codable, Sendable, Equatable {
    var amount: OptionalFact<String>
    var currencyCode: OptionalFact<String>
    var transactionType: OptionalFact<String>
    var date: OptionalFact<String>
    var merchant: OptionalFact<String>
    var category: OptionalFact<String>
}

struct DebtCandidateGroundTruthV1: Codable, Sendable, Equatable {
    var localId: String
    var lender: OptionalFact<String>
    var productName: OptionalFact<String>
    var debtType: OptionalFact<String>
    var outstandingBalance: OptionalFact<String>
    var currentDue: OptionalFact<String>
    var minimumDue: OptionalFact<String>
    var installmentAmount: OptionalFact<String>
    var dueDate: OptionalFact<String>
    var interestRate: OptionalFact<String>
}

struct DebtGroundTruthV1: Codable, Sendable, Equatable {
    var candidates: [DebtCandidateGroundTruthV1]
}

struct RecognitionQualityFixtureV1: Codable, Sendable, Equatable {
    var id: String
    var capability: RecognitionCapability
    var sourceKind: RecognitionFixtureSourceKind
    var containsRealUserData: Bool
    var tags: [String]
    var assets: [String]
    var transaction: TransactionGroundTruthV1?
    var debt: DebtGroundTruthV1?
}

struct RecognitionQualityCorpusV1: Codable, Sendable, Equatable {
    var schemaVersion: String
    var corpusVersion: String
    var dateComparison: DateComparisonSpec
    var fixtures: [RecognitionQualityFixtureV1]
}

// MARK: - Observations (recognizer output, not Mock internals)

struct TransactionRecognitionObservation: Sendable, Equatable {
    var amount: Decimal?
    var currencyCode: String?
    var transactionType: TransactionType?
    var date: Date?
    var merchant: String?
    var category: String?
}

struct DebtCandidateObservation: Sendable, Equatable {
    var lender: String?
    var productName: String?
    var debtType: DebtType?
    var outstandingBalance: Decimal?
    var currentDue: Decimal?
    var minimumDue: Decimal?
    var installmentAmount: Decimal?
    var dueDate: Date?
    var interestRate: Decimal?
}

struct DebtRecognitionObservation: Sendable, Equatable {
    var candidates: [DebtCandidateObservation]
}

enum RecognitionFixtureObservation: Sendable, Equatable {
    case transaction(TransactionRecognitionObservation)
    case debt(DebtRecognitionObservation)
}

enum RecognitionFixtureRun: Sendable, Equatable {
    case operationFailure(code: String)
    case observation(RecognitionFixtureObservation)
}

// MARK: - Metrics / report

struct FieldMetricCounts: Codable, Sendable, Equatable {
    var correct: Int = 0
    var incorrect: Int = 0
    var missing: Int = 0
    var invented: Int = 0
    var correctlyUnknown: Int = 0
    var expectedKnownDenominator: Int = 0
    var expectedUnknownDenominator: Int = 0

    mutating func add(_ outcome: FieldOutcome) {
        switch outcome {
        case .correct:
            correct += 1
            expectedKnownDenominator += 1
        case .incorrect:
            incorrect += 1
            expectedKnownDenominator += 1
        case .missing:
            missing += 1
            expectedKnownDenominator += 1
        case .invented:
            invented += 1
            expectedUnknownDenominator += 1
        case .correctlyUnknown:
            correctlyUnknown += 1
            expectedUnknownDenominator += 1
        }
    }

    static func summing(_ items: [FieldMetricCounts]) -> FieldMetricCounts {
        items.reduce(into: FieldMetricCounts()) { partial, item in
            partial.correct += item.correct
            partial.incorrect += item.incorrect
            partial.missing += item.missing
            partial.invented += item.invented
            partial.correctlyUnknown += item.correctlyUnknown
            partial.expectedKnownDenominator += item.expectedKnownDenominator
            partial.expectedUnknownDenominator += item.expectedUnknownDenominator
        }
    }
}

struct TransactionQualityMetricsV1: Codable, Sendable, Equatable {
    var amount: FieldMetricCounts = .init()
    var transactionType: FieldMetricCounts = .init()
    var date: FieldMetricCounts = .init()
    var merchant: FieldMetricCounts = .init()
    var category: FieldMetricCounts = .init()
    var currencyCode: FieldMetricCounts = .init()
    var wholeRecordExactCount: Int = 0
    var wholeRecordEvaluatedCount: Int = 0
}

struct DebtQualityMetricsV1: Codable, Sendable, Equatable {
    var expectedCandidateCount: Int = 0
    var observedCandidateCount: Int = 0
    var matchedCount: Int = 0
    var missedCandidateCount: Int = 0
    var extraCandidateCount: Int = 0
    var lender: FieldMetricCounts = .init()
    var productName: FieldMetricCounts = .init()
    var debtType: FieldMetricCounts = .init()
    var outstandingBalance: FieldMetricCounts = .init()
    var currentDue: FieldMetricCounts = .init()
    var minimumDue: FieldMetricCounts = .init()
    var installmentAmount: FieldMetricCounts = .init()
    var dueDate: FieldMetricCounts = .init()
    var interestRate: FieldMetricCounts = .init()
}

struct RecognitionQualityReportV1: Codable, Sendable, Equatable {
    var schemaVersion: String
    var corpusVersion: String
    var recognizerLabel: String
    var baselineEligible: Bool
    var baselineIneligibilityReasons: [String]
    var fixtureCount: Int
    var transactionFixtureCount: Int
    var debtFixtureCount: Int
    var operationFailureCount: Int
    var operationFailureFixtureIDs: [String]
    var transaction: TransactionQualityMetricsV1
    var debt: DebtQualityMetricsV1
}

enum RecognitionQualityCorpusError: Error, Equatable, Sendable {
    case unsupportedVersion(String)
    case duplicateFixtureID(String)
    case missingAsset(fixtureID: String, path: String)
    case emptyDebtDocuments(String)
    case capabilityMismatch(String)
    case realUserDataNotAllowed(String)
    case invalidDecimal(String)
    case invalidDate(String)
    case invalidPresence(String)
    case invalidTimeZone(String)
}

enum RecognitionQualityBaseline {
    static let mockReasons = ["mockRecognizer", "recognizerDoesNotInspectPixels"]
    static let nonPixelReasons = ["recognizerDoesNotInspectPixels"]
}
