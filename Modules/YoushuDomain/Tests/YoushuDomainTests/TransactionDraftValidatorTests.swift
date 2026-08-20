import Foundation
import Testing
import YoushuDomain

@Suite("Transaction draft validator")
struct TransactionDraftValidatorTests {
    @Test("rejects multiple candidate amounts")
    func ambiguous() throws {
        let draft = TransactionDraft(
            amount: nil,
            candidateAmounts: [10, 20],
            unknowns: ["amount"]
        )
        #expect(throws: AIRecognitionError.ambiguousAmount([10, 20])) {
            try TransactionDraftValidator.validateRecognition(draft)
        }
    }

    @Test("rejects missing amount")
    func missingAmount() throws {
        let draft = TransactionDraft(amount: nil, unknowns: ["amount"])
        #expect(throws: AIRecognitionError.amountMissing) {
            try TransactionDraftValidator.validateRecognition(draft)
        }
    }

    @Test("date missing is warning only")
    func dateWarning() throws {
        let draft = TransactionDraft(
            amount: 12,
            transactionType: .expense,
            date: nil,
            category: "餐饮",
            unknowns: ["date"]
        )
        let warnings = try TransactionDraftValidator.validateRecognition(draft)
        #expect(warnings.contains(where: { $0.contains("时间") }))
    }

    @Test("confirmation rejects non-positive amount")
    func confirmAmount() {
        #expect(throws: DomainError.self) {
            try TransactionDraftValidator.validateConfirmation(
                ConfirmScreenshotTransactionInput(
                    amount: 0,
                    date: Date(),
                    category: "餐饮",
                    accountId: UUID(),
                    formType: .expense
                )
            )
        }
    }
}
