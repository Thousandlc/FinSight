import Foundation

/// Production-facing Privacy / AI disclosure copy.
/// Semantics follow current runtime consent, retention, and wipe contracts.
public enum PrivacyAIDisclosureCopy {
    public static let screenshotSettingTitle = "交易截图 AI 识别"
    public static let screenshotSettingSubtitle =
        "允许用你选择的交易截图进行 AI 识别。需要远程 AI 处理时，所选图片可能发送至 AI 服务。是否保留原图由「保留原始图片」单独控制。关闭后不影响已记账交易。"

    public static let screenshotConsentTitle = "隐私说明"
    public static let screenshotConsentLines: [String] = [
        "你选择的交易截图会用于 AI 识别交易信息。",
        "需要远程 AI 处理时，所选图片可能发送至 AI 服务。",
        "是否保留原图由「保留原始图片」单独控制；授权识别不会自动保存原图。",
        "AI 只提供识别草稿，不会直接写入账本；最终数据以你确认为准。",
    ]

    public static let debtScanSettingTitle = "债务图片 AI 扫描"
    public static let debtScanSettingSubtitle =
        "允许用你选择的账单图片进行 AI 债务扫描。需要远程 AI 处理时，所选图片可能发送至 AI 服务。扫描结果需你确认后才会写入。是否保留原图由「保留原始图片」单独控制。"

    public static let debtScanConsentTitle = "搞清楚你到底欠多少钱"
    public static let debtScanConsentLines: [String] = [
        "选择多张账单截图，AI 会帮你发现信用卡、分期和贷款等可能的债务。",
        "需要远程 AI 处理时，所选图片可能发送至 AI 服务。",
        "AI 只生成候选结果，不会直接写入账本；你确认后才会创建债务。",
        "是否保留原图由「保留原始图片」单独控制；授权扫描不会自动保存原图。",
    ]

    public static let debtEmptyStateMessage =
        "选择账单截图，用 AI 发现可能的债务；结果需你确认。也可以手动添加。"

    public static let financialContextSettingTitle = "财务上下文 AI"
    public static let financialContextSettingSubtitle =
        "开启后，知数可向 AI 提供完成分析所需的聚合财务摘要，例如收支、债务和现金流情况。发送内容经过最小化处理，不直接发送内部标识、备注或不必要的交易明细。关闭后不再发送新的财务上下文，首页改用本地计算摘要；此前生成的历史 AI 洞察不会因此自动删除。"

    public static let assistantConsentTitle = "让 AI 帮你看懂财务"
    public static let assistantConsentBody =
        "为了回答你的财务问题，知数可向 AI 提供完成分析所需的聚合财务摘要，例如收支、债务和现金流情况。发送内容经过最小化处理，不直接发送内部标识、备注或不必要的交易明细。"
    public static let assistantConsentGuarantee =
        "AI 不会因为你使用助手而自动修改你的账户、交易或债务数据。"
    public static let assistantUnauthorizedMessage = "你还没有授权使用财务上下文 AI。"
    public static let assistantAskFootnote =
        "基于已授权的聚合财务摘要作答。AI 只负责表述，不会直接改账。"

    public static let retentionSettingTitle = "保留原始图片"
    public static let retentionSettingSubtitle =
        "开启后，知数会在应用私有存储中保留用于识别的原始图片，便于后续追溯。关闭后将停止保留新的原图，并删除此前由知数保留的原图。这不等于授权 AI 处理图片。"

    public static let wipeActionTitle = "删除全部本地数据"
    public static let wipeActionSubtitle =
        "删除 App 内本地数据，不会删除你此前保存到「文件」中的备份。"
    public static let wipeConfirmationTitle = "确认删除全部本地数据？"
    public static let wipeConfirmationMessage =
        "将删除本 App 内的账户、交易、债务与计划、AI 授权与历史洞察、以及已保留的原始图片。删除后无法从当前 App 本地数据中恢复。保存在「文件」中的 .finsightbackup 备份不会被自动删除；如你此前保存了备份，之后仍可手动恢复其中包含的数据。"
    public static let wipeConfirmButtonTitle = "删除全部本地数据"
    public static let wipeSuccessMessage = "本地数据已删除。"
    public static let wipeMediaRetrySuccessMessage = "残留原图已清除。"

    public static let homeDeterministicCaption =
        "当前为本地计算摘要。授权财务上下文后，可由 AI 润色表述。"
    public static let homeAuthorizedCaption =
        "当前摘要基于已授权的聚合财务分析。"
    public static let homeEmptyCaption =
        "未授权或暂无 AI 说明时，首页使用本地计算摘要。"

    public static let backupRestoreExclusions =
        "AI 授权、历史 AI 洞察和保留的原图不会从备份恢复。"
    public static let backupRestoreReplaceWarning =
        "恢复会替换当前设备中的知数财务数据。当前设备中不在备份里的数据将被移除。"

    public static var screenshotConsentJoined: String {
        screenshotConsentLines.joined(separator: "\n")
    }

    public static var debtScanConsentJoined: String {
        debtScanConsentLines.joined(separator: "\n")
    }
}
