import Foundation
import Testing
import YoushuDomain
@testable import YoushuUI

@Suite("Privacy AI disclosure copy")
struct PrivacyAIDisclosureCopyTests {
    @Test("A financial-context disclosure describes minimized aggregated context")
    func financialContextDisclosure() {
        let surfaces = [
            PrivacyAIDisclosureCopy.financialContextSettingSubtitle,
            PrivacyAIDisclosureCopy.assistantConsentBody,
            PrivacyAIDisclosureCopy.assistantAskFootnote,
        ]
        for text in surfaces {
            #expect(text.contains("聚合财务摘要") || text.contains("聚合财务"))
            assertDoesNotDescribeRawRecords(text)
            assertNoJargon(in: text)
        }
        #expect(PrivacyAIDisclosureCopy.financialContextSettingSubtitle.contains("最小化"))
        #expect(PrivacyAIDisclosureCopy.assistantConsentBody.contains("不直接发送内部标识"))
    }

    @Test("B screenshot setting and contextual consent share image-AI semantics")
    func screenshotDisclosureConsistency() {
        let surfaces = [
            PrivacyAIDisclosureCopy.screenshotSettingSubtitle,
            PrivacyAIDisclosureCopy.screenshotConsentJoined,
        ]
        for text in surfaces {
            #expect(text.contains("截图"))
            #expect(text.contains("AI 识别"))
            #expect(text.contains("可能发送"))
            #expect(text.contains("保留原始图片") || text.contains("保留原图"))
            #expect(!text.contains("上传"))
            #expect(!text.contains("始终"))
            #expect(!text.contains("不会离开设备"))
            assertNoJargon(in: text)
        }
    }

    @Test("C debt-scan setting and contextual consent share image-AI semantics")
    func debtScanDisclosureConsistency() {
        let surfaces = [
            PrivacyAIDisclosureCopy.debtScanSettingSubtitle,
            PrivacyAIDisclosureCopy.debtScanConsentJoined,
            PrivacyAIDisclosureCopy.debtEmptyStateMessage,
        ]
        for text in surfaces {
            #expect(text.contains("债务"))
            #expect(!text.contains("上传"))
            assertNoJargon(in: text)
        }
        #expect(PrivacyAIDisclosureCopy.debtScanSettingSubtitle.contains("可能发送"))
        #expect(PrivacyAIDisclosureCopy.debtScanConsentJoined.contains("可能发送"))
        #expect(PrivacyAIDisclosureCopy.debtScanSettingSubtitle.contains("确认"))
        #expect(PrivacyAIDisclosureCopy.debtScanConsentJoined.contains("确认"))
        #expect(PrivacyAIDisclosureCopy.debtScanSettingSubtitle.contains("保留原始图片"))
    }

    @Test("D retention disclosure keeps local storage separate from AI permission")
    func retentionDisclosure() {
        let text = PrivacyAIDisclosureCopy.retentionSettingSubtitle
        #expect(text.contains("应用私有存储") || text.contains("私有存储"))
        #expect(text.contains("停止保留新的原图") || text.contains("停止保留"))
        #expect(text.contains("删除此前") || text.contains("删除"))
        #expect(text.contains("不等于授权 AI"))
        #expect(!text.contains("关闭后将同时关闭截图"))
        assertNoJargon(in: text)
    }

    @Test("E financial-context revoke copy does not delete historical insights")
    func financialContextRevokeDisclosure() {
        let text = PrivacyAIDisclosureCopy.financialContextSettingSubtitle
        #expect(text.contains("本地计算摘要"))
        #expect(text.contains("历史 AI 洞察"))
        #expect(text.contains("不会因此自动删除") || text.contains("不会自动删除"))
        #expect(!text.contains("关闭后将删除历史"))
        #expect(!text.contains("删除过去"))
        assertNoJargon(in: text)
    }

    @Test("F delete-all confirmation covers local data and excludes Files backups")
    func deleteAllConfirmation() {
        let text = PrivacyAIDisclosureCopy.wipeConfirmationMessage
        #expect(text.contains("账户") && text.contains("交易") && text.contains("债务"))
        #expect(text.contains("AI 授权") || text.contains("历史洞察"))
        #expect(text.contains("原始图片") || text.contains("原图"))
        #expect(text.contains(".finsightbackup") || text.contains("文件"))
        #expect(text.contains("不会被自动删除"))
        #expect(text.contains("无法从当前 App 本地数据中恢复"))
        assertNoJargon(in: text)
        assertNoSensitiveIdentifier(in: text)
    }

    @Test("G media-cleanup-incomplete copy says ledger is gone but originals remain")
    func partialDeletionWarning() {
        let text = PrivacyError.mediaCleanupIncomplete.userMessage
        #expect(text.contains("财务数据已删除") || text.contains("本地财务数据已删除"))
        #expect(text.contains("原图"))
        #expect(text.contains("未能清除") || text.contains("未能删除"))
        #expect(!text.contains("删除失败，账本仍在"))
        assertNoJargon(in: text)
        assertNoSensitiveIdentifier(in: text)

        let retention = PrivacyError.retentionCleanupFailed(deletedCount: 1, failedImageIds: ["img-secret"]).userMessage
        #expect(retention.contains("已停止保留新原图"))
        #expect(!retention.contains("img-secret"))
        assertNoSensitiveIdentifier(in: retention)
    }

    @Test("consent required copy hides internal Context jargon")
    func consentRequiredCopyHidesContextJargon() {
        let message = PrivacyError.consentRequired("财务助手 Context").userMessage
        #expect(message.contains("财务上下文"))
        #expect(!message.contains("Context"))
        #expect(!message.contains("DTO"))
    }

    private func assertDoesNotDescribeRawRecords(_ text: String) {
        #expect(!text.contains("交易记录"))
        #expect(!text.contains("读取你的账户、交易或债务对象"))
        #expect(!text.contains("Account / Transaction"))
        #expect(!text.contains("发送 Account"))
    }

    private func assertNoJargon(in text: String) {
        let banned = [
            "AssistantRequestDTO", "FinancialContextMapper", "FactPack", "Provider",
            "Gateway", "FinancialInsight", "MediaArtifact", "userId", "UUID",
            "DirectoryMediaBinaryStore", "Context",
        ]
        for term in banned {
            #expect(!text.contains(term), "copy must not contain \(term)")
        }
    }

    private func assertNoSensitiveIdentifier(in text: String) {
        #expect(!text.contains("00000000"))
        #expect(!text.lowercased().contains("file://"))
        #expect(!text.contains("media-originals"))
        #expect(!text.contains("img-"))
    }
}
