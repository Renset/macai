//
//  VertexAIHandler.swift
//  macai
//
//  Created by Link on 18.12.2025.
//

import AppKit
import CoreData
import Foundation
import UniformTypeIdentifiers

// MARK: - ADC Credentials

private struct ADCCredentials: Decodable {
    let clientId: String
    let clientSecret: String
    let refreshToken: String
    let type: String

    enum CodingKeys: String, CodingKey {
        case clientId = "client_id"
        case clientSecret = "client_secret"
        case refreshToken = "refresh_token"
        case type
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let expiresIn: Int
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

// MARK: - Token Manager

private actor VertexTokenManager {
    static let shared = VertexTokenManager()

    private var cachedToken: String?
    private var tokenExpiry: Date?

    private let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!

    func getAccessToken(session: URLSession) async throws -> String {
        // Return cached token if still valid (with 5-minute buffer)
        if let token = cachedToken,
            let expiry = tokenExpiry,
            Date() < expiry.addingTimeInterval(-300)
        {
            return token
        }

        let _ = try await ensureADCCredentials()
        // Read ADC credentials
        let credentials = try await readADCCredentials()

        // Exchange refresh token for access token
        let token = try await refreshAccessToken(credentials: credentials, session: session)
        return token
    }

    private func ensureADCCredentials() async throws -> Data {
        do {
            return try ADCCredentialsAccess.loadCredentialsData()
        }
        catch let error as ADCCredentialsAccessError {
            switch error {
            case .noBookmark:
                return try await ADCCredentialsAccess.promptAndStoreBookmark()
            default:
                throw error
            }
        }
    }

    private func readADCCredentials() async throws -> ADCCredentials {
        do {
            let data = try ADCCredentialsAccess.loadCredentialsData()
            let credentials = try JSONDecoder().decode(ADCCredentials.self, from: data)

            guard credentials.type == "authorized_user" else {
                throw APIError.unknown(
                    "ADC file is not an authorized_user type. Run 'gcloud auth application-default login'"
                )
            }

            return credentials
        }
        catch let error as ADCCredentialsAccessError {
            switch error {
            case .noBookmark:
                let data = try await ADCCredentialsAccess.promptAndStoreBookmark()
                let credentials = try JSONDecoder().decode(ADCCredentials.self, from: data)

                guard credentials.type == "authorized_user" else {
                    throw APIError.unknown(
                        "ADC file is not an authorized_user type. Run 'gcloud auth application-default login'"
                    )
                }

                return credentials
            default:
                throw error
            }
        }
    }

    private func refreshAccessToken(credentials: ADCCredentials, session: URLSession) async throws -> String {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "client_id": credentials.clientId,
            "client_secret": credentials.clientSecret,
            "refresh_token": credentials.refreshToken,
            "grant_type": "refresh_token",
        ]

        request.httpBody =
            body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.unauthorized
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)

        // Cache the token
        cachedToken = tokenResponse.accessToken
        tokenExpiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))

        return tokenResponse.accessToken
    }

    func clearCache() {
        cachedToken = nil
        tokenExpiry = nil
    }
}

// MARK: - Vertex AI Response Structures (reusing Gemini format)

private struct VertexGenerateRequest: Encodable {
    let contents: [GeminiContentRequest]
    let systemInstruction: GeminiContentRequest?
    let generationConfig: VertexGenerationConfig?
}

private struct VertexGenerationConfig: Encodable {
    let temperature: Float
}

// MARK: - Claude (Anthropic) Request/Response Structures for Vertex AI

private struct ClaudeVertexRequest: Encodable {
    let anthropicVersion: String
    let messages: [[String: Any]]
    let system: String?
    let stream: Bool
    let temperature: Float
    let maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case anthropicVersion = "anthropic_version"
        case messages
        case system
        case stream
        case temperature
        case maxTokens = "max_tokens"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(anthropicVersion, forKey: .anthropicVersion)

