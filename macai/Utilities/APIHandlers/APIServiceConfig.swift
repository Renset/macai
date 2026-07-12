//
//  APIServiceConfig.swift
//  macai
//
//  Created by Renat on 28.07.2024.
//

import Foundation

struct APIServiceConfig: APIServiceConfiguration, Codable {
    var name: String
    var apiUrl: URL
    var apiKey: String
    var model: String
    var customHeaders: [String: String] = [:]
}

enum APIServiceHeaderStore {
    private static let identifier = "custom_headers"

    static func load(for serviceID: UUID) -> [String: String] {
        guard let json = try? TokenManager.getToken(for: serviceID.uuidString, identifier: identifier),
              let data = json.data(using: .utf8),
              let headers = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return headers
    }

    static func save(_ headers: [String: String], for serviceID: UUID) throws {
        if headers.isEmpty {
            try TokenManager.deleteToken(for: serviceID.uuidString, identifier: identifier)
            return
        }
        let data = try JSONEncoder().encode(headers)
        guard let json = String(data: data, encoding: .utf8) else { return }
        try TokenManager.setToken(json, for: serviceID.uuidString, identifier: identifier)
    }

    static func delete(for serviceID: UUID) {
        try? TokenManager.deleteToken(for: serviceID.uuidString, identifier: identifier)
    }
}
