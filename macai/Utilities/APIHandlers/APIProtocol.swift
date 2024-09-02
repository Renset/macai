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
    case decodingFailed(Error)
    case unauthorized
    case rateLimited
    case serverError(String)
    case unknown(String)
}

protocol APIService {
    var name: String { get }
    var baseURL: URL { get }

    func sendMessage(_ message: String, chat: ChatEntity, contextSize: Int, completion: @escaping (Result<String, APIError>) -> Void)
    func sendMessageStream(_ message: String, chat: ChatEntity, contextSize: Int) async throws -> AsyncThrowingStream<String, Error>
}

protocol APIServiceConfiguration {
    var name: String { get set }
    var apiUrl: URL { get set }
    var apiKey: String { get set }
    var model: String { get set }
}