        // Manually encode messages array
        let messagesData = try JSONSerialization.data(withJSONObject: messages)
        let messagesJson = try JSONDecoder().decode([AnyCodable].self, from: messagesData)
        try container.encode(messagesJson, forKey: .messages)

        try container.encodeIfPresent(system, forKey: .system)
        try container.encode(stream, forKey: .stream)
        try container.encode(temperature, forKey: .temperature)
        try container.encode(maxTokens, forKey: .maxTokens)
    }
}

private struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        }
        else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        }
        else if let string = try? container.decode(String.self) {
            value = string
        }
        else if let int = try? container.decode(Int.self) {
            value = int
        }
        else if let double = try? container.decode(Double.self) {
            value = double
        }
        else if let bool = try? container.decode(Bool.self) {
            value = bool
        }
        else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let dict = value as? [String: Any] {
            try container.encode(dict.mapValues { AnyCodable($0) })
        }
        else if let array = value as? [Any] {
            try container.encode(array.map { AnyCodable($0) })
        }
        else if let string = value as? String {
            try container.encode(string)
        }
        else if let int = value as? Int {
            try container.encode(int)
        }
        else if let double = value as? Double {
            try container.encode(double)
        }
        else if let bool = value as? Bool {
            try container.encode(bool)
        }
        else {
            try container.encodeNil()
        }
    }
}

private struct VertexGenerateResponse: Decodable {
    let candidates: [VertexCandidate]?
}

private struct VertexCandidate: Decodable {
    let content: VertexContentResponse?
    let finishReason: String?
}

private struct VertexContentResponse: Decodable {
    let parts: [VertexPartResponse]?
}

private struct VertexPartResponse: Decodable {
    let text: String?
    let inlineData: VertexInlineDataResponse?
    let thoughtSignature: String?
}

private struct VertexInlineDataResponse: Decodable {
    let mimeType: String?
    let data: String?
}

private struct VertexErrorEnvelope: Decodable {
    let error: VertexAPIError
}

private struct VertexAPIError: Decodable {
    let code: Int?
    let message: String
    let status: String?
}

private struct VertexStreamParseResult {
    let delta: String?
    let finished: Bool
}

// MARK: - Vertex AI Handler

class VertexAIHandler: APIService {
    let name: String
    let baseURL: URL
    let model: String
    private let projectId: String
    private let region: String
    private let session: URLSession
    private var activeDataTask: Task<Void, Never>?
    private var activeStreamTask: Task<Void, Never>?
    private var lastResponseParts: [VertexPartResponse]?

    init(config: APIServiceConfiguration, session: URLSession) {
        self.name = config.name
        self.baseURL = config.apiUrl
        self.model = config.model
        self.projectId = config.gcpProjectId ?? ""
        self.region = config.gcpRegion ?? "us-central1"
        self.session = session
    }

    // MARK: - API Service Protocol

    func fetchModels() async throws -> [AIModel] {
        // Vertex AI does not provide a stable v1 REST API endpoint for listing publisher models.
        // Return the curated list of available models from configuration.
        return AppConstants.defaultApiConfigurations["vertex"]?.models.map { AIModel(id: $0) } ?? []
    }

