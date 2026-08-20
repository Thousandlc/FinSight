import Foundation

/// 账单文档种类。MVP 使用截图；架构预留 PDF / 各类账单。
public enum BillDocumentKind: String, Codable, CaseIterable, Sendable, Hashable {
    case screenshot
    case pdf
    case creditCardStatement
    case loanStatement
    case consumerCreditStatement

    public var displayName: String {
        switch self {
        case .screenshot: return "截图"
        case .pdf: return "PDF"
        case .creditCardStatement: return "信用卡账单"
        case .loanStatement: return "贷款账单"
        case .consumerCreditStatement: return "消费信贷账单"
        }
    }
}

/// 统一账单输入。未来 PDF / 账单类型只需换 kind，不必改扫描编排。
public struct BillDocument: Identifiable, Sendable, Hashable {
    public let id: UUID
    public var kind: BillDocumentKind
    public var data: Data
    public var fileName: String?

    public init(
        id: UUID = UUID(),
        kind: BillDocumentKind = .screenshot,
        data: Data,
        fileName: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.data = data
        self.fileName = fileName
    }

    public var referenceId: String {
        fileName ?? "doc-\(id.uuidString.prefix(8))"
    }
}
