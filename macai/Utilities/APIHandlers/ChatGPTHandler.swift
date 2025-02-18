//
//  ChatGPTHandler.swift
//  macai
//
//  Created by Renat on 17.07.2024.
//

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
                        guard let (messageContent, _, t_msg, t_id) = self.parseJSONResponse(data: responseData) else {
                            completion(.failure(.decodingFailed("Failed to parse response")))
                            return
                        }
                        
                        if let t_msg = t_msg {
                            var messages = requestMessages
                            messages.append(t_msg)
                            var webresult: String
                            messages.append([
                                "role": "tool",
                                "tool_call_id": t_id,
                                "name": "search_web",
                                "content": self.searchWeb(messageContent)
                            ])
                            self.sendMessage(messages, temperature: temperature, completion: completion)
                        
                        } else {
                            completion(.success(messageContent))
                        }
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
    
    func searchWeb(_ query: String) -> String {
        guard let url = URL(string: "http://127.0.0.1:3000/\(query)") else { return "bad url" }
        
        let semaphore = DispatchSemaphore(value: 0)
        var result: String = ""
        
        session.dataTask(with: url) { data, response, error in
            if let error = error {
                result = "Error: \(error)"
                semaphore.signal()
                return
            }
            
            guard let data = data else {
                result = "No data received"
                semaphore.signal()
                return
            }
            
            // Handle the response data
            if let str = String(data: data, encoding: .utf8) {
                result = str
                semaphore.signal()
                return
            }
            
            result = "bad string"
            semaphore.signal()
        }.resume()
        
        semaphore.wait()
        return result
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
                            let prefix = "data: "
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
        } catch {
            throw APIError.requestFailed(error)
        }
    }

    private func prepareRequest(requestMessages: [[String: Any]], model: String, temperature: Float, stream: Bool)
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

        let jsonDict: [String: Any] = [
            "model": self.model,
            "stream": stream,
            "messages": requestMessages,
            "temperature": temperatureOverride,
            "tools": [[
                "type": "function",
                "function": [
                    "name": "search_web",
                    "description": "useful for when you need to search for information on the web",
                    "parameters": [
                      "type": "object",
                      "properties": [
                        "query": [
                          "type": "string",
                          "description": "the query to search for"
                        ]
                      ],
                      "required": ["query"]
                    ]
                ]
            ]]
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

    private func parseJSONResponse(data: Data) -> (String, String, [String: Any]?, String)? {
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
                        return (messageContent, messageRole, nil, "")
                    }
                    if let choices = dict["choices"] as? [[String: Any]],
                        let lastIndex = choices.indices.last,
                        let content = choices[lastIndex]["message"] as? [String: Any],
                        let messageRole = content["role"] as? String,
                        let toolCalls = content["tool_calls"] as? [[String: Any]],
                        let firstTool = toolCalls.first,
                        let function = firstTool["function"] as? [String: Any],
                        //let f_name = function["name"] as? String,
                        let f_arguments = function["arguments"] as? String,
                        let f_id = firstTool["id"] as? String
                    {
                        
                        return (f_arguments, messageRole, content, f_id)
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

    private func parseDeltaJSONResponse(data: Data?) -> (Bool, Error?, String?, String?) {
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
    
    private func isNotSSEComment(_ string: String) -> Bool {
        return !string.starts(with: ":")
    }
}
