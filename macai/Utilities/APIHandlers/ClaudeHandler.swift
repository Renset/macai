//
//  ClaudeHandler.swift
//  macai
//
//  Created by Renat Notfullin on 20.09.2024.
//

import Foundation

class ClaudeHandler: APIService {
    let name: String
    let baseURL: URL
    private let apiKey: String
    let model: String

    init(config: APIServiceConfiguration) {
        self.name = config.name
        self.baseURL = config.apiUrl
        self.apiKey = config.apiKey
        self.model = config.model
    }

    func sendMessage(_ requestMessages: [[String: String]], completion: @escaping (Result<String, APIError>) -> Void) {
        let request = prepareRequest(requestMessages: requestMessages, model: model, stream: false)

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(.requestFailed(error)))
                    return
                }

                guard let data = data else {
                    completion(.failure(.invalidResponse))
                    return
                }

                guard let (messageContent, _) = self.parseJSONResponse(data: data) else {
                    print("Error parsing JSON")
                    completion(
                        .failure(
                            .decodingFailed(
                                NSError(
                                    domain: "ClaudeHandler",
                                    code: 0,
                                    userInfo: [NSLocalizedDescriptionKey: "Error parsing JSON"]
                                )
                            )
                        )
                    )
                    return
                }
                completion(.success(messageContent))
            }
        }.resume()
    }

    func sendMessageStream(_ requestMessages: [[String: String]]) async throws -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            let request = self.prepareRequest(requestMessages: requestMessages, model: model, stream: true)

            Task {
                do {
                    let (stream, _) = try await URLSession.shared.bytes(for: request)

                    for try await line in stream.lines {
                        let (finished, error, content, _) = self.parseSSEEvent(line)

                        if let error = error {
                            continuation.finish(throwing: error)
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
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func prepareRequest(requestMessages: [[String: String]], model: String, stream: Bool) -> URLRequest {
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

        let jsonDict: [String: Any] = [
            "model": model,
            "messages": updatedRequestMessages,
            "system": systemMessage,
            "stream": stream,
            "max_tokens": 4096,
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: jsonDict, options: [])

        return request
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
