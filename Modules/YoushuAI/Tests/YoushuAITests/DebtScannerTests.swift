import Foundation
import Testing
import YoushuAI
import YoushuData
import YoushuDomain
import YoushuFoundation

@Suite("AI Debt Scanner")
struct DebtScannerTests {
    private func docs(_ labels: [String]) -> [BillDocument] {
        labels.map { BillDocument(kind: .screenshot, data: Data($0.utf8), fileName: $0) }
    }

    private func makeService(behavior: MockAIProvider.DebtScanBehavior) async throws -> (
        service: DebtScannerService,
        container: RepositoryContainer,
        userId: UUID
    ) {
        let store = YoushuStore()
        let container = RepositoryContainer(store: store)
        let userId = UUID()
        try await container.users.upsert(User(id: userId, displayName: "Tester"))
        let debtService = DebtService(
            debts: container.debts,
            events: container.debtEvents,
            accounts: container.accounts,
            transactions: container.transactions
        )
        let service = DebtScannerService(
            scanner: MockAIProvider(debtScanBehavior: behavior),
            debtService: debtService
        )
        return (service, container, userId)
    }

    private func scan(
        _ service: DebtScannerService,
        documents: [BillDocument],
        userId: UUID
    ) async throws -> PendingDebtScanResult {
        let identity = DebtScanImportIdentity.from(documents: documents)
        return try await service.scan(documents: documents, userId: userId, importIdentity: identity)
    }

    private func confirmedDebts(
        outcome: DebtScanConfirmOutcome,
        container: RepositoryContainer
    ) async throws -> [Debt] {
        var debts: [Debt] = []
        for result in outcome.succeeded {
            guard let debtId = result.debtId else { continue }
            if let debt = try await container.debts.fetch(id: debtId) {
                debts.append(debt)
            }
        }
        return debts
    }

    @Test("scans multiple bills into distinct candidates")
    func multiDebt() async throws {
        let env = try await makeService(behavior: .successMultiDebt)
        let result = try await scan(env.service, documents: docs(["a.png", "b.png", "c.png"]), userId: env.userId)
        #expect(result.candidates.count == 2)
        #expect(result.candidates.contains { $0.lender == "招商银行" })
        #expect(result.candidates.contains { $0.lender == "马上消费" })
    }

    @Test("aggregates duplicate credit card pages into one candidate")
    func aggregateDuplicates() async throws {
        let env = try await makeService(behavior: .duplicateCreditCardPages)
        let result = try await scan(env.service, documents: docs(["p1", "p2", "p3"]), userId: env.userId)
        #expect(result.candidates.count == 1)
        let candidate = result.candidates[0]
        #expect(candidate.lender == "招商银行")
        #expect(candidate.outstandingBalance == Decimal(string: "12800"))
        #expect(candidate.currentDue == Decimal(string: "2300"))
        #expect(candidate.minimumDue == Decimal(string: "200"))
        #expect(candidate.installmentAmount == Decimal(string: "800"))
        #expect(candidate.remainingInstallments == 10)
        #expect(candidate.interestRate == nil)
        #expect(candidate.sourceDocuments.count == 3)
        #expect(candidate.outstandingBalance != candidate.currentDue)
    }

    @Test("keeps outstanding unknown when only current due is found")
    func currentDueOnly() async throws {
        let env = try await makeService(behavior: .currentDueOnly)
        let result = try await scan(env.service, documents: docs(["bill"]), userId: env.userId)
        #expect(result.candidates.count == 1)
        #expect(result.candidates[0].outstandingBalance == nil)
        #expect(result.candidates[0].currentDue == Decimal(string: "2300"))
        #expect(result.candidates[0].interestRate == nil)
        #expect(result.warnings.contains(where: { $0.contains("剩余总欠款") }))

        let outcome = await env.service.confirm(candidates: result.candidates, userId: env.userId)
        #expect(outcome.isFullySuccessful)
        let created = try await confirmedDebts(outcome: outcome, container: env.container)
        #expect(created.count == 1)
        #expect(created[0].outstandingBalance == nil)
        #expect(created[0].outstandingPrincipal == nil)
        #expect(created[0].currentDue?.amount == Decimal(string: "2300"))
        #expect(created[0].outstandingBalance?.amount != created[0].currentDue?.amount)
    }

