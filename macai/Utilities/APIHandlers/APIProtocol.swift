//
//  APIProtocol.swift
//  macai
//
//  Created by Renat on 17.07.2024.
//

import Foundation

enum APIError: Error {
    case requestFailed(Error)
    case invalidResponse
    case decodingFailed(String)
    case unauthorized
    case rateLimited
    case serverError(String)
    case unknown(String)
    case noApiService(String)
}

protocol APIService {
    var name: String { get }
    var baseURL: URL { get }
    var session: URLSession { get }

    func sendMessage(
        _ requestMessages: [[String: String]],
        temperature: Float,
        completion: @escaping (Result<String, APIError>) -> Void
    )

    func sendMessageStream(_ requestMessages: [[String: String]], temperature: Float) async throws
        -> AsyncThrowingStream<String, Error>

    func fetchModels() async throws -> [AIModel]

    func cancelOngoingRequests()
    func resetSession()
}

protocol APIServiceConfiguration {
    var name: String { get set }
    var apiUrl: URL { get set }
    var apiKey: String { get set }
    var model: String { get set }
}

struct AIModel: Codable, Identifiable {
    let id: String

    init(id: String) {
        self.id = id
    }
}

extension APIService {
    func cancelOngoingRequests() {
        session.invalidateAndCancel()
    }

    func resetSession() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = AppConstants.requestTimeout
        configuration.timeoutIntervalForResource = AppConstants.requestTimeout
    }

    func fetchModels() async throws -> [AIModel] {
        return []
    }
}
