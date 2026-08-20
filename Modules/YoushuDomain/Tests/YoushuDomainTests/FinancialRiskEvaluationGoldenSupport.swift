import Foundation
import YoushuAI
import YoushuDomain
import YoushuFoundation

/// Canonical eval-case inputs routed through production Swift policy (tests + golden parity only).
enum FinancialRiskEvaluationGoldenSupport {
    static let smokeCaseIDs: [String] = [
        "A01_healthy_cashflow",
        "C03_high_monthly_payment",
        "B04_short_term_negative_balance",
        "C01_no_debt",
        "E05_missing_debt_data",
        "E01_partial_debt_data",
    ]

    static let allCaseIDs: [String] = EvalCasePolicyInputs.allCaseIDs

    static func repoRoot(from filePath: String = #filePath) -> URL {
        URL(fileURLWithPath: filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    static func loadGolden(_ caseID: String, filePath: String = #filePath) throws -> FinancialRiskEvaluationGoldenFixture {
        let url = repoRoot(from: filePath)
            .appendingPathComponent("TestFixtures/FinancialRiskEvaluationV2/\(caseID).json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(FinancialRiskEvaluationGoldenFixture.self, from: data)
    }

    static func mappedAssessment(for caseID: String) throws -> GatewayFinancialRiskAssessmentDTO {
        let assessment = try productionAssessment(for: caseID)
        return FinancialRiskAssessmentRequestMapper.toDTO(assessment)
    }

    static func productionAssessment(for caseID: String) throws -> FinancialRiskAssessment {
        switch caseID {
        case "C03_high_monthly_payment":
            return FinancialRiskPolicyEngine.evaluate(evalC03PolicyInput())
        case "C01_no_debt":
            return productionC01Assessment()
        case "E05_missing_debt_data":
            return productionE05Assessment()
        case "E01_partial_debt_data":
            return productionE01Assessment()
        default:
            if let input = EvalCasePolicyInputs.evalPolicyInput(for: caseID) {
                return FinancialRiskPolicyEngine.evaluate(input)
            }
            throw GoldenSupportError.unsupportedCase(caseID)
        }
    }

    static func makeGoldenFixture(for caseID: String) throws -> FinancialRiskEvaluationGoldenFixture {
        let assessment = try mappedAssessment(for: caseID)
        let vectorID = EvalCasePolicyInputs.policyVectorID(for: caseID)
        let productionScenario: String?
        if EvalCasePolicyInputs.productionWiredCaseIDs.contains(caseID) {
            productionScenario = caseID
        } else {
            productionScenario = nil
        }
        return FinancialRiskEvaluationGoldenFixture(
            caseId: caseID,
            assessmentTruthSource: "swift-policy-golden",
            generationPath: EvalCasePolicyInputs.generationPath(for: caseID),
            policyVectorId: vectorID,
            productionScenario: productionScenario,
            financialRiskAssessment: assessment
        )
    }

    /// Matches eval C03 envelope semantics: DTI 40%, no debtPressureLevel fact.
    static func evalC03PolicyInput() -> FinancialRiskPolicyInput {
        FinancialRiskPolicyInput(
            minimumBalance: .known(money(5000)),
            safeBalance: .missing(currencyCode: "CNY"),
            estimatedMonthEndBalance: .known(money(5000)),
            monthlyIncome: .known(money(5000)),
            monthlyExpense: .known(money(3000)),
            debtPaymentToIncomePercent: .known(40),
            debtPressureLevel: nil,
            debtDataState: .knownDebt,
            dataCompleteness: FinancialDataCompleteness(
                debt: .known,
                cashFlowProjection: .known,
                income: .known,
                expense: .known
            ),
            evaluatedAt: FinancialRiskPolicyVectorInputs.fixedEvaluatedAt
        )
    }

    static func productionC01Assessment() -> FinancialRiskAssessment {
        let calendar = utcCalendar
        let asOf = date(2024, 6, 20, calendar: calendar)
        let account = Account(
            userId: syntheticUserID,
            name: "现金",
            type: .cash,
            openingBalance: money(15_000)
        )
        let paidOff = Debt(
            userId: syntheticUserID,
            lender: "已结清",
            outstandingBalance: money(0),
            status: .paidOff
        )
        let txs = [
            incomeTransaction(accountId: account.id, amount: 12_000, on: date(2024, 6, 5, calendar: calendar)),
            expenseTransaction(accountId: account.id, amount: 3_000, on: date(2024, 6, 7, calendar: calendar)),
        ]
        return assessProduction(
            accounts: [account],
            transactions: txs,
            debts: [paidOff],
            asOf: asOf,
            debtInventoryEstablishment: .confirmedComplete,
            calendar: calendar
        )
    }

    static func productionE01Assessment() -> FinancialRiskAssessment {
        let calendar = utcCalendar
        let asOf = date(2024, 6, 15, calendar: calendar)
        let account = Account(
            userId: syntheticUserID,
            name: "现金",
            type: .cash,
            openingBalance: money(20_000)
        )
        let txs = [
            incomeTransaction(accountId: account.id, amount: 10_000, on: date(2024, 6, 4, calendar: calendar)),
            repaymentTransaction(accountId: account.id, amount: 2_500, on: date(2024, 6, 9, calendar: calendar)),
        ]
        return assessProduction(
            accounts: [account],
            transactions: txs,
            debts: [],
            asOf: asOf,
            calendar: calendar
        )
    }

    static func productionE05Assessment() -> FinancialRiskAssessment {
        let calendar = utcCalendar
        let asOf = date(2024, 6, 12, calendar: calendar)
        let account = Account(
            userId: syntheticUserID,
            name: "现金",
            type: .cash,
            openingBalance: money(10_000)
        )
        let txs = [
            incomeTransaction(accountId: account.id, amount: 8_000, on: date(2024, 6, 2, calendar: calendar)),
        ]
        return assessProduction(
            accounts: [account],
            transactions: txs,
            debts: [],
            asOf: asOf,
            debtInventoryLoadSucceeded: true,
            debtInventoryEstablishment: .unestablished,
            calendar: calendar
        )
    }

    private static let syntheticUserID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private static let safeBalance = Money(amount: 2_000, currencyCode: "CNY")

    private static var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private static func assessProduction(
        accounts: [Account],
        transactions: [Transaction],
        debts: [Debt],
        asOf: Date,
        debtInventoryLoadSucceeded: Bool = true,
        debtInventoryEstablishment: DebtInventoryEstablishmentState = .unestablished,
        calendar: Calendar
    ) -> FinancialRiskAssessment {
        let source = FinancialContextBuilder.Source(
            accounts: accounts,
            transactions: transactions,
            debts: debts,
            asOf: asOf,
            calendar: calendar,
            safeBalance: safeBalance
        )
        let context = FinancialContextBuilder.build(source)
        let facts = MonthlySummaryFactsEnricher.enrich(
            FinancialContextBuilder.monthlySummaryFacts(from: context),
            context: context,
            safeBalance: safeBalance
        )
        let assembly = FinancialRiskAssessmentService.assemblyContext(
            source: source,
            context: context,
            enrichedFacts: facts,
            safeBalance: safeBalance,
            debtInventoryLoadSucceeded: debtInventoryLoadSucceeded,
            debtInventoryEstablishment: debtInventoryEstablishment,
            evaluatedAt: asOf
        )
        return FinancialRiskAssessmentService.assess(assembly)
    }

    private static func money(_ amount: Decimal) -> Money {
        Money(amount: amount, currencyCode: "CNY")
    }

    private static func date(_ y: Int, _ m: Int, _ d: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private static func incomeTransaction(accountId: UUID, amount: Decimal, on day: Date) -> Transaction {
        Transaction(
            userId: syntheticUserID,
            accountId: accountId,
            amount: money(amount),
            date: day,
            category: "工资",
            transactionType: .income
        )
    }

    private static func expenseTransaction(accountId: UUID, amount: Decimal, on day: Date) -> Transaction {
        Transaction(
            userId: syntheticUserID,
            accountId: accountId,
            amount: money(amount),
            date: day,
            category: "生活",
            transactionType: .expense
        )
    }

    private static func repaymentTransaction(accountId: UUID, amount: Decimal, on day: Date) -> Transaction {
        Transaction(
            userId: syntheticUserID,
            accountId: accountId,
            amount: money(amount),
            date: day,
            category: "还款",
            transactionType: .repayment
        )
    }
}

struct FinancialRiskEvaluationGoldenFixture: Codable, Equatable {
    let caseId: String
    let assessmentTruthSource: String
    let generationPath: String
    let policyVectorId: String?
    let productionScenario: String?
    let financialRiskAssessment: GatewayFinancialRiskAssessmentDTO
}

enum GoldenSupportError: Error, CustomStringConvertible {
    case missingVector(String)
    case unsupportedCase(String)

    var description: String {
        switch self {
        case let .missingVector(id):
            return "missing policy vector \(id)"
        case let .unsupportedCase(id):
            return "unsupported golden case \(id)"
        }
    }
}
