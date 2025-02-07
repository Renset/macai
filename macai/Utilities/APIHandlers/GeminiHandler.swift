//
//  GeminiHandler.swift
//  macai
//
//  Created by Renat on 07.02.2025.
//

import Foundation

private struct ModelResponse: Codable {
    let models: [Model]
}

private struct Model: Codable {
    let name: String
    
    var id: String {
        name.replacingOccurrences(of: "models/", with: "")
    }
}

class GeminiHandler: ChatGPTHandler {
    override func fetchModels() async throws -> [AIModel] {
        var urlComponents = URLComponents(url: baseURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("models"), resolvingAgainstBaseURL: true)
        urlComponents?.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        
        guard let modelsURL = urlComponents?.url else {
            throw APIError.unknown("Invalid URL")
        }

        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"

        do {
            let (data, response) = try await session.data(for: request)

            let result = handleAPIResponse(response, data: data, error: nil)
            switch result {
            case .success(let responseData):
                guard let responseData = responseData else {
                    throw APIError.invalidResponse
                }

                let geminiResponse = try JSONDecoder().decode(ModelResponse.self, from: responseData)
                return geminiResponse.models.map { AIModel(id: $0.id) }

            case .failure(let error):
                throw error
            }
        }
        catch {
            throw APIError.requestFailed(error)
        }
    }
}
