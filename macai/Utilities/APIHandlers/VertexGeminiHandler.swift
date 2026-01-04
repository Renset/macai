//
//  VertexGeminiHandler.swift
//  macai
//
//  Vertex AI handler for Gemini models.
//

import AppKit
import CoreData
import Foundation

// MARK: - Vertex Gemini Handler

class VertexGeminiHandler: GeminiHandlerBase {
    private let projectId: String
    private let region: String
    private var vertexActiveDataTask: Task<Void, Never>?

    override init(config: APIServiceConfiguration, session: URLSession) {
        self.projectId = config.gcpProjectId ?? ""
        self.region = config.gcpRegion ?? "us-central1"
        super.init(config: config, session: session)
    }

    // MARK: - Fetch Models

    override func fetchModels() async throws -> [AIModel] {
        // Vertex AI does not provide a stable v1 REST API endpoint for listing publisher models.
        // Return the curated list of Gemini models from configuration.
        let allModels = AppConstants.defaultApiConfigurations["vertex"]?.models ?? []
        // Filter to only Gemini models (exclude Claude models)
        let geminiModels = allModels.filter { !$0.lowercased().hasPrefix("claude") }
        return geminiModels.map { AIModel(id: $0) }
    }

    // MARK: - Override sendMessage for async token handling

    override func sendMessage(
        _ requestMessages: [[String: String]],
        temperature: Float,
        completion: @escaping (Result<String, APIError>) -> Void
    ) {
        vertexActiveDataTask?.cancel()
        let task = Task {
            defer { self.vertexActiveDataTask = nil }
            do {
                let request = try await prepareRequestAsync(
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

                        do {
                            let decoder = self.makeDecoder()
                            let response = try decoder.decode(GeminiGenerateResponse.self, from: payload)
                            self.lastResponseParts = response.candidates?.first?.content?.parts
                            var inlineDataCache: [String: String] = [:]
                            if let message = self.renderMessage(from: response, inlineDataCache: &inlineDataCache) {
                                completion(.success(message))
                            }
                            else {
                                completion(.failure(.decodingFailed("Empty Vertex AI Gemini response")))
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
        vertexActiveDataTask = task
    }

    // MARK: - Override sendMessageStream for async token handling

    override func sendMessageStream(_ requestMessages: [[String: String]], temperature: Float) async throws
        -> AsyncThrowingStream<String, Error>
    {
        let request = try await prepareRequestAsync(
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

    // MARK: - Synchronous prepareRequest (not used directly, required by base class)

    override func prepareRequest(
        requestMessages: [[String: String]],
        temperature: Float,
        stream: Bool
    ) -> Result<URLRequest, APIError> {
        // This method requires async for token retrieval, so we return an error
        // The actual implementation uses prepareRequestAsync
        return .failure(.unknown("Use sendMessage or sendMessageStream instead"))
    }

    // MARK: - Async Request Preparation

    private func prepareRequestAsync(
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

        // Use Gemini format for Google models
        let (systemInstruction, contents) = transformMessages(requestMessages)

        if contents.isEmpty {
            throw APIError.unknown("Vertex AI request requires at least one user or assistant message")
        }

        let body = GeminiGenerateRequest(
            contents: contents,
            systemInstruction: systemInstruction,
            generationConfig: GeminiGenerationConfig(temperature: temperature)
        )

        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(body)

        return request
    }

    // MARK: - URL Building

    override func buildRequestURL(stream: Bool) -> URL? {
        return VertexURLBuilder.geminiURL(
            region: region,
            projectId: projectId,
            model: model,
            stream: stream
        )
    }

    // MARK: - Cancel

    override func cancelCurrentRequest() {
        vertexActiveDataTask?.cancel()
        super.cancelCurrentRequest()
    }
}

