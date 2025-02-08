//
//  ClaudeHandler.swift
//  macai
//
//  Created by Renat Notfullin on 20.09.2024.
//

import Foundation

private struct ClaudeModelsResponse: Codable {
    let data: [ClaudeModel]
}

private struct ClaudeModel: Codable {
    let id: String
}

class ClaudeHandler: APIService {
    let name: String
    let baseURL: URL
    private let apiKey: String
    let model: String
    private let session: URLSession

    init(config: APIServiceConfiguration, session: URLSession) {
        self.name = config.name
        self.baseURL = config.apiUrl
        self.apiKey = config.apiKey
        self.model = config.model
        self.session = session
    }

    func fetchModels() async throws -> [AIModel] {
        let modelsURL = baseURL.deletingLastPathComponent().appendingPathComponent("models")
        
        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("2023-06-01", forHTTPHeaderField: "Anthropic-Version")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            let result = handleAPIResponse(response, data: data, error: nil)
            switch result {
            case .success(let responseData):
                guard let responseData = responseData else {
                    throw APIError.invalidResponse
                }
                
                let claudeResponse = try JSONDecoder().decode(ClaudeModelsResponse.self, from: responseData)
                
                return claudeResponse.data.map { AIModel(id: $0.id) }
                
            case .failure(let error):
                throw error
            }
        } catch {
            throw APIError.requestFailed(error)
        }
    }

    func sendMessage(
        _ requestMessages: [[String: Any]],
        temperature: Float,
        completion: @escaping (Result<String, APIError>) -> Void
    ) {
        let request = prepareRequest(
            requestMessages: requestMessages,
            model: model,
            temperature: temperature,
            stream: false
        )

        session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                let result = self.handleAPIResponse(response, data: data, error: error)

                switch result {
                case .success(let responseData):
                    if let responseData = responseData {
                        guard let (messageContent, _) = self.parseJSONResponse(data: responseData) else {
                            completion(.failure(.decodingFailed("Failed to parse Claude response")))
                            return
                        }
                        completion(.success(messageContent))
                    }
                    else {
                        completion(.failure(.invalidResponse))
                    }

                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    func sendMessageStream(_ requestMessages: [[String: String]], temperature: Float) async throws
        -> AsyncThrowingStream<String, Error>
    {
        return AsyncThrowingStream { continuation in
            let request = self.prepareRequest(
                requestMessages: requestMessages,
                model: model,
                temperature: temperature,
                stream: true
            )

            Task {
                do {
                    let (stream, response) = try await session.bytes(for: request)
                    let result = self.handleAPIResponse(response, data: nil, error: nil)

                    switch result {
                    case .failure(let error):
                        var data = Data()
                        for try await byte in stream {
                            data.append(byte)
                        }
                        let error = APIError.serverError(
                            String(data: data, encoding: .utf8) ?? error.localizedDescription
                        )
                        continuation.finish(throwing: error)
                        return
                    case .success:
                        break
                    }

                    for try await line in stream.lines {
                        let (finished, error, content, _) = self.parseSSEEvent(line)

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
                catch {
                    continuation.finish(throwing: APIError.requestFailed(error))
                }
            }
        }
    }

    private func prepareRequest(requestMessages: [[String: Any]], model: String, temperature: Float, stream: Bool)
        -> URLRequest
    {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "Anthropic-Version")

        // Claude doesn't support 'system' role. Instead, we extract system message from request messages and insert into 'system' string parameter (more details: https://docs.anthropic.com/en/api/messages)
        var systemMessage = ""
        let firstMessage = requestMessages.first
        var updatedRequestMessages = requestMessages

        if firstMessage?["role"] as? String == "system" {
            systemMessage = firstMessage?["content"] as? String ?? ""
            updatedRequestMessages.removeFirst()
        }

        let maxTokens =
            model == "claude-3-5-sonnet-latest" ? 8192 : AppConstants.defaultApiConfigurations["claude"]!.maxTokens!

        let jsonDict: [String: Any] = [
            "model": model,
            "messages": updatedRequestMessages,
            "system": systemMessage,
            "stream": stream,
            "temperature": temperature,
            "max_tokens": maxTokens,
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: jsonDict, options: [])

        return request
    }

    private func handleAPIResponse(_ response: URLResponse?, data: Data?, error: Error?) -> Result<Data?, APIError> {
        if let error = error {
            return .failure(.requestFailed(error))
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            return .failure(.invalidResponse)
        }

        if !(200...299).contains(httpResponse.statusCode) {
            if let data = data, let errorResponse = String(data: data, encoding: .utf8) {
                switch httpResponse.statusCode {
                case 401:
                    return .failure(.unauthorized)
                case 429:
                    return .failure(.rateLimited)
                case 400:
                    return .failure(.serverError("Bad Request: \(errorResponse)"))
                case 404:
                    return .failure(.serverError("Model not found: \(errorResponse)"))
                case 500...599:
                    return .failure(.serverError("Claude API Error: \(errorResponse)"))
                default:
                    return .failure(.unknown("HTTP \(httpResponse.statusCode): \(errorResponse)"))
                }
            }
            else {
                return .failure(.serverError("HTTP Response code: \(httpResponse.statusCode)"))
            }
        }

        return .success(data)
    }

    private func parseJSONResponse(data: Data) -> (String, String)? {
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
            print("Error parsing JSON: \(error.localizedDescription)")
        }
        return nil
    }

    private func parseSSEEvent(_ event: String) -> (Bool, Error?, String?, String?) {
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
            case "contenxt_block_start":
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
                print("Unhandled event type: \(eventType)")
            }
        }
        return (isFinished, parseError, textContent.isEmpty ? nil : textContent, nil)
    }
}
