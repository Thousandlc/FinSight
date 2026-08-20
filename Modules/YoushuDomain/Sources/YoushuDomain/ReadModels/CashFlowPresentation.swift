import Foundation
import YoushuFoundation

/// 首页/详情页现金流展示状态（仅映射，不重新计算现金流）。
public enum CashFlowPresentationStatus: String, Equatable, Sendable {
    case safe
    case risk

    public var displayText: String {
        switch self {
        case .safe: "安全"
        case .risk: "风险"
        }
    }
}

/// 按 Kind 汇总后的驱动因素金额（对已有 signedAmount 做 presentation aggregation）。
public struct CashFlowDriverBreakdown: Equatable, Sendable, Hashable {
    public var income: Money
    public var fixedExpense: Money
    public var debtRepayment: Money
    public var otherExpense: Money

    public init(
        income: Money = .zeroCNY,
        fixedExpense: Money = .zeroCNY,
        debtRepayment: Money = .zeroCNY,
        otherExpense: Money = .zeroCNY
    ) {
        self.income = income
        self.fixedExpense = fixedExpense
        self.debtRepayment = debtRepayment
        self.otherExpense = otherExpense
    }
}

/// 单个时间窗口的现金流展示模型。
public struct CashFlowHorizonPresentation: Equatable, Sendable, Hashable, Identifiable {
    public var id: Int { horizon.rawValue }
    public var horizon: CashFlowHorizon
    public var title: String
    public var endingBalance: Money
    public var status: CashFlowPresentationStatus
    public var statusText: String
    public var minimumBalance: Money
    public var minimumBalanceDate: Date
    public var peakRepayment: Money?
    public var peakRepaymentDate: Date?
    public var driverBreakdown: CashFlowDriverBreakdown
    public var riskSummary: String?

    public init(
        horizon: CashFlowHorizon,
        title: String,
        endingBalance: Money,
        status: CashFlowPresentationStatus,
        statusText: String,
        minimumBalance: Money,
        minimumBalanceDate: Date,
        peakRepayment: Money? = nil,
        peakRepaymentDate: Date? = nil,
        driverBreakdown: CashFlowDriverBreakdown = CashFlowDriverBreakdown(),
        riskSummary: String? = nil
    ) {
        self.horizon = horizon
        self.title = title
        self.endingBalance = endingBalance
        self.status = status
        self.statusText = statusText
        self.minimumBalance = minimumBalance
        self.minimumBalanceDate = minimumBalanceDate
        self.peakRepayment = peakRepayment
        self.peakRepaymentDate = peakRepaymentDate
        self.driverBreakdown = driverBreakdown
        self.riskSummary = riskSummary
    }
}

/// 首页「未来现金流」模块展示模型。
public struct CashFlowSectionPresentation: Equatable, Sendable {
    public var horizons: [CashFlowHorizonPresentation]
    public var footerSummary: String
    public var isEmpty: Bool
    public var emptyMessage: String?
    public var insufficientDataMessage: String?

    public init(
        horizons: [CashFlowHorizonPresentation] = [],
        footerSummary: String = "",
        isEmpty: Bool = false,
        emptyMessage: String? = nil,
        insufficientDataMessage: String? = nil
    ) {
        self.horizons = horizons
        self.footerSummary = footerSummary
        self.isEmpty = isEmpty
        self.emptyMessage = emptyMessage
        self.insufficientDataMessage = insufficientDataMessage
    }
}

/// 将已有 CashFlowProjection 转换为 UI 展示信息。不执行新的现金流预测。
public enum CashFlowPresentation {
    public static func horizonTitle(_ horizon: CashFlowHorizon) -> String {
        "未来 \(horizon.rawValue) 天"
    }

    public static func pickerTitle(_ horizon: CashFlowHorizon) -> String {
        "\(horizon.rawValue) 天"
    }