    func sendMessage(
        _ requestMessages: [[String: String]],
        temperature: Float,
        completion: @escaping (Result<String, APIError>) -> Void
    ) {
        activeDataTask?.cancel()
        let task = Task {
            defer { self.activeDataTask = nil }
            do {
                let request = try await prepareRequest(
                    requestMessages: requestMessages,
                    temperature: temperature,
                    stream: false
                )

                let (data, response) = try await session.data(for: request)

                await MainActor.run {
                    let result = self.handleAPIResponse(response, data: data, error: nil)

                    switch result {
                    case .success(let payload):
                        guard let payload = payload else {
                            completion(.failure(.invalidResponse))
                            return
                        }

                        do {
                            if self.isClaudeModel() {
                                // Parse Claude response
                                if let (messageContent, _) = self.parseClaudeJSONResponse(data: payload) {
                                    completion(.success(messageContent))
                                }
                                else {
                                    completion(.failure(.decodingFailed("Failed to parse Claude response")))
                                }
                            }
                            else {
                                // Parse Gemini response
                                let decoder = self.makeDecoder()
                                let response = try decoder.decode(VertexGenerateResponse.self, from: payload)
                                self.lastResponseParts = response.candidates?.first?.content?.parts
                                var inlineDataCache: [String: String] = [:]
                                if let message = self.renderMessage(from: response, inlineDataCache: &inlineDataCache) {
                                    completion(.success(message))
                                }
                                else {
                                    completion(.failure(.decodingFailed("Empty Vertex AI response")))
                                }
                            }
                        }
                        catch {
                            if let envelope = try? self.makeDecoder().decode(VertexErrorEnvelope.self, from: payload) {
                                completion(.failure(.serverError(envelope.error.message)))
                            }
                            else {
                                completion(
                                    .failure(
                                        .decodingFailed(
                                            "Failed to decode Vertex AI response: \(error.localizedDescription)"
                                        )
                                    )
                                )
                            }
                        }

                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            }
            catch let apiError as APIError {
                await MainActor.run {
                    completion(.failure(apiError))
                }
            }
            catch {
                await MainActor.run {
                    completion(.failure(.requestFailed(error)))
                }
            }
        }
        activeDataTask = task
    }

    func sendMessageStream(_ requestMessages: [[String: String]], temperature: Float) async throws
        -> AsyncThrowingStream<String, Error>
    {
        let request = try await prepareRequest(
            requestMessages: requestMessages,
            temperature: temperature,
            stream: true
        )

        return AsyncThrowingStream { continuation in
            let streamTask = Task {
                defer { self.activeStreamTask = nil }
                do {
                    let (stream, response) = try await self.session.bytes(for: request)
                    let responseCheck = self.handleAPIResponse(response, data: nil, error: nil)

                    switch responseCheck {
                    case .failure(let error):
                        var errorData = Data()
                        for try await byte in stream {
                            errorData.append(byte)
                        }

                        if let envelope = try? self.makeDecoder().decode(VertexErrorEnvelope.self, from: errorData) {
                            continuation.finish(throwing: APIError.serverError(envelope.error.message))
                        }
                        else {
                            let message = String(data: errorData, encoding: .utf8) ?? error.localizedDescription
                            continuation.finish(throwing: APIError.serverError(message))
                        }
                        return

                    case .success:
                        break
                    }

                    if self.isClaudeModel() {
                        // Handle Claude streaming response
                        for try await line in stream.lines {
                            let (finished, error, content, _) = self.parseClaudeSSEEvent(line)

                            if let error = error {
                                continuation.finish(throwing: APIError.decodingFailed(error.localizedDescription))
                                break
                            }

                            if let content = content, !content.isEmpty {
                                continuation.yield(content)
                            }

                            if finished {
                                continuation.finish()
                                break
                            }
                        }
                    }
                    else {
                        // Handle Gemini streaming response
                        let decoder = self.makeDecoder()
                        var aggregatedText = ""
                        var inlineDataCache: [String: String] = [:]

                        for try await line in stream.lines {
                            if line.isEmpty { continue }

                            if line.hasPrefix("data:") {
                                let index = line.index(line.startIndex, offsetBy: "data:".count)
                                let payload = String(line[index...]).trimmingCharacters(in: .whitespacesAndNewlines)

                                if payload.isEmpty { continue }

                                let result = try self.parseStreamPayload(
                                    payload,
                                    decoder: decoder,
                                    aggregatedText: &aggregatedText,
                                    inlineDataCache: &inlineDataCache
                                )

                                if let delta = result.delta, !delta.isEmpty {
                                    continuation.yield(delta)
                                }

                                if result.finished {
                                    continuation.finish()
                                    return
                                }
                            }
                        }

                        continuation.finish()
                    }
                }
                catch let apiError as APIError {
                    continuation.finish(throwing: apiError)
                }
                catch {
                    continuation.finish(throwing: APIError.requestFailed(error))
                }
            }
            activeStreamTask?.cancel()
            activeStreamTask = streamTask
            continuation.onTermination = { _ in
                streamTask.cancel()
            }
        }
    }

    // MARK: - Request Preparation

    private func prepareRequest(
        requestMessages: [[String: String]],
        temperature: Float,
        stream: Bool
    ) async throws -> URLRequest {
        guard !projectId.isEmpty else {
            throw APIError.unknown("GCP Project ID is required for Vertex AI")
        }

        guard !region.isEmpty else {
            throw APIError.unknown("GCP Region is required for Vertex AI")
        }

        let accessToken = try await VertexTokenManager.shared.getAccessToken(session: session)

        guard let url = buildRequestURL(stream: stream) else {
            throw APIError.unknown("Invalid Vertex AI request URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = AppConstants.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        if stream {
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }

        let encoder = JSONEncoder()

        if isClaudeModel() {
            // Use Anthropic Messages API format for Claude models
            var systemMessage = ""
            var updatedRequestMessages = requestMessages

            if let firstMessage = requestMessages.first, firstMessage["role"] == "system" {
                systemMessage = firstMessage["content"] ?? ""
                updatedRequestMessages.removeFirst()
            }

            if updatedRequestMessages.isEmpty {
                throw APIError.unknown("Claude request requires at least one user or assistant message")
            }

            let jsonDict: [String: Any] = [
                "anthropic_version": "vertex-2023-10-16",
                "messages": updatedRequestMessages,
                "system": systemMessage,
                "stream": stream,
                "temperature": temperature,
                "max_tokens": 4096,
            ]

            request.httpBody = try JSONSerialization.data(withJSONObject: jsonDict, options: [])
        }
        else {
            // Use Gemini format for Google models
            let (systemInstruction, contents) = transformMessages(requestMessages)

            if contents.isEmpty {
                throw APIError.unknown("Vertex AI request requires at least one user or assistant message")
            }

            let generationConfig = VertexGenerationConfig(temperature: temperature)
            let body = VertexGenerateRequest(
                contents: contents,
                systemInstruction: systemInstruction,
                generationConfig: generationConfig
            )

            request.httpBody = try encoder.encode(body)
        }

        return request
    }

    private func buildRequestURL(stream: Bool) -> URL? {
        let normalizedModel = model.hasPrefix("models/") ? model.replacingOccurrences(of: "models/", with: "") : model

        // Determine publisher and action based on model name
        let isClaudeModel = normalizedModel.lowercased().hasPrefix("claude")
        let publisher = isClaudeModel ? "anthropic" : "google"
        let action: String

        if isClaudeModel {
            // Claude models use rawPredict endpoint
            action = stream ? ":streamRawPredict" : ":rawPredict"
        }
        else {
            // Gemini models use generateContent endpoint
            action = stream ? ":streamGenerateContent" : ":generateContent"
        }

        // Vertex AI URL format:
        // https://{REGION}-aiplatform.googleapis.com/v1/projects/{PROJECT_ID}/locations/{REGION}/publishers/{PUBLISHER}/models/{MODEL}:{ACTION}
        var urlString =
            "https://\(region)-aiplatform.googleapis.com/v1/projects/\(projectId)/locations/\(region)/publishers/\(publisher)/models/\(normalizedModel)\(action)"

        if stream && !isClaudeModel {
            urlString += "?alt=sse"
        }

        return URL(string: urlString)
    }

    private func isClaudeModel() -> Bool {
        let normalizedModel = model.hasPrefix("models/") ? model.replacingOccurrences(of: "models/", with: "") : model
        return normalizedModel.lowercased().hasPrefix("claude")
    }

    // MARK: - Message Transformation (similar to Gemini)

    private func transformMessages(_ requestMessages: [[String: String]]) -> (
        GeminiContentRequest?,
        [GeminiContentRequest]
    ) {
        var systemInstruction: GeminiContentRequest?
        var contents: [GeminiContentRequest] = []
        let requiresThoughtSignatures = model.lowercased().contains("gemini-3")

        for message in requestMessages {
            guard let role = message["role"], let content = message["content"] else { continue }
            let storedParts = decodeStoredParts(from: message["message_parts"])

            switch role {
            case "system":
                let text = Self.stripImagePlaceholders(from: content).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                systemInstruction = GeminiContentRequest(
                    role: "system",
                    parts: [GeminiPartRequest(text: text)]
                )
            case "assistant":
                let parts = storedParts ?? buildParts(from: content, allowInlineData: true)
                if requiresThoughtSignatures, !parts.contains(where: { $0.thoughtSignature != nil }) {
                    continue
                }
                guard !parts.isEmpty else { continue }
                contents.append(
                    GeminiContentRequest(
                        role: "model",
                        parts: parts
                    )
                )
            default:
                let parts = storedParts ?? buildParts(from: content, allowInlineData: true)
                guard !parts.isEmpty else { continue }
                contents.append(
                    GeminiContentRequest(
                        role: "user",
                        parts: parts
                    )
                )
            }
        }

        return (systemInstruction, contents)
    }

    private func buildParts(from content: String, allowInlineData: Bool) -> [GeminiPartRequest] {
        var parts: [GeminiPartRequest] = []

        let pattern = "<image-uuid>(.*?)</image-uuid>"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let nsString = content as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)

        var currentLocation = 0
        let matches = regex?.matches(in: content, options: [], range: fullRange) ?? []

        for match in matches {
            let matchRange = match.range
            let textLength = matchRange.location - currentLocation
            if textLength > 0 {
                let textSegment = nsString.substring(with: NSRange(location: currentLocation, length: textLength))
                if !textSegment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    parts.append(GeminiPartRequest(text: textSegment))
                }
            }

            if allowInlineData, match.numberOfRanges > 1 {
                let uuidRange = match.range(at: 1)
                let uuidString = nsString.substring(with: uuidRange)
                if let uuid = UUID(uuidString: uuidString),
                    let image = loadImageFromCoreData(uuid: uuid)
                {
                    let base64 = image.data.base64EncodedString()
                    let inlineData = GeminiInlineData(mimeType: image.mimeType, data: base64)
                    parts.append(GeminiPartRequest(inlineData: inlineData))
                }
            }

            currentLocation = matchRange.location + matchRange.length
        }

        let remainingLength = nsString.length - currentLocation
        if remainingLength > 0 {
            let trailingText = nsString.substring(with: NSRange(location: currentLocation, length: remainingLength))
            if !trailingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parts.append(GeminiPartRequest(text: trailingText))
            }
        }

        if parts.isEmpty {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                parts.append(GeminiPartRequest(text: content))
            }
        }

