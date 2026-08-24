import Foundation
import Testing
import YoushuDomain

@Suite("Debt candidate edit draft fact integrity")
struct DebtCandidateEditDraftTests {
    private let knownDueDate = Date(timeIntervalSince1970: 1_701_000_000)
    private let explicitDate = Date(timeIntervalSince1970: 1_702_000_000)

    private func currentDueOnlyCandidate(dueDate: Date? = nil) -> DebtCandidate {
        DebtCandidate(
            lender: "招商银行",
            productName: "信用卡",
            debtType: .creditCard,
            outstandingBalance: nil,
            currentDue: Decimal(string: "2300"),
            minimumDue: Decimal(string: "200"),
            dueDate: dueDate,
            currencyCode: "CNY",
            unknowns: ["outstandingBalance"]
        )
    }

    @Test("unknown dueDate survives unrelated edit")
    func unknownDueDateSurvivesUnrelatedEdit() {
        var draft = DebtCandidateEditDraft(from: currentDueOnlyCandidate())
        #expect(draft.candidate.dueDate == nil)
        #expect(!draft.includeDueDate)

        draft.candidate.lender = "用户修改银行"
        let saved = draft.finalized()
        #expect(saved.dueDate == nil)
        #expect(saved.lender == "用户修改银行")
        #expect(saved.currentDue == Decimal(string: "2300"))
        #expect(saved.outstandingBalance == nil)
    }

    @Test("explicit due date enable uses the selected date")
    func explicitDueDateSelection() {
        var draft = DebtCandidateEditDraft(from: currentDueOnlyCandidate())
        draft.setIncludeDueDate(true, explicitDate: explicitDate)
        draft.candidate.productName = "白金卡"

        let saved = draft.finalized()
        #expect(saved.dueDate == explicitDate)
        #expect(saved.productName == "白金卡")
    }

    @Test("known dueDate survives unrelated edit")
    func knownDueDatePreserved() {
        var draft = DebtCandidateEditDraft(from: currentDueOnlyCandidate(dueDate: knownDueDate))
        #expect(draft.includeDueDate)
        #expect(draft.candidate.dueDate == knownDueDate)

        draft.candidate.lender = "改名银行"
        let saved = draft.finalized()
        #expect(saved.dueDate == knownDueDate)
        #expect(saved.lender == "改名银行")
    }

    @Test("explicitly clearing dueDate returns nil")
    func explicitClearDueDate() {
        var draft = DebtCandidateEditDraft(from: currentDueOnlyCandidate(dueDate: knownDueDate))
        draft.setIncludeDueDate(false, explicitDate: explicitDate)
        let saved = draft.finalized()
        #expect(saved.dueDate == nil)
    }
}
