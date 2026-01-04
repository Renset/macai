//
//  VertexClaudeHandler.swift
//  macai
//
//  Vertex AI handler for Claude models.
//

import Foundation

// MARK: - Vertex Claude Handler

class VertexClaudeHandler: APIService {
    let name: String
    let baseURL: URL
    private let model: String
    private let session: URLSession
    private let projectId: String
    private let region: String
    private var activeDataTask: Task<Void, Never>?
    private var activeStreamTask: Task<Void, Never>?

    init(config: APIServiceConfiguration, session: URLSession) {
        self.name = config.name
        self.baseURL = config.apiUrl
        self.model = config.model
        self.session = session
        self.projectId = config.gcpProjectId ?? ""
        self.region = config.gcpRegion ?? "us-central1"
    }

    // MARK: - Fetch Models

    func fetchModels() async throws -> [AIModel] {
        // Vertex AI does not provide a stable v1 REST API endpoint for listing publisher models.
        // Return the curated list of Claude models from configuration.
        let allModels = AppConstants.defaultApiConfigurations["vertex"]?.models ?? []
        // Filter to only Claude models
        let claudeModels = allModels.filter { $0.lowercased().hasPrefix("claude") }
        return claudeModels.map { AIModel(id: $0) }
    }

    // MARK: - Send Message (Non-streaming)

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
                    let result = VertexResponseHandler.handleAPIResponse(response, data: data, error: nil)

                    switch result {
                    case .success(let payload):
                        guard let payload = payload else {
                            completion(.failure(.invalidResponse))
                            return
                        }

                        if let (messageContent, _) = self.parseClaudeJSONResponse(data: payload) {
                            completion(.success(messageContent))
                        }
                        else {
                            // Try to decode error envelope
                            let decoder = JSONDecoder()
                            decoder.keyDecodingStrategy = .convertFromSnakeCase
                            if let envelope = try? decoder.decode(VertexErrorEnvelope.self, from: payload) {
                                completion(.failure(.serverError(envelope.error.message)))
                            }
                            else {
                                completion(.failure(.decodingFailed("Failed to parse Claude response")))
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

    // MARK: - Send Message Stream

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
                    let responseCheck = VertexResponseHandler.handleAPIResponse(response, data: nil, error: nil)

                    switch responseCheck {
                    case .failure(let error):
                        var errorData = Data()
                        for try await byte in stream {
                            errorData.append(byte)
                        }

                        let decoder = JSONDecoder()
                        decoder.keyDecodingStrategy = .convertFromSnakeCase
                        if let envelope = try? decoder.decode(VertexErrorEnvelope.self, from: errorData) {
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

        guard let url = VertexURLBuilder.claudeURL(
            region: region,
            projectId: projectId,
            model: model,
            stream: stream
        ) else {
            throw APIError.unknown("Invalid Vertex AI Claude request URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = AppConstants.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        if stream {
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }

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

        return request
    }

    // MARK: - Claude Response Parsing

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

    // MARK: - Cancel

    func cancelCurrentRequest() {
        activeDataTask?.cancel()
        activeStreamTask?.cancel()
    }
}

