import Foundation

/// 用户对「哪些数据可发给 AI」的授权。默认最小化。
public struct AIDataConsent: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var userId: UUID
    /// 允许将记账截图字节发送给 AI（识别交易）。
    public var allowScreenshotImageToAI: Bool
    /// 允许将债务账单图片字节发送给 AI。
    public var allowDebtScanImageToAI: Bool
    /// 允许将聚合财务 Context（余额/收支/债务汇总等）发送给 AI 助手。
    public var allowFinancialContextToAI: Bool
    /// 是否在本地保留原图二进制。默认 false（仅元数据/临时引用）。
    public var retainOriginalImages: Bool
    public var updatedAt: Date
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        userId: UUID,
        allowScreenshotImageToAI: Bool = false,
        allowDebtScanImageToAI: Bool = false,
        allowFinancialContextToAI: Bool = false,
        retainOriginalImages: Bool = false,
        updatedAt: Date = Date(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.allowScreenshotImageToAI = allowScreenshotImageToAI
        self.allowDebtScanImageToAI = allowDebtScanImageToAI
        self.allowFinancialContextToAI = allowFinancialContextToAI
        self.retainOriginalImages = retainOriginalImages
        self.updatedAt = updatedAt
        self.createdAt = createdAt
    }

    /// 默认拒绝一切 AI 数据发送，需用户显式授权。
    public static func deniedDefault(userId: UUID) -> AIDataConsent {
        AIDataConsent(userId: userId)
    }

    /// 会话内接受截图隐私条款后的最小授权（仍不保留原图）。
    public func grantingScreenshotSession() -> AIDataConsent {
        var copy = self
        copy.allowScreenshotImageToAI = true
        copy.updatedAt = Date()
        return copy
    }

    public func grantingDebtScanSession() -> AIDataConsent {
        var copy = self
        copy.allowDebtScanImageToAI = true
        copy.updatedAt = Date()
        return copy
    }

    public func grantingAssistantContext() -> AIDataConsent {
        var copy = self
        copy.allowFinancialContextToAI = true
        copy.updatedAt = Date()
        return copy
    }

    public func revokingAssistantContext() -> AIDataConsent {
        var copy = self
        copy.allowFinancialContextToAI = false
        copy.updatedAt = Date()
        return copy
    }

    /// 供 UI / 审计展示：将发送给 AI 的数据类别说明。
    public var disclosedPayloadDescriptions: [String] {
        var items: [String] = []
        if allowScreenshotImageToAI {
            items.append("记账截图（用于交易识别；是否保留原图单独控制）")
        }
        if allowDebtScanImageToAI {
            items.append("债务账单图片（用于债务扫描；是否保留原图单独控制）")
        }
        if allowFinancialContextToAI {
            items.append("聚合财务摘要：收支、债务与现金流等（不含内部标识、备注或不必要的交易明细）")
        }
        if items.isEmpty {
            items.append("当前未授权任何数据发送给 AI")
        }
        return items
    }
}

public enum AIRecognitionKind: String, Codable, Sendable, Hashable {
    case screenshotTransaction
    case debtScan
}

public enum AIRecognitionStatus: String, Codable, Sendable, Hashable {
    case recognized
    case confirmed
    case discarded
    case failed
}

/// AI 识别审计记录。不含原图二进制，不含完整财务金额字段。
public struct AIRecognitionRecord: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var userId: UUID
    public var kind: AIRecognitionKind
    public var sourceImageId: String?
    public var status: AIRecognitionStatus
    public var modelName: String?
    /// 非敏感摘要，例如「截图记账识别」；禁止写入金额/证件号。
    public var summaryLabel: String
    public var createdAt: Date
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        userId: UUID,
        kind: AIRecognitionKind,
        sourceImageId: String? = nil,
        status: AIRecognitionStatus,
        modelName: String? = nil,
        summaryLabel: String,
        createdAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.userId = userId
        self.kind = kind
        self.sourceImageId = sourceImageId
        self.status = status
        self.modelName = modelName
        self.summaryLabel = summaryLabel
        self.createdAt = createdAt
        self.completedAt = completedAt
    }
}

public enum MediaRetentionPolicy: String, Codable, Sendable, Hashable {
    /// 仅内存/临时，处理完即删。
    case ephemeral
    /// 保留至 AI 处理完成。
    case untilProcessed
    /// 用户明确要求保留原图。
    case userRetained
}

/// 媒体元数据。默认不保存原图内容；仅在 retain 策略下可有相对路径。
public struct MediaArtifact: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var userId: UUID
    public var kind: AIRecognitionKind
    public var byteSize: Int
    public var contentHash: String
    public var retention: MediaRetentionPolicy
    public var relativePath: String?
    public var createdAt: Date
    public var purgeAfter: Date?

    public init(
        id: String,
        userId: UUID,
        kind: AIRecognitionKind,
        byteSize: Int,
        contentHash: String,
        retention: MediaRetentionPolicy = .ephemeral,
        relativePath: String? = nil,
        createdAt: Date = Date(),
        purgeAfter: Date? = nil
    ) {
        self.id = id
        self.userId = userId
        self.kind = kind
        self.byteSize = byteSize
        self.contentHash = contentHash
        self.retention = retention
        self.relativePath = relativePath
        self.createdAt = createdAt
        self.purgeAfter = purgeAfter
    }
}
