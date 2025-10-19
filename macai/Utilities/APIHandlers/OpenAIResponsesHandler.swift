//
//  OpenAIResponsesHandler.swift
//  macai
//
//  Created by Renat on 19.10.2025.
//

import Foundation

private struct OpenAIModelsResponse: Codable {
    let data: [OpenAIModel]
}

private struct OpenAIModel: Codable {
    let id: String
}

class OpenAIResponsesHandler: OpenAIHandlerBase, APIService {
    private static var temperatureUnsupportedModels = Set<String>()
    private static let temperatureLock = NSLock()

    override init(config: APIServiceConfiguration, session: URLSession) {
        super.init(config: config, session: session)
    }

    func sendMessage(
        _ requestMessages: [[String: String]],
        temperature: Float,
        completion: @escaping (Result<String, APIError>) -> Void
    ) {
        func performRequest(includeTemperature: Bool) {
            let request = prepareRequest(
                requestMessages: requestMessages,
                temperature: temperature,
                stream: false,
                includeTemperature: includeTemperature
            )

            session.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    let result = self.handleAPIResponse(response, data: data, error: error)

                    switch result {
                    case .success(let responseData):
                        guard let responseData = responseData,
                              let (messageContent, _) = self.parseJSONResponse(data: responseData)
                        else {
                            completion(.failure(.decodingFailed("Failed to parse response")))
                            return
                        }

                        completion(.success(messageContent))

                    case .failure(let error):
                        if includeTemperature && self.isUnsupportedTemperatureError(error) {
                            Self.markTemperatureUnsupported(for: self.model)
                            performRequest(includeTemperature: false)
                            return
                        }
                        completion(.failure(error))
                    }
                }
            }.resume()
        }

        performRequest(includeTemperature: shouldSendTemperature())
    }

    func sendMessageStream(_ requestMessages: [[String: String]], temperature: Float) async throws
        -> AsyncThrowingStream<String, Error>
    {
        return AsyncThrowingStream { continuation in
            let request = self.prepareRequest(
                requestMessages: requestMessages,
                temperature: temperature,
                stream: true,
                includeTemperature: self.shouldSendTemperature()
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
                        let apiError = APIError.serverError(
                            String(data: data, encoding: .utf8) ?? error.localizedDescription
                        )
                        if self.isUnsupportedTemperatureError(apiError) {
                            Self.markTemperatureUnsupported(for: self.model)
                        }
                        continuation.finish(throwing: apiError)
                        return
                    case .success:
                        break
                    }

                    var hasYieldedContent = false

                    for try await line in stream.lines {
                        if line.isEmpty || !self.isNotSSEComment(line) {
                            continue
                        }

                        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmedLine.hasPrefix("event:") {
                            continue
                        }

                        let prefix = "data:"
                        var payloadString = trimmedLine
                        if trimmedLine.hasPrefix(prefix) {
                            payloadString = String(trimmedLine.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                        }

                        guard !payloadString.isEmpty else { continue }
                        if payloadString == "[DONE]" {
                            continuation.finish()
                            return
                        }

                        guard let jsonData = payloadString.data(using: .utf8) else { continue }
                        let (finished, error, messageData) = self.parseStreamResponse(data: jsonData)

                        if let error = error {
                            continuation.finish(throwing: error)
                            return
                        }

                        if let messageData = messageData, !messageData.isEmpty {
                            if finished && hasYieldedContent {
                                // Avoid replaying the full message when we've already streamed it.
                            }
                            else {
                                continuation.yield(messageData)
                                hasYieldedContent = true
                            }
                        }

                        if finished {
                            continuation.finish()
                            return
                        }
                    }
                    continuation.finish()
                }
                catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func fetchModels() async throws -> [AIModel] {
        let modelsURL = baseURL
            .deletingLastPathComponent()
            .appendingPathComponent("models")

        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await session.data(for: request)

            let result = handleAPIResponse(response, data: data, error: nil)
            switch result {
            case .success(let responseData):
                guard let responseData = responseData else {
                    throw APIError.invalidResponse
                }

                let decodedResponse = try JSONDecoder().decode(OpenAIModelsResponse.self, from: responseData)
                return decodedResponse.data.map { AIModel(id: $0.id) }

            case .failure(let error):
                throw error
            }
        }
        catch {
            throw APIError.requestFailed(error)
        }
    }

    private func prepareRequest(
        requestMessages: [[String: String]],
        temperature: Float,
        stream: Bool,
        includeTemperature: Bool = true
    ) -> URLRequest {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("responses=v1", forHTTPHeaderField: "OpenAI-Beta")

        if stream {
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }

        var temperatureOverride = temperature
        let normalizedModel = self.model.lowercased()

        if AppConstants.openAiReasoningModels.contains(normalizedModel) {
            temperatureOverride = 1
        }

        var processedMessages: [[String: Any]] = []

        for message in requestMessages {
            var processedMessage: [String: Any] = [:]

            let role = message["role"]
            if let role {
                processedMessage["role"] = role
            }

            if let content = message["content"] {
                let pattern = "<image-uuid>(.*?)</image-uuid>"
                let regex = try? NSRegularExpression(pattern: pattern, options: [])
                let nsString = content as NSString
                let matches =
                    regex?.matches(in: content, options: [], range: NSRange(location: 0, length: nsString.length))
                    ?? []

                let textContent = content.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                var contentArray: [[String: Any]] = []
                let textType = role == "assistant" ? "output_text" : "input_text"

                if !textContent.isEmpty {
                    contentArray.append(["type": textType, "text": textContent])
                }

                if role != "assistant" {
                    for match in matches {
                        if match.numberOfRanges > 1 {
                            let uuidRange = match.range(at: 1)
                            let uuidString = nsString.substring(with: uuidRange)

                            if let uuid = UUID(uuidString: uuidString),
                               let imageData = self.loadImageFromCoreData(uuid: uuid)
                            {
                                contentArray.append([
                                    "type": "input_image",
                                    "image_url": "data:image/jpeg;base64,\(imageData.base64EncodedString())",
                                ])
                            }
                        }
                    }
                }

                processedMessage["content"] = contentArray
            }

            processedMessages.append(processedMessage)
        }

        var jsonDict: [String: Any] = [
            "model": self.model,
            "input": processedMessages,
        ]

        if includeTemperature {
            jsonDict["temperature"] = temperatureOverride
        }

        if stream {
            jsonDict["stream"] = true
        }

        request.httpBody = try? JSONSerialization.data(withJSONObject: jsonDict, options: [])

        return request
    }

    private func parseJSONResponse(data: Data) -> (String, String)? {
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            return nil
        }

        if let outputText = json["output_text"] as? String {
            return (outputText, "assistant")
        }

        if let output = json["output"] as? [[String: Any]] {
            for item in output {
                let role = item["role"] as? String ?? "assistant"
                guard let contentItems = item["content"] as? [[String: Any]] else { continue }

                var aggregatedText = ""

                for contentItem in contentItems {
                    if let text = contentItem["text"] as? String {
                        aggregatedText += text
                    }
                    else if let text = contentItem["output_text"] as? String {
                        aggregatedText += text
                    }
                }

                if !aggregatedText.isEmpty {
                    return (aggregatedText, role)
                }
            }
        }

        if let response = json["response"] as? [String: Any] {
            if let outputText = response["output_text"] as? String {
                let role = response["role"] as? String ?? "assistant"
                return (outputText, role)
            }

            if let output = response["output"] as? [[String: Any]] {
                for item in output {
                    let role = item["role"] as? String ?? "assistant"
                    if let contents = item["content"] as? [[String: Any]] {
                        let aggregatedText = contents.reduce(into: "") { partialResult, entry in
                            if let text = entry["text"] as? String {
                                partialResult += text
                            }
                            else if let text = entry["output_text"] as? String {
                                partialResult += text
                            }
                        }
                        if !aggregatedText.isEmpty {
                            return (aggregatedText, role)
                        }
                    }
                }
            }
        }

        return nil
    }

    private func parseStreamResponse(data: Data) -> (Bool, APIError?, String?) {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                return (false, APIError.decodingFailed("Failed to parse streaming payload"), nil)
            }

            if let errorDict = json["error"] as? [String: Any],
               let message = errorDict["message"] as? String
            {
                return (true, APIError.serverError(message), nil)
            }

            if let type = json["type"] as? String {
                if type == "response.completed" {
                    if let response = json["response"] as? [String: Any],
                       let outputText = response["output_text"] as? String,
                       !outputText.isEmpty
                    {
                        return (true, nil, outputText)
                    }
                    return (true, nil, nil)
                }

                if type == "response.error" {
                    let message = (json["message"] as? String)
                        ?? (json["error"] as? [String: Any])?["message"] as? String
                        ?? String(data: data, encoding: .utf8)
                        ?? "Unknown error"
                    return (true, APIError.serverError(message), nil)
                }

                if type.hasSuffix(".delta"), let delta = json["delta"] as? String {
                    return (false, nil, delta)
                }

                if type.hasSuffix(".done") {
                    return (false, nil, nil)
                }
            }

            if let delta = json["delta"] as? String {
                return (false, nil, delta)
            }

            if let outputText = json["output_text"] as? String {
                return (false, nil, outputText)
            }

            return (false, nil, nil)
        }
        catch {
            return (false, APIError.decodingFailed("Failed to parse JSON: \(error.localizedDescription)"), nil)
        }
    }

    private func shouldSendTemperature() -> Bool {
        let modelID = self.model.lowercased()
        Self.temperatureLock.lock()
        let isUnsupported = Self.temperatureUnsupportedModels.contains(modelID)
        Self.temperatureLock.unlock()
        return !isUnsupported
    }

    private static func markTemperatureUnsupported(for model: String) {
        temperatureLock.lock()
        temperatureUnsupportedModels.insert(model.lowercased())
        temperatureLock.unlock()
    }

    private func isUnsupportedTemperatureError(_ error: APIError) -> Bool {
        let message: String
        switch error {
        case .serverError(let text), .unknown(let text):
            message = text
        default:
            return false
        }

        let lowered = message.lowercased()
        return lowered.contains("'temperature' is not supported") || lowered.contains("unsupported parameter")
    }
}
