import Foundation

public enum PrivacyWipeResult: Equatable, Sendable {
    /// All targeted local user data and retained binaries were removed.
    case complete
    /// Persistent store records were removed, but one or more retained original files remain.
    case mediaCleanupIncomplete
}

public enum PrivacyError: Error, Equatable, Sendable {
    case consentRequired(String)
    case deletionFailed(String)
    case mediaUnavailable
    case tokenUnavailable
    case operationFailed
    case retentionCleanupFailed(deletedCount: Int, failedImageIds: [String])
    case persistentDeletionIncomplete
    case mediaCleanupIncomplete

    /// 面向用户的安全提示：不含内部细节、金额、Token。
    public var userMessage: String {
        switch self {
        case .consentRequired(let scope):
            return "尚未授权「\(scope)」相关数据发送给 AI，请先在隐私设置中确认。"
        case .deletionFailed:
            return "删除未能完成，请稍后重试。若问题持续，可尝试清除全部本地数据。"
        case .mediaUnavailable:
            return "原图不可用或已按数据最小化策略清除。"
        case .tokenUnavailable:
            return "安全凭证不可用，请重新登录或配置后重试。"
        case .operationFailed:
            return "操作失败，未泄漏任何敏感数据。请稍后重试。"
        case .retentionCleanupFailed:
            return "原图保留已关闭，但部分已保留原图未能清除，请稍后重试。"
        case .persistentDeletionIncomplete:
            return "未能删除全部本地数据，请稍后重试。"
        case .mediaCleanupIncomplete:
            return "本地账本已删除，但部分已保留原图未能清除。"
        }
    }
}

extension PrivacyError: LocalizedError {
    public var errorDescription: String? { userMessage }
}

/// 将任意错误映射为不泄漏敏感信息的用户提示。
public enum PrivacySafeErrorMapper {
    public static func userMessage(for error: Error) -> String {
        if let privacy = error as? PrivacyError {
            return privacy.userMessage
        }
        if let ai = error as? AIRecognitionError {
            return ai.userMessage
        }
        if let domain = error as? DomainError {
            switch domain {
            case .validationFailed(let msg):
                return msg
            case .notFound:
                return "未找到相关数据。"
            case .userMismatch:
                return "无权访问该数据。"
            case .invalidRelation:
                return "数据关联无效，操作已取消。"
            }
        }
        return PrivacyError.operationFailed.userMessage
    }
}
