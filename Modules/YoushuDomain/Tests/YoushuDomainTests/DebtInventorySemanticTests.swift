import Foundation
import Testing
import YoushuData
import YoushuDomain
import YoushuFoundation

@Suite("Debt inventory semantic hardening")
struct DebtInventorySemanticTests {
    private func semanticInput(
        debts: [Debt] = [],
        loadState: DebtInventoryLoadState = .loaded,
        establishment: DebtInventoryEstablishmentState = .unestablished,
        importInProgress: Bool = false,
        monthlyDebtPayment: Money = .zeroCNY
    ) -> DebtDataStateBuilder.SemanticInput {
        DebtDataStateBuilder.SemanticInput(
            debts: debts,
            totalOutstanding: DebtBalanceCalculator.totalOutstanding(debts: debts),
            repositoryLoadState: loadState,
            inventoryEstablishment: establishment,
            importInProgress: importInProgress,
            monthlyDebtPayment: monthlyDebtPayment
        )
    }

    @Test("repo success empty unestablished is not knownNoDebt")
    func emptyUnestablishedIsMissing() {
        let state = DebtDataStateBuilder.build(semanticInput())
        #expect(state == .missing)
        #expect(state != .knownNoDebt)
    }

    @Test("repo success empty confirmedComplete is knownNoDebt")
    func emptyConfirmedCompleteIsKnownNoDebt() {
        let state = DebtDataStateBuilder.build(
            semanticInput(establishment: .confirmedComplete)
        )
        #expect(state == .knownNoDebt)
    }

    @Test("repo success debt with partial establishment stays partial")
    func debtWithPartialEstablishment() {
        let debt = Debt(
            userId: UUID(),
            outstandingBalance: Money(amount: 5000, currencyCode: "CNY"),
            installmentAmount: Money(amount: 500, currencyCode: "CNY"),
            paymentFrequency: .monthly,
            status: .active,
            profileCompleteness: 0.9
        )
        let state = DebtDataStateBuilder.build(
            semanticInput(debts: [debt], establishment: .partial)
        )
        #expect(state == .partial)
        #expect(state != .knownDebt)
    }

    @Test("repo success debt with confirmedComplete is knownDebt")
    func debtWithConfirmedCompleteIsKnownDebt() {
        let debt = Debt(
            userId: UUID(),
            outstandingBalance: Money(amount: 5000, currencyCode: "CNY"),
            installmentAmount: Money(amount: 500, currencyCode: "CNY"),
            paymentFrequency: .monthly,
            status: .active,
            profileCompleteness: 0.9
        )
        let state = DebtDataStateBuilder.build(
            semanticInput(debts: [debt], establishment: .confirmedComplete)
        )
        #expect(state == .knownDebt)
    }

    @Test("import in progress with empty inventory is missing not knownNoDebt")
    func importInProgressEmpty() {
        let state = DebtDataStateBuilder.build(
            semanticInput(establishment: .partial, importInProgress: true)
        )
        #expect(state == .missing)
        #expect(state != DebtDataState.knownNoDebt)
    }

    @Test("user confirmed no debt path uses confirmedComplete semantics")
    func userConfirmedNoDebt() {
        let state = DebtDataStateBuilder.build(
            semanticInput(establishment: .confirmedComplete)
        )
        #expect(state == .knownNoDebt)
    }

    @Test("migrated legacy user with empty inventory defaults to missing")
    func migratedLegacyUser() {
        let state = DebtDataStateBuilder.build(
            semanticInput(establishment: .unestablished)
        )
        #expect(state == .missing)
    }

    @Test("confirmedComplete with repayment contradiction stays partial")
    func confirmedCompleteRepaymentContradiction() {
        let state = DebtDataStateBuilder.build(
            semanticInput(
                establishment: .confirmedComplete,
                monthlyDebtPayment: Money(amount: 800, currencyCode: "CNY")
            )
        )
        #expect(state == .partial)
    }

    @Test("E05 missing can occur with repo success and unestablished inventory")
    func e05WithRepoSuccess() {
        let state = DebtDataStateBuilder.build(
            semanticInput(establishment: .unestablished)
        )
        #expect(state == .missing)
    }

    @Test("E01 partial with unestablished inventory and known repayment")
    func e01PartialWithRepayment() {
        let state = DebtDataStateBuilder.build(
            semanticInput(
                establishment: .unestablished,
                monthlyDebtPayment: Money(amount: 2500, currencyCode: "CNY")
            )
        )
        #expect(state == .partial)
    }

    @Test("debt pressure input only allowed for knownDebt state")
    func debtPressureGate() {
        let partialDebt = Debt(
            userId: UUID(),
            outstandingBalance: Money(amount: 5000, currencyCode: "CNY"),
            status: .active,
            profileCompleteness: 0.9
        )
        let partialState = DebtDataStateBuilder.build(
            semanticInput(debts: [partialDebt], establishment: .partial)
        )
        #expect(partialState == .partial)
        #expect(partialState != .knownDebt)

        let knownState = DebtDataStateBuilder.build(
            semanticInput(debts: [partialDebt], establishment: .confirmedComplete)
        )
        #expect(knownState == .knownDebt)
    }

    @Test("DTI partial rule remains allowed under partial debt state")
    func dtiPartialRule() {
        let input = FinancialRiskPolicyInput(
            minimumBalance: .known(Money(amount: 5000, currencyCode: "CNY")),
            safeBalance: .known(Money(amount: 2000, currencyCode: "CNY")),
            estimatedMonthEndBalance: .known(Money(amount: 4500, currencyCode: "CNY")),
            monthlyIncome: .known(Money(amount: 10_000, currencyCode: "CNY")),
            monthlyExpense: .known(Money(amount: 3000, currencyCode: "CNY")),
            debtPaymentToIncomePercent: .known(25),
            debtPressureLevel: nil,
            debtDataState: .partial,
            dataCompleteness: FinancialDataCompleteness(
                debt: .partial,
                cashFlowProjection: .known,
                income: .known,
                expense: .known,
                requiredUnknownReasonCodes: []
            ),
            evaluatedAt: FinancialRiskPolicyVectorInputs.fixedEvaluatedAt
        )
        let assessment = FinancialRiskPolicyEngine.evaluate(input)
        #expect(assessment.signals.map(\.reasonCode).contains(.highDebtPaymentToIncome))
    }

    @Test("establishment state persists across store reload")
    func persistenceRoundTrip() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("youshu-debt-establishment-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fileURL = dir.appendingPathComponent("store.json")
        defer { try? FileManager.default.removeItem(at: dir) }

        let userId = UUID()
        let user = User(
            id: userId,
            displayName: "Persist",
            debtInventoryEstablishment: .confirmedComplete,
            debtInventoryEstablishmentSource: .userConfirmedNoDebt
        )
        let container = RepositoryContainer.fileBacked(url: fileURL)
        try await container.users.upsert(user)
        try await container.store.persist()

        let reloaded = try await YoushuStore.load(from: fileURL)
        let fetched = try await RepositoryContainer(store: reloaded).users.fetch(id: userId)
        #expect(fetched?.debtInventoryEstablishment == .confirmedComplete)
        #expect(fetched?.debtInventoryEstablishmentSource == .userConfirmedNoDebt)
        #expect(await reloaded.currentSnapshot().schemaVersion == YoushuSnapshot.currentSchemaVersion)
    }
}
