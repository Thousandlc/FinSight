import Foundation

/// Maps backup / restore errors to concise user-facing copy without exposing secrets or internals.
public enum BackupUserFacingErrorMapper {
    public static func message(for error: Error) -> String {
        if let category = BackupRestoreFailureClassifier.classify(error) {
            switch category {
            case .validationFailure:
                return validationMessage(for: error)
            case .commitFailure:
                return "恢复未能完成，当前设备中的财务数据未被替换。请稍后重试。"
            case .criticalPersistenceFailure:
                return criticalPersistenceMessage
            }
        }

        return "操作失败，请稍后重试。"
    }

    public static var criticalPersistenceMessage: String {
        "恢复过程中发生严重错误，应用无法确认当前数据状态是否一致。请停止继续修改财务数据，关闭并重新打开应用后检查数据，必要时联系支持。"
    }

    public static func backupCreationMessage(for error: Error) -> String {
        if let backupError = error as? BackupError {
            switch backupError {
            case .invalidPassphrase:
                return "请输入备份密码。"
            case .backupTooLarge:
                return "当前数据过大，无法创建备份。"
            case .authenticationFailure, .unsupportedFormat, .unsupportedAlgorithm,
                 .invalidCryptoParameter, .malformedEnvelope, .payloadDecodeFailure:
                return "创建备份失败，请稍后重试。"
            }
        }
        return "创建备份失败，请稍后重试。"
    }

    private static func validationMessage(for error: Error) -> String {
        if let backupError = error as? BackupError {
            switch backupError {
            case .invalidPassphrase:
                return "请输入备份密码。"
            case .authenticationFailure:
                return "无法解锁备份。密码可能不正确，或备份文件已损坏。"
            case .backupTooLarge:
                return "备份文件过大，无法处理。"
            case .unsupportedFormat:
                return "不支持的备份格式。"
            case .unsupportedAlgorithm, .invalidCryptoParameter, .malformedEnvelope, .payloadDecodeFailure:
                return "备份文件无效或已损坏。"
            }
        }

        if error is BackupPayloadValidationError {
            return "备份内容无效，无法恢复。"
        }

        return "无法验证备份文件，请检查后重试。"
    }
}
