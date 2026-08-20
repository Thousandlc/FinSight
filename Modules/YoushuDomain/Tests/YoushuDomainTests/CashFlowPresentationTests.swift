import Foundation
import Testing
import YoushuDomain
import YoushuFoundation

@Suite("Cash flow presentation")
struct CashFlowPresentationTests {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func sampleProjection(
        horizon: CashFlowHorizon,
        ending: Decimal,
        minimum: Decimal = 1_000,
        withRisk: Bool = false
    ) -> CashFlowProjection {
        let currency = "CNY"
        let money = { Money(amount: $0, currencyCode: currency) }
        let drivers = [
            CashFlowDriver(
                date: date(2024, 9, 10),
                amount: money(3_000),
                signedAmount: money(3_000),
                kind: .historicalIncome,
                label: "工资"
            ),
            CashFlowDriver(
                date: date(2024, 9, 12),
                amount: money(500),
                signedAmount: money(-500),
                kind: .fixedExpense,
                label: "房租"
            ),
            CashFlowDriver(
                date: date(2024, 9, 18),
                amount: money(800),
                signedAmount: money(-800),
                kind: .debtRepayment,
                label: "信用卡"
            ),
            CashFlowDriver(
                date: date(2024, 9, 20),
                amount: money(200),
                signedAmount: money(-200),
                kind: .historicalExpense,
                label: "餐饮"
            ),
        ]
        let risk: CashFlowRisk? = withRisk ? CashFlowRisk(
            minimumBalance: money(minimum),
            minimumBalanceDate: date(2024, 9, 18),
            peakRepayment: money(800),
            peakRepaymentDate: date(2024, 9, 18),
            safeBalance: money(2_000),
            drivers: drivers.filter { $0.kind == .debtRepayment },
            explanationFacts: CashFlowExplanationFacts(
                minimumBalance: money(minimum),
                minimumBalanceDate: date(2024, 9, 18),
                majorDrivers: drivers.filter { $0.signedAmount.amount < 0 },
                safeBalance: money(2_000),
                isBelowSafeBalance: true
            )
        ) : nil

        return CashFlowProjection(
            horizon: horizon,
            startingBalance: money(5_000),
            endingBalance: money(ending),
            minimumBalance: money(minimum),
            minimumBalanceDate: date(2024, 9, 18),
            peakRepayment: money(800),
            peakRepaymentDate: date(2024, 9, 18),
            drivers: drivers,
            risk: risk
        )
    }

    @Test("horizon titles")
    func horizonTitles() {
        #expect(CashFlowPresentation.horizonTitle(.days7) == "未来 7 天")
        #expect(CashFlowPresentation.horizonTitle(.days30) == "未来 30 天")
        #expect(CashFlowPresentation.horizonTitle(.days60) == "未来 60 天")
        #expect(CashFlowPresentation.horizonTitle(.days90) == "未来 90 天")
    }

    @Test("maps ending balance from projection")
    func endingBalanceMapping() {
        let projection = sampleProjection(horizon: .days30, ending: 6_300)
        let presentation = CashFlowPresentation.makeHorizonPresentation(from: projection, calendar: calendar)
        #expect(presentation.endingBalance.amount == 6_300)
    }

    @Test("maps risk status")
    func riskStatusMapping() {
        let safe = CashFlowPresentation.status(for: sampleProjection(horizon: .days7, ending: 8_520))
        let risky = CashFlowPresentation.status(
            for: sampleProjection(horizon: .days90, ending: 2_100, minimum: 1_200, withRisk: true)
        )
        #expect(safe == .safe)
        #expect(risky == .risk)
        #expect(CashFlowPresentation.makeHorizonPresentation(from: sampleProjection(horizon: .days90, ending: 2_100, withRisk: true)).statusText == "风险")
    }

    @Test("builds risk summary from existing risk facts")
    func riskSummary() {
        let projection = sampleProjection(horizon: .days30, ending: 1_500, minimum: 1_200, withRisk: true)
        let presentation = CashFlowPresentation.makeHorizonPresentation(from: projection, calendar: calendar)
        #expect(presentation.riskSummary?.contains("9月18日") == true)
        #expect(presentation.riskSummary?.contains("¥") == true)
    }

    @Test("aggregates drivers by kind")
    func driverBreakdown() {
        let breakdown = CashFlowPresentation.driverBreakdown(
            from: sampleProjection(horizon: .days30, ending: 6_300).drivers
        )
        #expect(breakdown.income.amount == 3_000)
        #expect(breakdown.fixedExpense.amount == 500)
        #expect(breakdown.debtRepayment.amount == 800)
        #expect(breakdown.otherExpense.amount == 200)
    }

    @Test("section supports partial projections")
    func partialProjections() {
        let overview = HomeOverview(
            availableFunds: Money(amount: 5_000, currencyCode: "CNY"),
            cashFlowProjections: [
                sampleProjection(horizon: .days7, ending: 8_520),
                sampleProjection(horizon: .days30, ending: 6_300),
            ],
            hasAccounts: true,
            hasTransactions: true
        )
        let section = CashFlowPresentation.makeSection(from: overview, calendar: calendar)
        #expect(section.isEmpty == false)
        #expect(section.horizons.count == 2)
        #expect(section.horizons.map(\.horizon) == [.days7, .days30])
    }

    @Test("empty projections show empty message")
    func emptyProjections() {
        let section = CashFlowPresentation.makeSection(from: HomeOverview(), calendar: calendar)
        #expect(section.isEmpty)
        #expect(section.emptyMessage == "目前还没有足够的数据生成现金流预测。")
    }

    @Test("footer summary uses overview risk when present")
    func footerSummaryWithRisk() {
        let projection = sampleProjection(horizon: .days30, ending: 1_500, minimum: 1_200, withRisk: true)
        let overview = HomeOverview(
            cashFlowProjections: [projection],
            cashFlowRisk: projection.risk,
            hasAccounts: true,
            hasTransactions: true
        )
        let summary = CashFlowPresentation.footerSummary(for: overview, calendar: calendar)
        #expect(summary.contains("9月18日"))
    }

    @Test("footer summary avoids invented numbers when no risk")
    func footerSummaryWithoutRisk() {
        let overview = HomeOverview(
            cashFlowProjections: [
                sampleProjection(horizon: .days7, ending: 8_520),
                sampleProjection(horizon: .days90, ending: 4_800),
            ],
            hasAccounts: true,
            hasTransactions: true
        )
        let summary = CashFlowPresentation.footerSummary(for: overview, calendar: calendar)
        #expect(summary == "未来 90 天预计不会出现明显资金压力。")
    }

    @Test("section marks insufficient data when no transactions")
    func insufficientDataMessage() {
        let overview = HomeOverview(
            cashFlowProjections: [sampleProjection(horizon: .days7, ending: 8_520)],
            hasAccounts: true,
            hasTransactions: false
        )
        let section = CashFlowPresentation.makeSection(from: overview, calendar: calendar)
        #expect(section.insufficientDataMessage?.contains("数据还不够") == true)
    }

    @Test("detail preserves engine ending balances")
    func detailMatchesEngineOutput() {
        let projections = CashFlowHorizon.allCases.map {
            sampleProjection(horizon: $0, ending: Decimal(10_000 - $0.rawValue))
        }
        let overview = HomeOverview(
            cashFlowProjections: projections,
            hasAccounts: true,
            hasTransactions: true
        )
        let detail = CashFlowPresentation.makeDetail(from: overview, calendar: calendar)
        #expect(detail.count == 4)
        #expect(detail.map(\.endingBalance.amount) == [9_993, 9_970, 9_940, 9_910])
    }
}
