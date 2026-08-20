import Foundation

/// AI Provider 抽象。业务层不得依赖具体 OpenAI / Claude / Gemini SDK。
public protocol AIProviding: Sendable {
    var name: String { get }
}

/// 从截图提取交易草稿。只返回 DTO，不写库。
public protocol TransactionExtracting: AIProviding {
    func extractTransactionDraft(fromImageData data: Data) async throws -> TransactionDraft
}

/// 批量扫描账单，返回债务候选 DTO。禁止直接创建 Debt。
public protocol DebtScanning: AIProviding {
    func scanDebts(from documents: [BillDocument]) async throws -> [DebtCandidate]
}

public protocol InsightExplaining: AIProviding {
    func explain(userId: UUID, titleHint: String) async throws -> FinancialInsight
}
