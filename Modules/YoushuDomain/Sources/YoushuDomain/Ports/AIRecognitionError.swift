import Foundation

/// AI 识别错误。禁止静默失败；必须向用户展示。
public enum AIRecognitionError: Error, Equatable, Sendable {
    case imageUnreadable
    case requestFailed(String)
    case invalidResponse(String)
    case amountMissing
    case ambiguousAmount([Decimal])
    case networkTimeout
    case dateMissing

    public var userMessage: String {
        switch self {
        case .imageUnreadable:
            return "无法读取图片，请重新选择截图。"
        case .requestFailed(let detail):
            return "AI 识别请求失败：\(detail)"
        case .invalidResponse(let detail):
            return "AI 返回格式错误：\(detail)"
        case .amountMissing:
            return "未能识别交易金额，请手动填写。"
        case .ambiguousAmount(let amounts):
            let list = amounts.map { "\($0)" }.joined(separator: "、")
            return "识别到多个金额（\(list)），无法自动判断，请手动选择。"
        case .networkTimeout:
            return "网络超时，请稍后重试。"
        case .dateMissing:
            return "未能识别交易时间，请手动选择。"
        }
    }
}

extension AIRecognitionError: LocalizedError {
    public var errorDescription: String? { userMessage }
}