    @Test("does not invent interest rate")
    func noInterestGuess() async throws {
        let env = try await makeService(behavior: .distinctAmountsNoInterest)
        let result = try await scan(env.service, documents: docs(["stmt"]), userId: env.userId)
        let c = result.candidates[0]
        #expect(c.outstandingBalance == Decimal(string: "12800"))
        #expect(c.currentDue == Decimal(string: "2300"))
        #expect(c.minimumDue == Decimal(string: "200"))
        #expect(c.interestRate == nil)
        #expect(c.unknowns.contains("interestRate"))
    }

    @Test("empty scan fails loudly")
    func emptyScan() async throws {
        let env = try await makeService(behavior: .empty)
        await #expect(throws: AIRecognitionError.self) {
            try await scan(env.service, documents: docs(["x"]), userId: env.userId)
        }
    }

    @Test("invalid AI format fails")
    func invalidFormat() async throws {
        let env = try await makeService(behavior: .invalidResponse)
        await #expect(throws: AIRecognitionError.invalidResponse("DebtCandidate JSON malformed")) {
            try await scan(env.service, documents: docs(["x"]), userId: env.userId)
        }
    }

    @Test("network error fails")
    func networkError() async throws {
        let env = try await makeService(behavior: .networkError)
        await #expect(throws: AIRecognitionError.self) {
            try await scan(env.service, documents: docs(["x"]), userId: env.userId)
        }
    }

    @Test("user confirm creates formal debts with screenshot source")
    func confirmCreatesDebts() async throws {
        let env = try await makeService(behavior: .successMultiDebt)
        let result = try await scan(env.service, documents: docs(["a", "b"]), userId: env.userId)
        let outcome = await env.service.confirm(candidates: result.candidates, userId: env.userId)
        #expect(outcome.isFullySuccessful)
        let created = try await confirmedDebts(outcome: outcome, container: env.container)
        #expect(created.count == 2)
        #expect(created.allSatisfy { $0.source == .screenshot })
        #expect(created.contains { $0.lender == "招商银行" && $0.outstandingBalance?.amount == Decimal(string: "8200") })
        #expect(created.contains { $0.lender == "招商银行" && $0.currentDue?.amount == Decimal(string: "1500") })
        #expect(created.contains { $0.lender == "马上消费" && $0.outstandingBalance?.amount == Decimal(string: "3600") })

        let stored = try await env.container.debts.fetchAll(userId: env.userId)
        #expect(stored.count == 2)

        for debt in stored {
            let events = try await env.container.debtEvents.fetchAll(debtId: debt.id)
            #expect(events.contains { $0.type == .created })
        }
    }

    @Test("user can edit candidate before confirm")
    func editThenConfirm() async throws {
        let env = try await makeService(behavior: .currentDueOnly)
        let result = try await scan(env.service, documents: docs(["bill"]), userId: env.userId)
        var edited = result.candidates[0]
        edited.outstandingBalance = Decimal(string: "9000")
        edited.lender = "用户修改银行"

        let outcome = await env.service.confirm(candidates: [edited], userId: env.userId)
        #expect(outcome.isFullySuccessful)
        let created = try await confirmedDebts(outcome: outcome, container: env.container)
        #expect(created.count == 1)
        #expect(created[0].lender == "用户修改银行")
        #expect(created[0].outstandingBalance?.amount == Decimal(string: "9000"))
        #expect(created[0].currentDue?.amount == Decimal(string: "2300"))
    }

    @Test("confirm does not invent outstandingBalance from currentDue")
    func confirmCurrentDueOnlyDoesNotInventOutstanding() async throws {
        let env = try await makeService(behavior: .currentDueOnly)
        let result = try await scan(env.service, documents: docs(["bill"]), userId: env.userId)
        let input = try env.service.makeCreateInput(from: result.candidates[0])
        #expect(input.approximateBalance == nil)
        #expect(input.currentDue == Decimal(string: "2300"))

        let outcome = await env.service.confirm(candidates: result.candidates, userId: env.userId)
        #expect(outcome.isFullySuccessful)
        let created = try await confirmedDebts(outcome: outcome, container: env.container)
        #expect(created[0].outstandingBalance == nil)
        #expect(created[0].currentDue?.amount == Decimal(string: "2300"))
        let stored = try await env.container.debts.fetch(id: created[0].id)
        #expect(stored?.outstandingBalance == nil)
        #expect(stored?.currentDue?.amount == Decimal(string: "2300"))
    }

    @Test("confirm preserves known outstanding balance exactly")
    func confirmPreservesKnownOutstanding() async throws {
        let env = try await makeService(behavior: .distinctAmountsNoInterest)
        let result = try await scan(env.service, documents: docs(["stmt"]), userId: env.userId)
        #expect(result.candidates[0].outstandingBalance == Decimal(string: "12800"))
        let outcome = await env.service.confirm(candidates: result.candidates, userId: env.userId)
        #expect(outcome.isFullySuccessful)
        let created = try await confirmedDebts(outcome: outcome, container: env.container)
        #expect(created[0].outstandingBalance?.amount == Decimal(string: "12800"))
        #expect(created[0].currentDue?.amount == Decimal(string: "2300"))
        #expect(created[0].minimumDue?.amount == Decimal(string: "200"))
    }

    @Test("confirm preserves unknown dueDate as nil")
    func confirmPreservesNilDueDate() async throws {
        let env = try await makeService(behavior: .currentDueOnly)
        let result = try await scan(env.service, documents: docs(["bill"]), userId: env.userId)
        #expect(result.candidates[0].dueDate == nil)
        let outcome = await env.service.confirm(candidates: result.candidates, userId: env.userId)
        #expect(outcome.isFullySuccessful)
        let created = try await confirmedDebts(outcome: outcome, container: env.container)
        #expect(created[0].dueDate == nil)
    }

    @Test("confirm preserves known dueDate")
    func confirmPreservesKnownDueDate() async throws {
        let env = try await makeService(behavior: .successMultiDebt)
        let result = try await scan(env.service, documents: docs(["a", "b"]), userId: env.userId)
        let cmb = try #require(result.candidates.first { $0.lender == "招商银行" })
        #expect(cmb.dueDate != nil)
        let outcome = await env.service.confirm(candidates: [cmb], userId: env.userId)
        #expect(outcome.isFullySuccessful)
        let created = try await confirmedDebts(outcome: outcome, container: env.container)
        #expect(created[0].dueDate == cmb.dueDate)
    }

    @Test("ignored candidates are not created when confirming subset")
    func confirmSubset() async throws {
        let env = try await makeService(behavior: .successMultiDebt)
        let result = try await scan(env.service, documents: docs(["a", "b"]), userId: env.userId)
        let onlyFirst = Array(result.candidates.prefix(1))
        let outcome = await env.service.confirm(candidates: onlyFirst, userId: env.userId)
        #expect(outcome.isFullySuccessful)
        let created = try await confirmedDebts(outcome: outcome, container: env.container)
        #expect(created.count == 1)
        let stored = try await env.container.debts.fetchAll(userId: env.userId)
        #expect(stored.count == 1)
    }

    @Test("aggregator merge never copies currentDue into outstandingBalance")
    func aggregatorSafety() {
        let pages = MockAIProvider.sampleDuplicateCreditCardPages(
            documents: docs(["1", "2", "3"])
        )
        #expect(pages.count == 3)
        let merged = DebtCandidateAggregator.aggregate(pages)
        #expect(merged.count == 1)
        #expect(merged[0].outstandingBalance == Decimal(string: "12800"))
        #expect(merged[0].currentDue == Decimal(string: "2300"))
    }

    @Test("prompt forbids inventing amounts and rates")
    func promptRules() {
        #expect(DebtScannerPrompt.system.contains("不能把「本期账单金额"))
        #expect(DebtScannerPrompt.system.contains("禁止猜测利率"))
        #expect(DebtScannerPrompt.system.contains("outstandingBalance"))
        #expect(DebtScannerPrompt.system.contains("currentDue"))
    }

    @Test("bill document kinds are reserved for future inputs")
    func documentKinds() {
        let kinds = BillDocumentKind.allCases
        #expect(kinds.contains(.pdf))
        #expect(kinds.contains(.creditCardStatement))
        #expect(kinds.contains(.loanStatement))
        #expect(kinds.contains(.consumerCreditStatement))
    }
}
