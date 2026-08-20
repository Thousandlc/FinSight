import Foundation
import YoushuDomain

public protocol AIGatewayClientProtocol: Sendable {
    func completeMonthlySummary(
        request: AssistantRequestDTO,
        facts: MonthlySummaryFacts,
        riskAssessment: FinancialRiskAssessment
    ) async throws -> (draft: AssistantAnswerDraft, modelAlias: String, requestId: String)
}

public struct AIGatewayClient: AIGatewayClientProtocol {
    public static let financialAssistantPath = "/v1/ai/financial-assistant"

    private let configuration: AIGatewayConfiguration
    private let transport: any GatewayHTTPTransport
    private let tokenStore: (any SecureTokenStoring)?
    private let maxRetryCount: Int
    private let retryDelaySeconds: UInt64

    public init(
        configuration: AIGatewayConfiguration,
        transport: any GatewayHTTPTransport,
        tokenStore: (any SecureTokenStoring)? = nil,
        maxRetryCount: Int = 1,
        retryDelaySeconds: UInt64 = 2
    ) {
        self.configuration = configuration
        self.transport = transport
        self.tokenStore = tokenStore
        self.maxRetryCount = maxRetryCount
        self.retryDelaySeconds = retryDelaySeconds
    }

    public func completeMonthlySummary(
        request: AssistantRequestDTO,
        facts: MonthlySummaryFacts,
        riskAssessment: FinancialRiskAssessment
    ) async throws -> (draft: AssistantAnswerDraft, modelAlias: String, requestId: String) {
        let requestId = UUID().uuidString
        var attempt = 0
        var lastError: AIGatewayError?

        while attempt <= maxRetryCount {
            if attempt > 0 {
                try await Task.sleep(nanoseconds: retryDelaySeconds * 1_000_000_000)
            }
            do {
                return try await performMonthlySummary(
                    request: request,
                    facts: facts,
                    riskAssessment: riskAssessment,
                    requestId: requestId
                )
            } catch let error as AIGatewayError {
                lastError = error
                if error.isRetryable, attempt < maxRetryCount {
                    attempt += 1
                    continue
                }
                throw error
            } catch {
                lastError = .networkFailure(error.localizedDescription)
                if attempt < maxRetryCount {
                    attempt += 1
                    continue
                }
                throw AIGatewayError.networkFailure(error.localizedDescription)
            }
        }
        throw lastError ?? AIGatewayError.internalError
    }

    private func performMonthlySummary(
        request: AssistantRequestDTO,
        facts: MonthlySummaryFacts,
        riskAssessment: FinancialRiskAssessment,
        requestId: String
    ) async throws -> (draft: AssistantAnswerDraft, modelAlias: String, requestId: String) {
        let envelope = GatewayRequestEnvelope(
            schemaVersion: configuration.schemaVersion,
            requestId: requestId,
            operation: .monthlySummary,
            assistantRequest: request,
            monthlySummaryFacts: GatewayMonthlySummaryFactsMapper.toDTO(facts),
            financialRiskAssessment: FinancialRiskAssessmentRequestMapper.toDTO(riskAssessment)
        )

        var headers = [
            "Content-Type": "application/json",
            "X-Youshu-Request-Id": requestId,
        ]
        if let tokenStore, let token = try tokenStore.load(account: configuration.tokenAccountKey) {
            headers["Authorization"] = "Bearer \(token)"
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]

        let httpRequest = GatewayHTTPRequest(
            url: configuration.baseURL.appendingPathComponent(Self.financialAssistantPath),
            method: "POST",
            headers: headers,
            body: try encoder.encode(envelope),
            timeout: configuration.timeout
        )

        let started = Date()
        let response: GatewayHTTPResponse
        do {
            response = try await transport.perform(httpRequest)
        } catch let error as URLError where error.code == .timedOut {
            logGateway(requestId: requestId, operation: GatewayOperation.monthlySummary.rawValue, status: 504, duration: Date().timeIntervalSince(started), error: "providerTimeout")
            throw AIGatewayError.providerTimeout
        } catch {
            logGateway(requestId: requestId, operation: GatewayOperation.monthlySummary.rawValue, status: 0, duration: Date().timeIntervalSince(started), error: "networkFailure")
            throw AIGatewayError.networkFailure(error.localizedDescription)
        }

        logGateway(
            requestId: requestId,
            operation: GatewayOperation.monthlySummary.rawValue,
            status: response.statusCode,
            duration: Date().timeIntervalSince(started),
            error: response.statusCode >= 400 ? "httpError" : nil
        )

        if (200..<300).contains(response.statusCode) {
            return try decodeSuccess(data: response.data, expectedRequestId: requestId)
        }
        throw decodeError(data: response.data, statusCode: response.statusCode)
    }

    private func decodeSuccess(
        data: Data,
        expectedRequestId: String
    ) throws -> (draft: AssistantAnswerDraft, modelAlias: String, requestId: String) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let envelope = try? decoder.decode(GatewaySuccessResponseEnvelope.self, from: data) else {
            throw AIGatewayError.decodingFailed
        }
        guard envelope.schemaVersion == configuration.schemaVersion else {
            throw AIGatewayError.unsupportedSchemaVersion
        }
        guard envelope.requestId == expectedRequestId else {
            throw AIGatewayError.requestIdMismatch(expected: expectedRequestId, actual: envelope.requestId)
        }
        let draft = GatewayAnswerDraftMapper.toDomain(envelope.draft)
        return (draft, envelope.modelAlias, envelope.requestId)
    }

    private func decodeError(data: Data, statusCode: Int) -> AIGatewayError {
        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(GatewayErrorResponseEnvelope.self, from: data) {
            return mapErrorCode(envelope.error.code, retryAfter: envelope.error.retryAfterSeconds)
        }
        switch statusCode {
        case 400: return .invalidRequest
        case 401: return .unauthorized
        case 429: return .rateLimited(retryAfterSeconds: nil)
        case 502: return .invalidProviderResponse
        case 503: return .providerUnavailable
        case 504: return .providerTimeout
        default: return statusCode >= 500 ? .internalError : .invalidRequest
        }
    }

    private func mapErrorCode(_ code: String, retryAfter: Int?) -> AIGatewayError {
        switch code {
        case "invalidRequest": return .invalidRequest
        case "unauthorized": return .unauthorized
        case "rateLimited": return .rateLimited(retryAfterSeconds: retryAfter)
        case "providerUnavailable": return .providerUnavailable
        case "providerTimeout": return .providerTimeout
        case "invalidProviderResponse": return .invalidProviderResponse
        case "unsupportedSchemaVersion": return .unsupportedSchemaVersion
        case "unsupportedOperation": return .unsupportedOperation
        case "internalError": return .internalError
        default: return .internalError
        }
    }

    private func logGateway(
        requestId: String,
        operation: String,
        status: Int,
        duration: TimeInterval,
        error: String?
    ) {
        #if DEBUG
        if let error {
            print("[youshu.ai] gateway op=\(operation) requestId=\(requestId) status=\(status) durationMs=\(Int(duration * 1000)) error=\(error)")
        } else {
            print("[youshu.ai] gateway op=\(operation) requestId=\(requestId) status=\(status) durationMs=\(Int(duration * 1000))")
        }
        #endif
    }
}
