import Foundation

/// AI Provider 抽象。业务层不得依赖具体 OpenAI / Claude / Gemini SDK。
public protocol AIProviding: Sendable {
    var name: String { get }
}

/// Platform-neutral OCR output. Raw recognized text is transient by default.
/// Geometry is intentionally absent until a deterministic parser proves it is required.
public struct RecognizedTextSpan: Sendable, Hashable, Equatable {
    public let text: String
    public let confidence: Double?

    public init(text: String, confidence: Double? = nil) {
        self.text = text
        self.confidence = confidence.map { min(max($0, 0), 1) }
    }
}

/// Reproducible capability metadata used by the existing recognition-quality harness.
public struct TransactionRecognizerMetadata: Sendable, Hashable, Equatable {
    public let providerID: String
    public let engineVersion: String?
    public let inspectsImagePixels: Bool

    public init(providerID: String, engineVersion: String? = nil, inspectsImagePixels: Bool) {
        self.providerID = providerID
        self.engineVersion = engineVersion
        self.inspectsImagePixels = inspectsImagePixels
    }

    public var baselineEligible: Bool {
        let identity = providerID.trimmingCharacters(in: .whitespacesAndNewlines)
        let version = engineVersion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return inspectsImagePixels
            && !identity.isEmpty
            && identity.localizedCaseInsensitiveCompare("mock") != .orderedSame
            && !version.isEmpty
    }
}

/// Single-image Transaction recognition outcome. A recognized draft is reviewable, not authoritative.
public enum TransactionRecognitionOutcome: Sendable, Equatable {
    case recognized(TransactionDraft)
    case unsupported
    case unreadable
    case failure(AIRecognitionError)
}

/// Deterministic parser boundary: recognized text in, non-authoritative recognition outcome out.
/// Implementations must not perform OCR, remote calls, persistence, or user confirmation.
public protocol TransactionRecognizedTextParsing: Sendable {
    func parseTransaction(from spans: [RecognizedTextSpan]) -> TransactionRecognitionOutcome
}

/// 从截图提取交易草稿。只返回 DTO，不写库。
public protocol TransactionExtracting: AIProviding {
    var transactionRecognizerMetadata: TransactionRecognizerMetadata { get }
    func extractTransactionDraft(fromImageData data: Data) async throws -> TransactionDraft
    func recognizeTransaction(fromImageData data: Data) async -> TransactionRecognitionOutcome
}

public extension TransactionExtracting {
    /// Conservative default keeps existing adapters source-compatible and baseline-ineligible.
    var transactionRecognizerMetadata: TransactionRecognizerMetadata {
        TransactionRecognizerMetadata(providerID: name, inspectsImagePixels: false)
    }

    func recognizeTransaction(fromImageData data: Data) async -> TransactionRecognitionOutcome {
        do {
            return .recognized(try await extractTransactionDraft(fromImageData: data))
        } catch AIRecognitionError.imageUnreadable {
            return .unreadable
        } catch let error as AIRecognitionError {
            return .failure(error)
        } catch {
            return .failure(.requestFailed("识别服务暂时不可用"))
        }
    }
}

/// 批量扫描账单，返回债务候选 DTO。禁止直接创建 Debt。
public protocol DebtScanning: AIProviding {
    func scanDebts(from documents: [BillDocument]) async throws -> [DebtCandidate]
}

public protocol InsightExplaining: AIProviding {
    func explain(userId: UUID, titleHint: String) async throws -> FinancialInsight
}
