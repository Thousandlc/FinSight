import Foundation
import YoushuDomain

/// Validates in-memory restore candidates produced from portable backup payloads.
enum BackupRestoreCandidateValidator {
    static func validate(_ candidate: YoushuSnapshot) throws {
        guard candidate.schemaVersion == YoushuSnapshot.currentSchemaVersion else {
            throw BackupPayloadValidationError.unsupportedPayloadFormat(
                found: candidate.schemaVersion,
                supported: YoushuSnapshot.currentSchemaVersion
            )
        }
        guard candidate.insights.isEmpty else {
            throw BackupPayloadValidationError.invalidReference(field: "FinancialInsight")
        }
        guard candidate.aiDataConsents.isEmpty else {
            throw BackupPayloadValidationError.invalidReference(field: "AIDataConsent")
        }
        guard candidate.aiRecognitionRecords.isEmpty else {
            throw BackupPayloadValidationError.invalidReference(field: "AIRecognitionRecord")
        }
        guard candidate.mediaArtifacts.isEmpty else {
            throw BackupPayloadValidationError.invalidReference(field: "MediaArtifact")
        }
        guard candidate.pendingDebtLinks.isEmpty else {
            throw BackupPayloadValidationError.invalidReference(field: "PendingDebtLink")
        }
        guard candidate.suspectedDebts.isEmpty else {
            throw BackupPayloadValidationError.invalidReference(field: "SuspectedDebt")
        }
        guard candidate.users.allSatisfy({ !$0.debtImportInProgress }) else {
            throw BackupPayloadValidationError.invalidReference(field: "User.debtImportInProgress")
        }
    }
}
