import Foundation
import YoushuDomain

enum RealRecognitionSourceKind: String, Codable, Sendable, Equatable {
    case privateRealScreenshot
    case privateRepresentativeScreenshot
}

enum RealRecognitionPlatform: String, Codable, Sendable, Equatable, CaseIterable {
    case weChat
    case alipay
    case other
}

enum RealRecognitionFamily: String, Codable, Sendable, Equatable, CaseIterable {
    case expensePayment
    case incomeReceived
    case refund
    case transfer
    case readableUnsupported
    case unreadable
}

enum RealRecognitionScreenshotQuality: String, Codable, Sendable, Equatable, CaseIterable {
    case fullScreenshot
    case crop
    case light
    case dark
    case other
}

enum RealRecognitionExpectedOutcome: String, Codable, Sendable, Equatable {
    case recognized
    case unsupported
    case unreadable
}

enum RealRecognitionDatePrecision: String, Codable, Sendable, Equatable {
    case day
    case minute
}

struct RealTransactionGroundTruthV1: Codable, Sendable, Equatable {
    var amount: OptionalFact<String>
    var direction: OptionalFact<String>
    var occurredAt: OptionalFact<String>
    var occurredAtPrecision: RealRecognitionDatePrecision?
    var merchant: OptionalFact<String>
    var paymentAccountHint: OptionalFact<String>
    var category: OptionalFact<String>
}

struct RealTransactionRecognitionSampleV1: Codable, Sendable, Equatable {
    var id: String
    var asset: String
    var sourceKind: RealRecognitionSourceKind
    var platform: RealRecognitionPlatform
    var family: RealRecognitionFamily
    var screenshotQualities: [RealRecognitionScreenshotQuality]
    var expectedOutcome: RealRecognitionExpectedOutcome
    var transaction: RealTransactionGroundTruthV1?
}

struct RealTransactionRecognitionCorpusV1: Codable, Sendable, Equatable {
    var schemaVersion: String
    var corpusVersion: String
    var timeZone: String
    var samples: [RealTransactionRecognitionSampleV1]
}

enum RealTransactionRecognitionCorpusError: Error, Equatable, Sendable {
    case unsupportedVersion(String)
    case emptyCorpusVersion
    case invalidTimeZone(String)
    case duplicateSampleID(String)
    case nonOpaqueSampleID(String)
    case unsafeAssetPath(String)
    case missingAsset(String)
    case outcomeLabelMismatch(String)
    case invalidDecimal(String)
    case invalidDirection(String)
    case invalidOccurredAt(String)
    case emptyQualityLabels(String)
    case invalidCandidateCommit(String)
}

enum RealRecognitionObservedOutcome: String, Codable, Sendable, Equatable, CaseIterable {
    case recognized
    case unsupported
    case unreadable
    case failure
}

struct RealRecognitionSampleResult: Sendable, Equatable {
    var sampleID: String
    var outcome: RealRecognitionObservedOutcome
    var observation: TransactionRecognitionObservation?
    var invalidRecognizedDraft: Bool
    var failureCategory: String?
    var latencyMilliseconds: Double
}

struct RecognitionMetricRatio: Codable, Sendable, Equatable {
    var numerator: Int
    var denominator: Int
    var percentage: Double?

    init(numerator: Int, denominator: Int) {
        self.numerator = numerator
        self.denominator = denominator
        percentage = denominator == 0 ? nil : Double(numerator) * 100 / Double(denominator)
    }
}

struct RecognitionFieldAccuracy: Codable, Sendable, Equatable {
    var endToEnd: RecognitionMetricRatio
    var recognizedOnly: RecognitionMetricRatio
}

struct RealRecognitionCoverage: Codable, Sendable, Equatable {
    var supported: Int
    var readableNegative: Int
    var expectedUnreadable: Int
    var privateRealScreenshot: Int
    var privateRepresentativeScreenshot: Int
    var weChat: Int
    var alipay: Int
    var otherPlatform: Int
    var expensePayment: Int
    var incomeReceived: Int
    var refund: Int
    var transfer: Int
    var fullScreenshot: Int
    var crop: Int
    var light: Int
    var dark: Int
    var otherQuality: Int
}

