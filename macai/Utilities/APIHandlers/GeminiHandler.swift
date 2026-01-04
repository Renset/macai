//
//  GeminiHandler.swift
//  macai
//
//  Created by Renat on 07.02.2025.
//

import Foundation

// MARK: - Gemini-specific Models Response

private struct GeminiModelList: Decodable {
    let models: [GeminiModel]
}

private struct GeminiModel: Decodable {
    let name: String

    var id: String {
        name.replacingOccurrences(of: "models/", with: "")
    }
}

// MARK: - GeminiHandler (Public Gemini API)

class GeminiHandler: GeminiHandlerBase {
    private let apiKey: String
    private let modelsEndpoint: URL

    override init(config: APIServiceConfiguration, session: URLSession) {
        self.apiKey = config.apiKey
        self.modelsEndpoint = GeminiHandler.normalizeModelsEndpoint(from: config.apiUrl)
        super.init(config: config, session: session)
    }

    // MARK: - Fetch Models

    override func fetchModels() async throws -> [AIModel] {
        guard var components = URLComponents(url: modelsEndpoint, resolvingAgainstBaseURL: false) else {
            throw APIError.unknown("Invalid Gemini models URL")
        }
        components.queryItems = [URLQueryItem(name: "key", value: apiKey)]

        guard let modelsURL = components.url else {
            throw APIError.unknown("Unable to build Gemini models URL")
        }

        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        request.timeoutInterval = AppConstants.requestTimeout

        do {
            let (data, response) = try await session.data(for: request)
            let result = handleAPIResponse(response, data: data, error: nil)

            switch result {
            case .success(let payload):
                guard let payload = payload else {
                    throw APIError.invalidResponse
                }
                let decoder = makeDecoder()
                let geminiResponse = try decoder.decode(GeminiModelList.self, from: payload)
                return geminiResponse.models.map { AIModel(id: $0.id) }

            case .failure(let error):
                throw error
            }
        }
        catch {
            throw APIError.requestFailed(error)
        }
    }

    // MARK: - Request Preparation

    override func prepareRequest(
        requestMessages: [[String: String]],
        temperature: Float,
        stream: Bool
    ) -> Result<URLRequest, APIError> {
        guard let url = buildRequestURL(stream: stream) else {
            return .failure(.unknown("Invalid Gemini request URL"))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = AppConstants.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        if stream {
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }

        let (systemInstruction, contents) = transformMessages(requestMessages)

        if contents.isEmpty {
            return .failure(.unknown("Gemini request requires at least one user or assistant message"))
        }

        let generationConfig = GeminiGenerationConfig(temperature: temperature)
        let body = GeminiGenerateRequest(
            contents: contents,
            systemInstruction: systemInstruction,
            generationConfig: generationConfig
        )

        do {
            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(body)
        }
        catch {
            return .failure(.decodingFailed("Failed to encode Gemini request: \(error.localizedDescription)"))
        }

        return .success(request)
    }

    // MARK: - URL Building

    override func buildRequestURL(stream: Bool) -> URL? {
        let action = stream ? ":streamGenerateContent" : ":generateContent"
        var base = modelsEndpoint.absoluteString

        if base.hasSuffix("/") {
            base.removeLast()
        }

        let path = "\(base)/\(normalizedModelIdentifier())\(action)"
        var components = URLComponents(string: path)
        var queryItems = [URLQueryItem(name: "key", value: apiKey)]

        if stream {
            queryItems.append(URLQueryItem(name: "alt", value: "sse"))
        }

        components?.queryItems = queryItems
        return components?.url
    }

    // MARK: - URL Normalization

    private static func normalizeModelsEndpoint(from url: URL) -> URL {
        var endpoint = url

        if endpoint.path.contains("/chat/completions") {
            endpoint = endpoint.deletingLastPathComponent().deletingLastPathComponent()
        }

        if let last = endpoint.pathComponents.last, last.contains(":") {
            endpoint = endpoint.deletingLastPathComponent()
        }

        if endpoint.pathComponents.last == "models" {
            return endpoint
        }

        if endpoint.pathComponents.contains("models") {
            while endpoint.pathComponents.last != "models", endpoint.pathComponents.count > 1 {
                endpoint = endpoint.deletingLastPathComponent()
            }
            return endpoint
        }

        return endpoint.appendingPathComponent("models")
    }
}
