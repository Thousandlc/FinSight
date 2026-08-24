import Foundation

/// AI 截图识别输出的结构化 DTO。
/// AI 禁止直接创建数据库对象；必须先返回本 DTO，经 Validator 与用户确认后再落库。
public struct TransactionDraft: Sendable, Hashable, Codable, Equatable {
    public var amount: Decimal?
    public var transactionType: TransactionType?
    public var merchant: String?
    public var date: Date?
    public var category: String?
    /// AI 推测的账户名称（非 UUID，禁止 AI 写库 id）。
    public var suggestedAccountName: String?
    public var currencyCode: String?
    public var note: String?
    public var confidence: Double?
    public var source: TransactionSource
    /// 若截图出现多个候选金额，全部列出；多于 1 个时 Validator 判为 ambiguous。
    public var candidateAmounts: [Decimal]
    /// 字段级不确定标记（null/unknown）。
    public var unknowns: [String]

    public init(
        amount: Decimal? = nil,
        transactionType: TransactionType? = nil,
        merchant: String? = nil,
        date: Date? = nil,
        category: String? = nil,
        suggestedAccountName: String? = nil,
        currencyCode: String? = nil,
        note: String? = nil,
        confidence: Double? = nil,
        source: TransactionSource = .screenshot,
        candidateAmounts: [Decimal] = [],
        unknowns: [String] = []
    ) {
        self.amount = amount
        self.transactionType = transactionType
        self.merchant = merchant
        self.date = date
        self.category = category
        self.suggestedAccountName = suggestedAccountName
        self.currencyCode = currencyCode?.uppercased()
        self.note = note
        self.confidence = confidence.map { min(max($0, 0), 1) }
        self.source = source
        self.candidateAmounts = candidateAmounts
        self.unknowns = unknowns
    }
}

/// Provider 识别完成、Application 接受前的暂态结果（ADR-036 Step C）。
/// 不表示 MediaArtifact / AIRecognitionRecord 已持久化。
public struct PendingScreenshotRecognition: Sendable, Equatable {
    public let acceptanceToken: UUID
    public let aiDraft: TransactionDraft
    public var editableDraft: TransactionDraft
    public let warnings: [String]
    public let imageData: Data
    public let importIdentity: TransactionScreenshotImportIdentity

    public init(
        acceptanceToken: UUID = UUID(),
        aiDraft: TransactionDraft,
        editableDraft: TransactionDraft? = nil,
        warnings: [String] = [],
        imageData: Data,
        importIdentity: TransactionScreenshotImportIdentity
    ) {
        self.acceptanceToken = acceptanceToken
        self.aiDraft = aiDraft
        self.editableDraft = editableDraft ?? aiDraft
        self.warnings = warnings
        self.imageData = imageData
        self.importIdentity = importIdentity
    }
}

/// Application 接受后进入审核流程的识别结果；此时 eligible 元数据已持久化。
public struct ScreenshotRecognitionResult: Sendable, Equatable {
    public let acceptanceToken: UUID
    /// AI 原始识别结果（只读展示）。
    public let aiDraft: TransactionDraft
    /// 供用户编辑的初始值（可与 aiDraft 相同，用户修改后不再回写 aiDraft）。
    public var editableDraft: TransactionDraft
    /// 非阻断性提示（如日期缺失）。
    public let warnings: [String]
    /// 临时图片引用；默认不永久保存原图。
    public let sourceImageId: String?
    public let importIdentity: TransactionScreenshotImportIdentity

    public init(
        acceptanceToken: UUID,
        aiDraft: TransactionDraft,
        editableDraft: TransactionDraft? = nil,
        warnings: [String] = [],
        sourceImageId: String? = nil,
        importIdentity: TransactionScreenshotImportIdentity
    ) {
        self.acceptanceToken = acceptanceToken
        self.aiDraft = aiDraft
        self.editableDraft = editableDraft ?? aiDraft
        self.warnings = warnings
        self.sourceImageId = sourceImageId
        self.importIdentity = importIdentity
    }
}

/// Screenshot confirm outcome. Transaction persistence is authoritative; secondary issues are degraded only.
public struct ConfirmScreenshotTransactionOutcome: Sendable, Equatable {
    public var transaction: Transaction
    public var debtLinkingIssue: String?
    public var provenanceIssue: String?

    public init(
        transaction: Transaction,
        debtLinkingIssue: String? = nil,
        provenanceIssue: String? = nil
    ) {
        self.transaction = transaction
        self.debtLinkingIssue = debtLinkingIssue
        self.provenanceIssue = provenanceIssue
    }

    public var isFullySuccessful: Bool { debtLinkingIssue == nil && provenanceIssue == nil }

    public var hasSecondaryIssues: Bool {
        debtLinkingIssue != nil || provenanceIssue != nil
    }
}

/// 用户确认后的最终保存输入（与 AI 草稿明确分离）。
public struct ConfirmScreenshotTransactionInput: Sendable, Equatable {
    public var amount: Decimal
    public var currencyCode: String
    public var date: Date
    public var merchant: String?
    public var category: String
    public var accountId: UUID
    public var note: String?
    public var formType: TransactionFormType
    public var recognitionConfidence: Double?
    public var sourceImageId: String?
    /// Import-local confirmation token. Reused to guarantee at-most-one Transaction per review flow.
    public var confirmationToken: UUID
    /// ADR-036 exact-source identity; required for screenshot provenance write.
    public var importIdentity: TransactionScreenshotImportIdentity?

    public init(
        amount: Decimal,
        currencyCode: String = "CNY",
        date: Date,
        merchant: String? = nil,
        category: String,
        accountId: UUID,
        note: String? = nil,
        formType: TransactionFormType,
        recognitionConfidence: Double? = nil,
        sourceImageId: String? = nil,
        confirmationToken: UUID,
        importIdentity: TransactionScreenshotImportIdentity? = nil
    ) {
        self.amount = amount
        self.currencyCode = currencyCode.uppercased()
        self.date = date
        self.merchant = merchant
        self.category = category
        self.accountId = accountId
        self.note = note
        self.formType = formType
        self.recognitionConfidence = recognitionConfidence
        self.sourceImageId = sourceImageId
        self.confirmationToken = confirmationToken
        self.importIdentity = importIdentity
    }
}
