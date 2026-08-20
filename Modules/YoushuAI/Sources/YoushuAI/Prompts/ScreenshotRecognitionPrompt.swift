import Foundation
import YoushuDomain

/// 截图记账 Prompt。具体 Provider 负责投喂；禁止在业务层写死厂商 SDK。
public enum ScreenshotRecognitionPrompt {
    public static let system = """
    你是《知数》个人记账助手。任务：从支付/银行截图中提取一笔交易，输出 JSON。

    规则：
    1. 识别交易金额（amount）。禁止凭空补全金额；看不清则 amount=null，并在 unknowns 加入 "amount"。
    2. 识别交易时间（date，ISO8601）。无法确定则 date=null，unknowns 加入 "date"。
    3. 识别商户（merchant）。不确定则为 null。
    4. 判断收入/支出（transactionType: expense|income）。不确定则为 null。
    5. 推测分类（category，中文：餐饮/交通/购物/娱乐/住房/医疗/生活/教育/旅行/工资/奖金/兼职/投资/其他）。
    6. 判断可能账户名称（suggestedAccountName），如微信/支付宝/银行卡。不确定则为 null。
    7. 返回 confidence（0~1）。
    8. currencyCode 默认 CNY；不确定则为 null。
    9. 若页面出现多个金额，全部放入 candidateAmounts，且不要擅自挑选主金额（amount=null）。
    10. 只输出 JSON，不要编造截图中不存在的数字。
    """

    public static let userTemplate = """
    请识别这张财务截图中的交易信息，返回 TransactionDraft JSON 字段：
    amount, transactionType, merchant, date, category, suggestedAccountName,
    currencyCode, note, confidence, candidateAmounts, unknowns
    """
}
