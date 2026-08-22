import Foundation
import YoushuDomain
import YoushuFoundation

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
        if let recorder = ObservabilityEmission.recorder {
            return try await performWithRetry(
                request: request,
                facts: facts,
                riskAssessment: riskAssessment,
                recorder: recorder,
                emitTerminal: false
            )
        }
        let recorder = ObservabilityOperationRecorder(operation: .monthlySummary)
        return try await ObservabilityEmission.$recorder.withValue(recorder) {
            try await performWithRetry(
                request: request,
                facts: facts,
                riskAssessment: riskAssessment,
                recorder: recorder,
                emitTerminal: true
            )
        }
    }

    private func performWithRetry(
        request: AssistantRequestDTO,
        facts: MonthlySummaryFacts,
        riskAssessment: FinancialRiskAssessment,
        recorder: ObservabilityOperationRecorder,
        emitTerminal: Bool
    ) async throws -> (draft: AssistantAnswerDraft, modelAlias: String, requestId: String) {
        var attempt = 0
        var lastError: AIGatewayError?

        while attempt <= maxRetryCount {
            if attempt > 0 {
                recorder.noteClientRetry()
                try await Task.sleep(nanoseconds: retryDelaySeconds * 1_000_000_000)
            }
            do {
                let result = try await performMonthlySummary(
                    request: request,
                    facts: facts,
                    riskAssessment: riskAssessment,
                    recorder: recorder
                )
                recorder.noteSuccess()
                if emitTerminal {
                    ObservabilityEmission.emitTerminal(recorder, outcome: .success)
                }
                return result
            } catch is CancellationError {
                recorder.noteFailure(
                    ObservabilityErrorMapping.classify(code: .cancelled, stage: .clientTransport)
                )
                if emitTerminal {
                    ObservabilityEmission.emitTerminal(recorder, outcome: .cancelled)
                }
                throw CancellationError()
            } catch let error as AIGatewayError {
                recorder.noteFailure(error.observabilityClassification)
                lastError = error
                if error.isRetryable, attempt < maxRetryCount {
                    attempt += 1
                    continue
                }
                if emitTerminal {
                    ObservabilityEmission.emitTerminal(recorder, outcome: .failed)
                }
                throw error
            } catch {
                recorder.noteFailure(error.observabilityClassification)
                lastError = .networkFailure("transportFailure")
                if attempt < maxRetryCount {
                    attempt += 1
                    continue
                }
                if emitTerminal {
                    ObservabilityEmission.emitTerminal(recorder, outcome: .failed)
                }
                throw AIGatewayError.networkFailure("transportFailure")
            }
        }
        let fallback = lastError ?? AIGatewayError.internalError
        recorder.noteFailure(fallback.observabilityClassification)
        if emitTerminal {
            ObservabilityEmission.emitTerminal(recorder, outcome: .failed)
        }
        throw fallback
    }

    private func performMonthlySummary(
        request: AssistantRequestDTO,
        facts: MonthlySummaryFacts,
        riskAssessment: FinancialRiskAssessment,
        recorder: ObservabilityOperationRecorder
    ) async throws -> (draft: AssistantAnswerDraft, modelAlias: String, requestId: String) {
        let requestId = recorder.requestId
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
        let body: Data
        do {
            body = try encoder.encode(envelope)
        } catch {
            recorder.noteFailure(
                ObservabilityErrorMapping.classify(
                    code: .serializationFailure,
                    stage: .requestSerialization
                )
            )
            recorder.noteSchemaStage(.requestEnvelope)
            throw AIGatewayError.invalidRequest
        }

        let httpRequest = GatewayHTTPRequest(
            url: configuration.baseURL.appendingPathComponent(Self.financialAssistantPath),
            method: "POST",
            headers: headers,
            body: body,
            timeout: configuration.timeout
        )

        let response: GatewayHTTPResponse
        do {
            response = try await transport.perform(httpRequest)
        } catch let error as URLError where error.code == .timedOut {
            recorder.noteFailure(
                ObservabilityErrorMapping.classify(code: .timeout, stage: .clientTransport)
            )
            throw AIGatewayError.providerTimeout
        } catch let error as URLError where error.code == .cancelled {
            recorder.noteFailure(
                ObservabilityErrorMapping.classify(code: .cancelled, stage: .clientTransport)
            )
            throw CancellationError()
        } catch let error as URLError {
            recorder.noteFailure(ObservabilityErrorMapping.classify(error))
            throw AIGatewayError.networkFailure("transportFailure")
        } catch is CancellationError {
            recorder.noteFailure(
                ObservabilityErrorMapping.classify(code: .cancelled, stage: .clientTransport)
            )
            throw CancellationError()
        } catch {
            recorder.noteFailure(
                ObservabilityErrorMapping.classify(code: .transportFailure, stage: .clientTransport)
            )
            throw AIGatewayError.networkFailure("transportFailure")
        }

        recorder.noteProvider(name: "bailian", status: String(response.statusCode))
        logGateway(
            requestId: requestId,
            operation: GatewayOperation.monthlySummary.rawValue,
            status: response.statusCode
        )

        if (200..<300).contains(response.statusCode) {
            return try decodeSuccess(data: response.data, expectedRequestId: requestId, recorder: recorder)
        }
        throw decodeError(data: response.data, statusCode: response.statusCode, recorder: recorder)
    }

    private func decodeSuccess(
        data: Data,
        expectedRequestId: String,
        recorder: ObservabilityOperationRecorder
    ) throws -> (draft: AssistantAnswerDraft, modelAlias: String, requestId: String) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let envelope = try? decoder.decode(GatewaySuccessResponseEnvelope.self, from: data) else {
            recorder.noteFailure(
                ObservabilityErrorMapping.classify(
                    code: .responseDecodeFailure,
                    stage: .clientResponseDecode
                )
            )
            recorder.noteSchemaStage(.clientDraft)
            throw AIGatewayError.decodingFailed
        }
        guard envelope.schemaVersion == configuration.schemaVersion else {
            recorder.noteFailure(
                ObservabilityErrorMapping.classify(
                    code: .unsupportedSchemaVersion,
                    stage: .clientResponseDecode
                )
            )
            throw AIGatewayError.unsupportedSchemaVersion
        }
        guard envelope.requestId == expectedRequestId else {
            recorder.noteFailure(
                ObservabilityErrorMapping.classify(
                    code: .responseDecodeFailure,
                    stage: .clientResponseDecode
                )
            )
            throw AIGatewayError.requestIdMismatch(expected: expectedRequestId, actual: envelope.requestId)
        }
        recorder.noteProvider(name: "bailian", model: envelope.modelAlias)
        let draft = GatewayAnswerDraftMapper.toDomain(envelope.draft)
        return (draft, envelope.modelAlias, envelope.requestId)
    }

    private func decodeError(data: Data, statusCode: Int, recorder: ObservabilityOperationRecorder) -> AIGatewayError {
        let decoder = JSONDecoder()
        if let envelope = try? decoder.decode(GatewayErrorResponseEnvelope.self, from: data) {
            let mapped = AIGatewayError.mapGatewayErrorCode(
                envelope.error.code,
                retryAfter: envelope.error.retryAfterSeconds
            )
            let code = ObservabilityErrorCode(rawValue: envelope.error.code)
                ?? mapped.observabilityClassification.errorCode
            var classified = ObservabilityErrorMapping.classify(code: code, stage: .unknown)
            classified.retryability = mapped.isRetryable ? .retryable : .notRetryable
            recorder.noteFailure(classified)
            return mapped
        }
        let mapped: AIGatewayError
        switch statusCode {
        case 400: mapped = .invalidRequest
        case 401: mapped = .unauthorized
        case 429: mapped = .rateLimited(retryAfterSeconds: nil)
        case 502: mapped = .invalidProviderResponse
        case 503: mapped = .providerUnavailable
        case 504: mapped = .providerTimeout
        default: mapped = statusCode >= 500 ? .internalError : .invalidRequest
        }
        recorder.noteFailure(mapped.observabilityClassification)
        return mapped
    }

    private func logGateway(
        requestId: String,
        operation: String,
        status: Int
    ) {
        #if DEBUG
        print("[youshu.ai] gateway op=\(operation) requestId=\(requestId) status=\(status)")
        #endif
    }
}
