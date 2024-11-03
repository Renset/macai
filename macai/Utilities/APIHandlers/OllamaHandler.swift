//
//  OllamaHandler.swift
//  macai
//
//  Created by Renat on 17.07.2024.
//

import Foundation

class OllamaHandler: APIService {
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
                    completion(.failure(.decodingFailed("Error parsing JSON" as! Error)))
                    return
                }
                let responseString = messageContent
                completion(.success(responseString))
            }
        }.resume()
    }
    
    func sendMessageStream(_ requestMessages: [[String: String]]) async throws -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            let request = self.prepareRequest(requestMessages: requestMessages, model: model, stream: true)
            
            Task {
                do {
                    let (stream, response) = try await URLSession.shared.bytes(for: request)
                    if let httpResponse = response as? HTTPURLResponse {
                        switch httpResponse.statusCode {
                        case 200...299:
                            #if DEBUG
                            print("Got successful response code from server")
                            #endif
                        case 400...599:
                            continuation.finish(throwing: APIError.serverError("HTTP Response code \(httpResponse.statusCode)"))
                        default:
                            continuation.finish(throwing: APIError.unknown("Unhandled status code: \(httpResponse.statusCode)"))
                        }
                    } else {
                        continuation.finish(throwing: APIError.invalidResponse)
                    }
                    
                    for try await line in stream.lines {
                        if line.data(using: .utf8) != nil {
                            let prefix = "data: "
                            var index = line.startIndex
                            if line.starts(with: prefix) {
                                index = line.index(line.startIndex, offsetBy: prefix.count)
                            }
                            let jsonData = String(line[index...]).trimmingCharacters(in: .whitespacesAndNewlines)
                            if let jsonData = jsonData.data(using: .utf8) {
                                let (finished, error, messageData, messageRole) = parseDeltaJSONResponse(data: jsonData)
                                
                                if (error != nil) {
                                    continuation.finish(throwing: error)
                                } else {
                                    if (messageData != nil) {
                                        continuation.yield(messageData!)
                                    }
                                    if (finished) {
                                        continuation.finish()
                                    }
                                }
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    private func prepareRequest(requestMessages: [[String: String]], model: String, stream: Bool) -> URLRequest {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let jsonDict: [String: Any] = [
            "model": self.model,
            "stream": stream,
            "messages": requestMessages
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: jsonDict, options: [])
        
        return request
    }
    
    private func parseJSONResponse(data: Data) -> (String, String)? {
        if let responseString = String(data: data, encoding: .utf8) {
            #if DEBUG
            print("Response: \(responseString)")
            #endif
            do {
                let json = try JSONSerialization.jsonObject(with: data, options: [])
                if let dict = json as? [String: Any] {
                    if let message = dict["message"] as? [String: Any],
                       let messageRole = message["role"] as? String,
                       let messageContent = message["content"] as? String {
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
    
    private func parseDeltaJSONResponse(data: Data?) -> (Bool, Error?, String?, String?) {
        guard let data = data else {
            print("No data received.")
            return (true, "No data received" as! Error, nil, nil)
        }
        
        let defaultRole = "assistant"
        let dataString = String(data: data, encoding: .utf8)
        if (dataString == "[DONE]") {
            return (true, nil, nil, nil)
        }
        
        do {
            let jsonResponse = try JSONSerialization.jsonObject(with: data, options: [])
            
            if let dict = jsonResponse as? [String: Any] {
                if let message = dict["message"] as? [String: Any],
                   let messageRole = message["role"] as? String,
                   let done = dict["done"] as? Bool,
                   let messageContent = message["content"] as? String {
                    return (done, nil, messageContent, messageRole)
                }
            }
            
            
        } catch {
            print(String(data: data, encoding: .utf8))
            print("Error parsing JSON: \(error)")
            return (true, error, nil, nil)
        }
        
        return (false, nil, nil, nil)
    }
}
