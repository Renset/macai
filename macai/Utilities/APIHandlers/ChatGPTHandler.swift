//
//  ChatGPTHandler.swift
//  macai
//
//  Created by Renat on 17.07.2024.
//

import AppKit
import CoreData
import Foundation

private struct ChatGPTModelsResponse: Codable {
    let data: [ChatGPTModel]
}

private struct ChatGPTModel: Codable {
    let id: String
}

class ChatGPTHandler: APIService {
    let name: String
    let baseURL: URL
    internal let apiKey: String
    let model: String
    internal let session: URLSession

    init(config: APIServiceConfiguration, session: URLSession) {
        self.name = config.name
        self.baseURL = config.apiUrl
        self.apiKey = config.apiKey
        self.model = config.model
        self.session = session
    }

    func sendMessage(
        _ requestMessages: [[String: String]],
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
                            completion(.failure(.decodingFailed("Failed to parse response")))
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
                        if line.data(using: .utf8) != nil && isNotSSEComment(line) {
                            let prefix = "data:"
                            var index = line.startIndex
                            if line.starts(with: prefix) {
                                index = line.index(line.startIndex, offsetBy: prefix.count)
                            }
                            let jsonData = String(line[index...]).trimmingCharacters(in: .whitespacesAndNewlines)
                            if let jsonData = jsonData.data(using: .utf8) {
                                let (finished, error, messageData, _) = parseDeltaJSONResponse(data: jsonData)

                                if error != nil {
                                    continuation.finish(throwing: error)
                                }
                                else {
                                    if messageData != nil {
                                        continuation.yield(messageData!)
                                    }
                                    if finished {
                                        continuation.finish()
                                    }
                                }
                            }
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
        let modelsURL = baseURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("models")

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

                let gptResponse = try JSONDecoder().decode(ChatGPTModelsResponse.self, from: responseData)

                return gptResponse.data.map { AIModel(id: $0.id) }

            case .failure(let error):
                throw error
            }
        }
        catch {
            throw APIError.requestFailed(error)
        }
    }

    internal func prepareRequest(requestMessages: [[String: String]], model: String, temperature: Float, stream: Bool)
        -> URLRequest
    {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var temperatureOverride = temperature

        if AppConstants.openAiReasoningModels.contains(self.model) {
            temperatureOverride = 1
        }

        var processedMessages: [[String: Any]] = []

        for message in requestMessages {
            var processedMessage: [String: Any] = [:]

            if let role = message["role"] {
                processedMessage["role"] = role
            }

            if let content = message["content"] {
                let pattern = "<image-uuid>(.*?)</image-uuid>"

                if content.range(of: pattern, options: .regularExpression) != nil {
                    let textContent = content.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    var contentArray: [[String: Any]] = []

                    if !textContent.isEmpty {
                        contentArray.append(["type": "text", "text": textContent])
                    }

                    let regex = try? NSRegularExpression(pattern: pattern, options: [])
                    let nsString = content as NSString
                    let matches =
                        regex?.matches(in: content, options: [], range: NSRange(location: 0, length: nsString.length))
                        ?? []

                    for match in matches {
                        if match.numberOfRanges > 1 {
                            let uuidRange = match.range(at: 1)
                            let uuidString = nsString.substring(with: uuidRange)

                            if let uuid = UUID(uuidString: uuidString),
                                let imageData = self.loadImageFromCoreData(uuid: uuid)
                            {
                                contentArray.append([
                                    "type": "image_url",
                                    "image_url": ["url": "data:image/jpeg;base64,\(imageData.base64EncodedString())"],
                                ])
                            }
                        }
                    }

                    processedMessage["content"] = contentArray
                }
                else {
                    processedMessage["content"] = content
                }
            }

            processedMessages.append(processedMessage)
        }

        let jsonDict: [String: Any] = [
            "model": self.model,
            "stream": stream,
            "messages": processedMessages,
            "temperature": temperatureOverride,
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: jsonDict, options: [])

        return request
    }

    internal func handleAPIResponse(_ response: URLResponse?, data: Data?, error: Error?) -> Result<Data?, APIError> {
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
                case 400...499:
                    return .failure(.serverError("Client Error: \(errorResponse)"))
                case 500...599:
                    return .failure(.serverError("Server Error: \(errorResponse)"))
                default:
                    return .failure(.unknown("Unknown error: \(errorResponse)"))
                }
            }
            else {
                return .failure(.serverError("HTTP \(httpResponse.statusCode)"))
            }
        }

        return .success(data)
    }

    internal func parseJSONResponse(data: Data) -> (String, String)? {
        if let responseString = String(data: data, encoding: .utf8) {
            #if DEBUG
                print("Response: \(responseString)")
            #endif
            do {
                let json = try JSONSerialization.jsonObject(with: data, options: [])
                if let dict = json as? [String: Any] {
                    if let choices = dict["choices"] as? [[String: Any]],
                        let lastIndex = choices.indices.last,
                        let content = choices[lastIndex]["message"] as? [String: Any],
                        let messageRole = content["role"] as? String,
                        let messageContent = content["content"] as? String
                    {
                        return (messageContent, messageRole)
                    }
                }
            }
            catch {
                print("Error parsing JSON: \(error.localizedDescription)")
                return nil
            }
        }
        return nil
    }

    internal func parseDeltaJSONResponse(data: Data?) -> (Bool, Error?, String?, String?) {
        guard let data = data else {
            print("No data received.")
            return (true, APIError.decodingFailed("No data received in SSE event"), nil, nil)
        }

        let defaultRole = "assistant"
        let dataString = String(data: data, encoding: .utf8)
        if dataString == "[DONE]" {
            return (true, nil, nil, nil)
        }

        do {
            let jsonResponse = try JSONSerialization.jsonObject(with: data, options: [])

            if let dict = jsonResponse as? [String: Any] {
                if let choices = dict["choices"] as? [[String: Any]],
                    let firstChoice = choices.first,
                    let delta = firstChoice["delta"] as? [String: Any],
                    let contentPart = delta["content"] as? String
                {

                    let finished = false
                    if let finishReason = firstChoice["finish_reason"] as? String, finishReason == "stop" {
                        _ = true
                    }
                    return (finished, nil, contentPart, defaultRole)
                }
            }
        }
        catch {
            #if DEBUG
                print(String(data: data, encoding: .utf8) ?? "Data cannot be converted into String")
                print("Error parsing JSON: \(error)")
            #endif

            return (false, APIError.decodingFailed("Failed to parse JSON: \(error.localizedDescription)"), nil, nil)
        }

        return (false, nil, nil, nil)
    }

    internal func isNotSSEComment(_ string: String) -> Bool {
        return !string.starts(with: ":")
    }

    private func loadImageFromCoreData(uuid: UUID) -> Data? {
        let viewContext = PersistenceController.shared.container.viewContext

        let fetchRequest: NSFetchRequest<ImageEntity> = ImageEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
        fetchRequest.fetchLimit = 1

        do {
            let results = try viewContext.fetch(fetchRequest)
            if let imageEntity = results.first, let imageData = imageEntity.image {
                return imageData
            }
        }
        catch {
            print("Error fetching image from CoreData: \(error)")
        }

        return nil
    }
}