        return parts
    }

    private func decodeStoredParts(from base64: String?) -> [GeminiPartRequest]? {
        guard let base64 = base64, let data = Data(base64Encoded: base64) else { return nil }
        if let envelope = try? JSONDecoder().decode(PartsEnvelope.self, from: data),
            envelope.serviceType.lowercased() == "gemini" || envelope.serviceType.lowercased() == "vertex"
        {
            return envelope.parts
        }
        if let parts = try? JSONDecoder().decode([GeminiPartRequest].self, from: data) {
            return parts
        }
        return nil
    }

    private static func stripImagePlaceholders(from content: String) -> String {
        let pattern = "<image-uuid>.*?</image-uuid>"
        return content.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Response Handling

    private func handleAPIResponse(_ response: URLResponse?, data: Data?, error: Error?) -> Result<Data?, APIError> {
        if let error = error {
            return .failure(.requestFailed(error))
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            return .failure(.invalidResponse)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            var message = "HTTP \(httpResponse.statusCode)"

            if let data = data {
                if let decodedError = try? makeDecoder().decode(VertexErrorEnvelope.self, from: data) {
                    message = decodedError.error.message
                }
                else if let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
                    message = raw
                }
            }

            switch httpResponse.statusCode {
            case 400:
                return .failure(.serverError("Bad Request: \(message)"))
            case 401, 403:
                // Clear token cache on auth failure
                Task { await VertexTokenManager.shared.clearCache() }
                return .failure(.unauthorized)
            case 429:
                return .failure(.rateLimited)
            case 500...599:
                return .failure(.serverError("Vertex AI Error: \(message)"))
            default:
                return .failure(.unknown(message))
            }
        }

        return .success(data)
    }

    private func renderMessage(
        from response: VertexGenerateResponse,
        inlineDataCache: inout [String: String]
    ) -> String? {
        guard let candidate = response.candidates?.first,
            let parts = candidate.content?.parts
        else {
            return nil
        }

        var message = ""

        for part in parts {
            if let text = part.text, !text.isEmpty {
                message += text
            }

            if let inline = part.inlineData,
                let base64 = inline.data
            {
                let normalized = base64.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else { continue }

                if let cached = inlineDataCache[normalized] {
                    appendInlinePlaceholder(cached, to: &message)
                    continue
                }

                if let placeholder = storeInlineImage(base64: normalized, mimeType: inline.mimeType) {
                    inlineDataCache[normalized] = placeholder
                    appendInlinePlaceholder(placeholder, to: &message)
                }
            }
        }

        while message.hasSuffix("\n") {
            message.removeLast()
        }

        return message.isEmpty ? nil : message
    }

    private func parseStreamPayload(
        _ payload: String,
        decoder: JSONDecoder,
        aggregatedText: inout String,
        inlineDataCache: inout [String: String]
    ) throws -> VertexStreamParseResult {
        if payload == "[DONE]" {
            return VertexStreamParseResult(delta: nil, finished: true)
        }

        guard let data = payload.data(using: .utf8) else {
            return VertexStreamParseResult(delta: nil, finished: false)
        }

        if let response = try? decoder.decode(VertexGenerateResponse.self, from: data) {
            lastResponseParts = response.candidates?.first?.content?.parts
            let delta = extractDelta(
                from: response,
                aggregatedText: &aggregatedText,
                inlineDataCache: &inlineDataCache
            )
            let finished = shouldFinish(after: response)
            return VertexStreamParseResult(delta: delta, finished: finished)
        }

        if let envelope = try? decoder.decode(VertexErrorEnvelope.self, from: data) {
            throw APIError.serverError(envelope.error.message)
        }

        if let stringPayload = try? decoder.decode(String.self, from: data) {
            let delta = mergeRawDelta(stringPayload, aggregatedText: &aggregatedText)
            return VertexStreamParseResult(delta: delta, finished: false)
        }

        if let plain = String(data: data, encoding: .utf8), !plain.isEmpty {
            let delta = mergeRawDelta(plain, aggregatedText: &aggregatedText)
            return VertexStreamParseResult(delta: delta, finished: false)
        }

        return VertexStreamParseResult(delta: nil, finished: false)
    }

    private func extractDelta(
        from response: VertexGenerateResponse,
        aggregatedText: inout String,
        inlineDataCache: inout [String: String]
    ) -> String? {
        guard let message = renderMessage(from: response, inlineDataCache: &inlineDataCache) else {
            return nil
        }

        return mergeRawDelta(message, aggregatedText: &aggregatedText)
    }

    private func mergeRawDelta(_ fragment: String, aggregatedText: inout String) -> String? {
        guard !fragment.isEmpty else { return nil }

        if aggregatedText.isEmpty {
            aggregatedText = fragment
            return fragment
        }

        if fragment == aggregatedText {
            return nil
        }

        if fragment.hasPrefix(aggregatedText) {
            let delta = String(fragment.dropFirst(aggregatedText.count))
            aggregatedText = fragment
            return delta.isEmpty ? nil : delta
        }

        let commonPrefix = fragment.commonPrefix(with: aggregatedText)
        if !commonPrefix.isEmpty {
            let delta = String(fragment.dropFirst(commonPrefix.count))
            aggregatedText = fragment
            return delta.isEmpty ? nil : delta
        }

        aggregatedText.append(fragment)
        return fragment
    }

    private func shouldFinish(after response: VertexGenerateResponse) -> Bool {
        guard let candidates = response.candidates else { return false }
        for candidate in candidates {
            if let reason = candidate.finishReason, isTerminalFinishReason(reason) {
                return true
            }
        }
        return false
    }

    private func isTerminalFinishReason(_ reason: String) -> Bool {
        switch reason.uppercased() {
        case "STOP", "MAX_TOKENS", "SAFETY", "RECITATION", "BLOCKLIST", "OTHER":
            return true
        default:
            return false
        }
    }

    // MARK: - Helpers

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private func parseClaudeJSONResponse(data: Data) -> (String, String)? {
        do {
            if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                let role = json["role"] as? String,
                let contentArray = json["content"] as? [[String: Any]]
            {

                let textContent = contentArray.compactMap { item -> String? in
                    if let type = item["type"] as? String, type == "text",
                        let text = item["text"] as? String
                    {
                        return text
                    }
                    return nil
                }.joined(separator: "\n")

                if !textContent.isEmpty {
                    return (textContent, role)
                }
            }
        }
        catch {
            print("Error parsing Claude JSON: \(error.localizedDescription)")
        }
        return nil
    }

    private func parseClaudeSSEEvent(_ event: String) -> (Bool, Error?, String?, String?) {
        var isFinished = false
        var textContent = ""
        var parseError: Error?
        var jsonString: String?

        if event.hasPrefix("data: ") {
            jsonString = event.replacingOccurrences(of: "data: ", with: "")
        }

        guard let jsonString = jsonString else {
            return (isFinished, parseError, nil, nil)
        }

        guard let jsonData = jsonString.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any]
        else {
            parseError = NSError(
                domain: "SSEParsing",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to parse JSON: \(jsonString)"]
            )
            return (isFinished, parseError, nil, nil)
        }

        if let eventType = json["type"] as? String {
            switch eventType {
            case "content_block_start":
                if let contentBlock = json["content_block"] as? [String: Any],
                    let text = contentBlock["text"] as? String
                {
                    textContent = text
                }
            case "content_block_delta":
                if let delta = json["delta"] as? [String: Any],
                    let text = delta["text"] as? String
                {
                    textContent += text
                }
            case "message_delta":
                if let delta = json["delta"] as? [String: Any],
                    let stopReason = delta["stop_reason"] as? String
                {
                    isFinished = stopReason == "end_turn"
                }
            case "message_stop":
                isFinished = true
            case "ping":
                // Ignore ping events
                break
            default:
                print("Unhandled Claude event type: \(eventType)")
            }
        }
        return (isFinished, parseError, textContent.isEmpty ? nil : textContent, nil)
    }

    private func appendInlinePlaceholder(_ placeholder: String, to message: inout String) {
        if !message.isEmpty, !message.hasSuffix("\n") {
            message += "\n"
        }

        message += placeholder

        if !message.hasSuffix("\n") {
            message += "\n"
        }
    }

    // MARK: - Image Handling

    private func storeInlineImage(base64: String, mimeType: String?) -> String? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        let format = formatFromMimeType(mimeType)

        guard let uuid = saveImageData(data, format: format) else {
            return nil
        }

        return "<image-uuid>\(uuid.uuidString)</image-uuid>"
    }

    private func saveImageData(_ data: Data, format: String) -> UUID? {
        guard let image = NSImage(data: data) else { return nil }
        let uuid = UUID()
        let context = PersistenceController.shared.container.viewContext
        var saveSucceeded = false

        context.performAndWait {
            let imageEntity = ImageEntity(context: context)
            imageEntity.id = uuid
            imageEntity.image = data
            imageEntity.imageFormat = format
            imageEntity.thumbnail = createThumbnailData(from: image)

            do {
                try context.save()
                saveSucceeded = true
            }
            catch {
                print("Error saving generated image: \(error)")
                context.rollback()
            }
        }

        return saveSucceeded ? uuid : nil
    }

    private func createThumbnailData(from image: NSImage) -> Data? {
        let thumbnailSize = CGFloat(AppConstants.thumbnailSize)
        let originalSize = image.size
        guard originalSize.width > 0, originalSize.height > 0 else { return nil }

        let aspectRatio = originalSize.width / originalSize.height
        var targetSize = CGSize(width: thumbnailSize, height: thumbnailSize)

        if aspectRatio > 1 {
            targetSize.height = thumbnailSize / aspectRatio
        }
        else {
            targetSize.width = thumbnailSize * aspectRatio
        }

        let thumbnail = NSImage(size: targetSize)
        thumbnail.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: CGRect(origin: .zero, size: targetSize), from: .zero, operation: .copy, fraction: 1.0)
        thumbnail.unlockFocus()

        guard let tiffData = thumbnail.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }

        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
    }

    private func formatFromMimeType(_ mimeType: String?) -> String {
        switch mimeType?.lowercased() {
        case "image/png":
            return "png"
        case "image/gif":
            return "gif"
        case "image/webp":
            return "webp"
        case "image/heic", "image/heif":
            return "heic"
        case "image/jpg":
            return "jpeg"
        default:
            return "jpeg"
        }
    }

    private func loadImageFromCoreData(uuid: UUID) -> (data: Data, mimeType: String)? {
        let viewContext = PersistenceController.shared.container.viewContext

        let fetchRequest: NSFetchRequest<ImageEntity> = ImageEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
        fetchRequest.fetchLimit = 1

        do {
            let results = try viewContext.fetch(fetchRequest)
            if let imageEntity = results.first, let imageData = imageEntity.image {
                let format = imageEntity.imageFormat ?? "jpeg"
                return (imageData, mimeTypeForImageFormat(format))
            }
        }
        catch {
            print("Error fetching image from CoreData: \(error)")
        }

        return nil
    }

    private func mimeTypeForImageFormat(_ format: String) -> String {
        switch format.lowercased() {
        case "png":
            return "image/png"
        case "heic", "heif":
            return "image/heic"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"
        default:
            return "image/jpeg"
        }
    }

    func consumeLastResponseParts() -> [GeminiPartRequest]? {
        defer { lastResponseParts = nil }
        guard let parts = lastResponseParts else { return nil }
        let requestParts: [GeminiPartRequest] = parts.compactMap { responsePart in
            if let text = responsePart.text {
                return GeminiPartRequest(text: text, thoughtSignature: responsePart.thoughtSignature)
            }
            if let mime = responsePart.inlineData?.mimeType,
                let data = responsePart.inlineData?.data
            {
                return GeminiPartRequest(
                    inlineData: GeminiInlineData(mimeType: mime, data: data),
                    thoughtSignature: responsePart.thoughtSignature
                )
            }
            return nil
        }
        return requestParts.isEmpty ? nil : requestParts
    }

    func cancelCurrentRequest() {
        activeDataTask?.cancel()
        activeStreamTask?.cancel()
    }
}