    public static func status(for projection: CashFlowProjection) -> CashFlowPresentationStatus {
        projection.risk != nil ? .risk : .safe
    }

    public static func driverBreakdown(from drivers: [CashFlowDriver]) -> CashFlowDriverBreakdown {
        let currency = drivers.first?.signedAmount.currencyCode ?? "CNY"

        func sumKinds(_ kinds: Set<CashFlowDriver.Kind>, magnitude: Bool) -> Money {
            let total = drivers
                .filter { kinds.contains($0.kind) }
                .reduce(Decimal.zero) { partial, driver in
                    let amount = magnitude ? abs(driver.signedAmount.amount) : driver.signedAmount.amount
                    return partial + amount
                }
            return Money(amount: total, currencyCode: currency)
        }

        return CashFlowDriverBreakdown(
            income: sumKinds([.historicalIncome, .knownFutureIncome], magnitude: false),
            fixedExpense: sumKinds([.fixedExpense, .recurringExpense], magnitude: true),
            debtRepayment: sumKinds([.debtRepayment], magnitude: true),
            otherExpense: sumKinds([.historicalExpense], magnitude: true)
        )
    }

    public static func makeHorizonPresentation(
        from projection: CashFlowProjection,
        calendar: Calendar = .current
    ) -> CashFlowHorizonPresentation {
        let status = status(for: projection)
        return CashFlowHorizonPresentation(
            horizon: projection.horizon,
            title: horizonTitle(projection.horizon),
            endingBalance: projection.endingBalance,
            status: status,
            statusText: status.displayText,
            minimumBalance: projection.minimumBalance,
            minimumBalanceDate: projection.minimumBalanceDate,
            peakRepayment: projection.peakRepayment,
            peakRepaymentDate: projection.peakRepaymentDate,
            driverBreakdown: driverBreakdown(from: projection.drivers),
            riskSummary: projection.risk.map { CashFlowExplanationBuilder.build(from: $0, calendar: calendar) }
        )
    }

    public static func makeSection(
        from overview: HomeOverview,
        calendar: Calendar = .current
    ) -> CashFlowSectionPresentation {
        let sorted = overview.cashFlowProjections.sorted { $0.horizon.rawValue < $1.horizon.rawValue }

        if sorted.isEmpty {
            return CashFlowSectionPresentation(
                isEmpty: true,
                emptyMessage: "目前还没有足够的数据生成现金流预测。"
            )
        }

        let horizons = sorted.map { makeHorizonPresentation(from: $0, calendar: calendar) }
        let insufficientDataMessage = overview.hasTransactions
            ? nil
            : "目前数据还不够，继续记录几笔收入和支出后，我们可以更准确地预测未来现金流。"

        return CashFlowSectionPresentation(
            horizons: horizons,
            footerSummary: footerSummary(for: overview, calendar: calendar),
            isEmpty: false,
            insufficientDataMessage: insufficientDataMessage
        )
    }

    public static func makeDetail(
        from overview: HomeOverview,
        calendar: Calendar = .current
    ) -> [CashFlowHorizonPresentation] {
        overview.cashFlowProjections
            .sorted { $0.horizon.rawValue < $1.horizon.rawValue }
            .map { makeHorizonPresentation(from: $0, calendar: calendar) }
    }

    public static func footerSummary(
        for overview: HomeOverview,
        calendar: Calendar = .current
    ) -> String {
        if let risk = overview.cashFlowRisk {
            return CashFlowExplanationBuilder.build(from: risk, calendar: calendar)
        }

        if let longest = overview.cashFlowProjections.max(by: { $0.horizon.rawValue < $1.horizon.rawValue }) {
            return "未来 \(longest.horizon.rawValue) 天预计不会出现明显资金压力。"
        }

        return "未来 90 天预计不会出现明显资金压力。"
    }

    public static func formatDate(_ date: Date, calendar: Calendar = .current) -> String {
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return "\(month)月\(day)日"
    }
}
