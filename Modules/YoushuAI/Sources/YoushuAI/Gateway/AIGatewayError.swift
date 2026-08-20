import Foundation

public enum AIGatewayError: Error, Equatable, Sendable {
    case notConfigured
    case invalidRequest
    case unauthorized
    case rateLimited(retryAfterSeconds: Int?)
    case providerUnavailable
    case providerTimeout
    case invalidProviderResponse
    case unsupportedSchemaVersion
    case unsupportedOperation
    case internalError
    case networkFailure(String)
    case decodingFailed
    case requestIdMismatch(expected: String, actual: String)

    public var isRetryable: Bool {
        switch self {
        case .providerUnavailable, .providerTimeout, .internalError:
            return true
        default:
            return false
        }
    }

    public var userMessage: String {
        switch self {
        case .notConfigured:
            return "AI Gateway 未配置。"
        case .invalidRequest:
            return "请求无效，请稍后重试。"
        case .unauthorized:
            return "服务未授权，请联系支持。"
        case .rateLimited:
            return "请求过于频繁，请稍后再试。"
        case .providerUnavailable:
            return "AI 服务暂时不可用。"
        case .providerTimeout:
            return "响应超时，请稍后再试。"
        case .invalidProviderResponse:
            return "AI 返回格式异常，已拒绝。"
        case .unsupportedSchemaVersion:
            return "应用版本过旧，请更新。"
        case .unsupportedOperation:
            return "当前不支持该 AI 操作。"
        case .internalError:
            return "服务异常，请稍后再试。"
        case .networkFailure:
            return "网络异常，请稍后再试。"
        case .decodingFailed:
            return "AI 响应解析失败。"
        case .requestIdMismatch:
            return "AI 响应无效，请重试。"
        }
    }
}

extension AIGatewayError: LocalizedError {
    public var errorDescription: String? { userMessage }
}
