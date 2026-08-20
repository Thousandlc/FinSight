import Foundation

public struct AIGatewayConfiguration: Sendable, Equatable {
    public var baseURL: URL
    public var timeout: TimeInterval
    public var schemaVersion: String
    public var tokenAccountKey: String

    public init(
        baseURL: URL,
        timeout: TimeInterval = 30,
        schemaVersion: String = "v1",
        tokenAccountKey: String = "youshu-ai-gateway"
    ) {
        self.baseURL = baseURL
        self.timeout = timeout
        self.schemaVersion = schemaVersion
        self.tokenAccountKey = tokenAccountKey
    }
}

public enum FinancialAssistingMode: Sendable, Equatable {
    case mock
    case remoteMonthlySummaryOnly
}

public enum GatewayOperation: String, Codable, Sendable {
    case monthlySummary
    case ask
    case insight
    case purchaseScenario
}
