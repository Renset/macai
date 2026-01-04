//
//  VertexCommon.swift
//  macai
//
//  Shared utilities for Vertex AI handlers.
//

import Foundation

// MARK: - ADC Credentials

struct ADCCredentials: Decodable {
    let clientId: String
    let clientSecret: String
    let refreshToken: String
    let type: String

    enum CodingKeys: String, CodingKey {
        case clientId = "client_id"
        case clientSecret = "client_secret"
        case refreshToken = "refresh_token"
        case type
    }
}

struct TokenResponse: Decodable {
    let accessToken: String
    let expiresIn: Int
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

// MARK: - Token Manager

actor VertexTokenManager {
    static let shared = VertexTokenManager()

    private var cachedToken: String?
    private var tokenExpiry: Date?

    private let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!

    func getAccessToken(session: URLSession) async throws -> String {
        // Return cached token if still valid (with 5-minute buffer)
        if let token = cachedToken,
            let expiry = tokenExpiry,
            Date() < expiry.addingTimeInterval(-300)
        {
            return token
        }

        let _ = try await ensureADCCredentials()
        // Read ADC credentials
        let credentials = try await readADCCredentials()

        // Exchange refresh token for access token
        let token = try await refreshAccessToken(credentials: credentials, session: session)
        return token
    }

    private func ensureADCCredentials() async throws -> Data {
        do {
            return try ADCCredentialsAccess.loadCredentialsData()
        }
        catch let error as ADCCredentialsAccessError {
            switch error {
            case .noBookmark:
                return try await ADCCredentialsAccess.promptAndStoreBookmark()
            default:
                throw error
            }
        }
    }

    private func readADCCredentials() async throws -> ADCCredentials {
        do {
            let data = try ADCCredentialsAccess.loadCredentialsData()
            let credentials = try JSONDecoder().decode(ADCCredentials.self, from: data)

            guard credentials.type == "authorized_user" else {
                throw APIError.unknown(
                    "ADC file is not an authorized_user type. Run 'gcloud auth application-default login'"
                )
            }

            return credentials
        }
        catch let error as ADCCredentialsAccessError {
            switch error {
            case .noBookmark:
                let data = try await ADCCredentialsAccess.promptAndStoreBookmark()
                let credentials = try JSONDecoder().decode(ADCCredentials.self, from: data)

                guard credentials.type == "authorized_user" else {
                    throw APIError.unknown(
                        "ADC file is not an authorized_user type. Run 'gcloud auth application-default login'"
                    )
                }

                return credentials
            default:
                throw error
            }
        }
    }

    private func refreshAccessToken(credentials: ADCCredentials, session: URLSession) async throws -> String {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "client_id": credentials.clientId,
            "client_secret": credentials.clientSecret,
            "refresh_token": credentials.refreshToken,
            "grant_type": "refresh_token",
        ]

        request.httpBody =
            body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.unauthorized
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)

        // Cache the token
        cachedToken = tokenResponse.accessToken
        tokenExpiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))

        return tokenResponse.accessToken
    }

    func clearCache() {
        cachedToken = nil
        tokenExpiry = nil
    }
}

// MARK: - Vertex AI Error Structures

struct VertexErrorEnvelope: Decodable {
    let error: VertexAPIError
}

struct VertexAPIError: Decodable {
    let code: Int?
    let message: String
    let status: String?
}

// MARK: - URL Builder

enum VertexURLBuilder {
    /// Builds a Vertex AI URL for Gemini models
    static func geminiURL(
        region: String,
        projectId: String,
        model: String,
        stream: Bool
    ) -> URL? {
        let normalizedModel = model.hasPrefix("models/") ? model.replacingOccurrences(of: "models/", with: "") : model
        let action = stream ? ":streamGenerateContent" : ":generateContent"
        
        var urlString =
            "https://\(region)-aiplatform.googleapis.com/v1/projects/\(projectId)/locations/\(region)/publishers/google/models/\(normalizedModel)\(action)"
        
        if stream {
            urlString += "?alt=sse"
        }
        
        return URL(string: urlString)
    }
    
    /// Builds a Vertex AI URL for Claude models
    static func claudeURL(
        region: String,
        projectId: String,
        model: String,
        stream: Bool
    ) -> URL? {
        let normalizedModel = model.hasPrefix("models/") ? model.replacingOccurrences(of: "models/", with: "") : model
        let action = stream ? ":streamRawPredict" : ":rawPredict"
        
        let urlString =
            "https://\(region)-aiplatform.googleapis.com/v1/projects/\(projectId)/locations/\(region)/publishers/anthropic/models/\(normalizedModel)\(action)"
        
        return URL(string: urlString)
    }
}

// MARK: - Shared Response Handling

enum VertexResponseHandler {
    static func handleAPIResponse(
        _ response: URLResponse?,
        data: Data?,
        error: Error?
    ) -> Result<Data?, APIError> {
        if let error = error {
            return .failure(.requestFailed(error))
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            return .failure(.invalidResponse)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            var message = "HTTP \(httpResponse.statusCode)"

            if let data = data {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                if let decodedError = try? decoder.decode(VertexErrorEnvelope.self, from: data) {
                    message = decodedError.error.message
                }
                else if let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
                    message = raw
                }
            }

            switch httpResponse.statusCode {
            case 400:
                return .failure(.serverError("Bad Request: \(message)"))
            case 401, 403:
                // Clear token cache on auth failure
                Task { await VertexTokenManager.shared.clearCache() }
                return .failure(.unauthorized)
            case 429:
                return .failure(.rateLimited)
            case 500...599:
                return .failure(.serverError("Vertex AI Error: \(message)"))
            default:
                return .failure(.unknown(message))
            }
        }

        return .success(data)
    }
}

