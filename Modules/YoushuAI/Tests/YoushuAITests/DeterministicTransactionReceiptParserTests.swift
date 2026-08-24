import Foundation
import Testing
import YoushuAI
import YoushuDomain

@Suite("Deterministic Transaction receipt parser")
struct DeterministicTransactionReceiptParserTests {
    private let parser = DeterministicTransactionReceiptParser()

    private func parse(_ lines: [String], confidence: Double? = nil) -> TransactionRecognitionOutcome {
        parser.parseTransaction(from: lines.map { RecognizedTextSpan(text: $0, confidence: confidence) })
    }

    private func recognized(
        _ lines: [String],
        sourceLocation: SourceLocation = #_sourceLocation
    ) -> TransactionDraft? {
        guard case .recognized(let draft) = parse(lines) else {
            Issue.record("Expected recognized outcome", sourceLocation: sourceLocation)
            return nil
        }
        return draft
    }

    @Test("WeChat expense extracts amount direction merchant time and account hint")
    func weChatExpense() throws {
        let draft = try #require(recognized([
            "微信支付", "支付成功", "交易金额", "￥12.34", "商户：测试咖啡",
            "支付时间：2026-08-24 12:34:56", "支付方式：零钱",
        ]))
        #expect(draft.amount == Decimal(string: "12.34"))
        #expect(draft.transactionType == .expense)
        #expect(draft.merchant == "测试咖啡")
        #expect(draft.suggestedAccountName == "零钱")
        #expect(draft.date != nil)
        #expect(draft.category == nil)
    }

    @Test("WeChat received-money case is income")
    func weChatIncome() throws {
        let draft = try #require(recognized([
            "微信", "收款到账", "收款金额 +88.00", "付款方：测试用户", "收款时间 2026/8/24 08:09",
        ]))
        #expect(draft.amount == Decimal(string: "88.00"))
        #expect(draft.transactionType == .income)
        #expect(draft.merchant == "测试用户")
    }

    @Test("WeChat amount label outranks order number balance coupon and fee")
    func weChatIrrelevantNumbers() throws {
        let draft = try #require(recognized([
            "微信支付", "支付成功", "订单号 202608241234567890", "余额 ￥998.00",
            "优惠券 ￥5.00", "服务费 ￥0.10", "支付金额 ¥36.50", "商户：测试地铁",
        ]))
        #expect(draft.amount == Decimal(string: "36.50"))
    }

    @Test("WeChat supports yuan suffix")
    func weChatYuanSuffix() throws {
        let draft = try #require(recognized(["微信支付", "付款成功", "付款金额 12.34元"]))
        #expect(draft.amount == Decimal(string: "12.34"))
    }

    @Test("WeChat supports a signed transaction amount when expense semantics are explicit")
    func weChatSignedAmount() throws {
        let draft = try #require(recognized(["微信支付", "支付成功", "交易金额 -12.34"]))
        #expect(draft.amount == Decimal(string: "12.34"))
        #expect(draft.transactionType == .expense)
    }

    @Test("WeChat missing amount is unreadable")
    func weChatMissingAmount() {
        #expect(parse(["微信支付", "支付成功", "商户：测试咖啡"]) == .unreadable)
    }

    @Test("WeChat missing direction is unreadable")
    func weChatMissingDirection() {
        #expect(parse(["微信支付", "账单详情", "交易金额 ￥12.34"]) == .unreadable)
    }

    @Test("WeChat conflicting labeled amounts are unreadable")
    func weChatAmbiguousAmount() {
        #expect(parse(["微信支付", "支付成功", "交易金额 ￥12.34", "支付金额 ￥56.78"]) == .unreadable)
    }

    @Test("unrelated WeChat screenshot is unsupported")
    func unrelatedWeChat() {
        #expect(parse(["微信", "聊天", "这是合成测试消息"]) == .unsupported)
    }

    @Test("Alipay expense extracts representative fields")
    func alipayExpense() throws {
        let draft = try #require(recognized([
            "支付宝", "交易成功", "付款金额 ¥45.60", "商家：测试书店",
            "交易时间：2026-08-24 15:20:30", "付款方式：花呗",
        ]))
        #expect(draft.amount == Decimal(string: "45.60"))
        #expect(draft.transactionType == .expense)
        #expect(draft.merchant == "测试书店")
        #expect(draft.suggestedAccountName == "花呗")
        #expect(draft.date != nil)
    }

    @Test("Alipay transfer received is income")
    func alipayIncome() throws {
        let draft = try #require(recognized([
            "支付宝", "转账已到账", "收款金额 ￥66.00", "转账方：测试伙伴",
            "转账时间 2026年8月24日 09:10:11",
        ]))
        #expect(draft.amount == Decimal(string: "66.00"))
        #expect(draft.transactionType == .income)
        #expect(draft.merchant == "测试伙伴")
    }

    @Test("Alipay refund is conservatively represented as income")
    func alipayRefund() throws {
        let draft = try #require(recognized(["支付宝", "退款成功", "退款金额 ￥19.90", "商家：测试商店"]))
        #expect(draft.amount == Decimal(string: "19.90"))
        #expect(draft.transactionType == .income)
    }

    @Test("Alipay strong amount ignores unrelated numeric strings")
    func alipayIrrelevantNumbers() throws {
        let draft = try #require(recognized([
            "支付宝", "交易成功", "交易号 20260824111122223333", "优惠 3.00元",
            "实付金额 ￥108.08", "商家：测试超市",
        ]))
        #expect(draft.amount == Decimal(string: "108.08"))
    }

    @Test("Alipay missing amount is unreadable")
    func alipayMissingAmount() {
        #expect(parse(["支付宝", "交易成功", "商家：测试书店", "付款方式：余额"]) == .unreadable)
    }

    @Test("Alipay ambiguous amount is unreadable")
    func alipayAmbiguousAmount() {
        #expect(parse(["支付宝", "付款成功", "付款金额 ￥8.00", "实付金额 ￥9.00"]) == .unreadable)
    }

    @Test("unrelated Alipay page is unsupported")
    func unrelatedAlipay() {
        #expect(parse(["支付宝", "蚂蚁森林", "收取绿色能量"]) == .unsupported)
    }

    @Test("empty and garbage OCR are unreadable")
    func emptyAndGarbage() {
        #expect(parse([]) == .unreadable)
        #expect(parse(["###", "123456789", "..."]) == .unreadable)
    }

    @Test("readable unsupported app and financial document are unsupported")
    func genericUnsupported() {
        #expect(parse(["Safari", "Settings", "Privacy"]) == .unsupported)
        #expect(parse(["测试银行信用卡账单", "应还金额 ￥100.00"]) == .unsupported)
    }

    @Test("cropped supported page and conflicting direction are unreadable")
    func incompleteAndConflicting() {
        #expect(parse(["微信支付", "支付成功", "图片已裁剪"]) == .unreadable)
        #expect(parse(["支付宝", "支付成功", "收款到账", "交易金额 ￥20.00"]) == .unreadable)
    }

    @Test("duplicate spans and confidence edges do not alter financial facts")
    func duplicateSpansAndConfidence() throws {
        let outcome = parser.parseTransaction(from: [
            RecognizedTextSpan(text: "微信支付", confidence: -1),
            RecognizedTextSpan(text: "支付成功", confidence: 2),
            RecognizedTextSpan(text: "交易金额 ￥12.34", confidence: 0.01),
            RecognizedTextSpan(text: "交易金额 ￥12.34", confidence: 1),
        ])
        guard case .recognized(let draft) = outcome else {
            Issue.record("Duplicate identical OCR spans must remain deterministic")
            return
        }
        #expect(draft.amount == Decimal(string: "12.34"))
        #expect(draft.confidence == nil)
    }
}