struct RealRecognitionOutcomeDistribution: Codable, Sendable, Equatable {
    var recognized: Int
    var unsupported: Int
    var unreadable: Int
    var failure: Int
}

struct RealRecognitionMetrics: Codable, Sendable, Equatable {
    var supportedRecognitionRate: RecognitionMetricRatio
    var amount: RecognitionFieldAccuracy
    var direction: RecognitionFieldAccuracy
    var occurredAt: RecognitionFieldAccuracy
    var merchant: RecognitionFieldAccuracy
    var unsupportedFalsePositiveRate: RecognitionMetricRatio
    var invalidRecognizedDraftCount: Int
    var operationalFailureCount: Int
    var crashCount: Int
}

enum RealRecognitionThresholdStatus: String, Codable, Sendable, Equatable {
    case pass = "PASS"
    case fail = "FAIL"
    case notEvaluable = "NOT EVALUABLE"
}

struct RealRecognitionThresholdResult: Codable, Sendable, Equatable {
    var metric: String
    var comparison: String
    var threshold: Double
    var actual: RecognitionMetricRatio?
    var actualCount: Int?
    var status: RealRecognitionThresholdStatus
}

struct RealRecognitionAccuracyGate: Codable, Sendable, Equatable {
    var amountExact: RealRecognitionThresholdResult
    var direction: RealRecognitionThresholdResult
    var occurredAt: RealRecognitionThresholdResult
    var merchant: RealRecognitionThresholdResult
    var supportedRecognition: RealRecognitionThresholdResult
    var unsupportedFalsePositive: RealRecognitionThresholdResult
    var invalidRecognizedDrafts: RealRecognitionThresholdResult
    var crashes: RealRecognitionThresholdResult
    var overall: RealRecognitionThresholdStatus
}

enum RealRecognitionBaselineStatus: String, Codable, Sendable, Equatable {
    case provisional = "PROVISIONAL"
    case established = "ESTABLISHED"
}

struct RealRecognitionLatency: Codable, Sendable, Equatable {
    var sampleCount: Int
    var p50Milliseconds: Double?
    var p95Milliseconds: Double?
}

/// Aggregate-only report. It intentionally has no per-sample collection or raw field-value property.
struct RealTransactionRecognitionBaselineReportV1: Codable, Sendable, Equatable {
    var schemaVersion: String
    var baselineStatus: RealRecognitionBaselineStatus
    var runTimestamp: String
    var candidateCommit: String
    var providerID: String
    var engineVersion: String
    var baselineEligible: Bool
    var corpusVersion: String
    var corpusDigest: String
    var sampleCount: Int
    var coverage: RealRecognitionCoverage
    var outcomes: RealRecognitionOutcomeDistribution
    var metrics: RealRecognitionMetrics
    var gate: RealRecognitionAccuracyGate
    var aggregateErrorCategories: [String: Int]
    var latency: RealRecognitionLatency
    var environment: String
    var platformOS: String
}

enum RealRecognitionCorpusAvailability: Equatable {
    case unavailable(String)
    case available(directory: URL, candidateCommit: String, reportURL: URL?)
}

enum RealRecognitionOfficialCoverage {
    static let minimumSupported = 100
    static let minimumReadableNegative = 20
    static let minimumWeChat = 20
    static let minimumAlipay = 20
    static let minimumExpensePayment = 50
    static let minimumIncomeReceived = 10
    static let minimumRefund = 10

    static func status(for coverage: RealRecognitionCoverage) -> RealRecognitionBaselineStatus {
        coverage.supported >= minimumSupported
            && coverage.readableNegative >= minimumReadableNegative
            && coverage.weChat >= minimumWeChat
            && coverage.alipay >= minimumAlipay
            && coverage.expensePayment >= minimumExpensePayment
            && coverage.incomeReceived >= minimumIncomeReceived
            && coverage.refund >= minimumRefund
            ? .established
            : .provisional
    }
}
