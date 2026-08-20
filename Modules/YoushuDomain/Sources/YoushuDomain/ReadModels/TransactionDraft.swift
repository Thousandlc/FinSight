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

/// 识别阶段结果：保留 AI 原始草稿，与用户最终编辑分离。
public struct ScreenshotRecognitionResult: Sendable, Equatable {
    /// AI 原始识别结果（只读展示）。
    public let aiDraft: TransactionDraft
    /// 供用户编辑的初始值（可与 aiDraft 相同，用户修改后不再回写 aiDraft）。
    public var editableDraft: TransactionDraft
    /// 非阻断性提示（如日期缺失）。
    public let warnings: [String]
    /// 临时图片引用；默认不永久保存原图。
    public let sourceImageId: String?

    public init(
        aiDraft: TransactionDraft,
        editableDraft: TransactionDraft? = nil,
        warnings: [String] = [],
        sourceImageId: String? = nil
    ) {
        self.aiDraft = aiDraft
        self.editableDraft = editableDraft ?? aiDraft
        self.warnings = warnings
        self.sourceImageId = sourceImageId
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
        sourceImageId: String? = nil
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
    }
}
