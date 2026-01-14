//
//  APIServiceTemplate.swift
//  macai
//
//  Created by Renat Notfullin on 12.03.2025.
//

import Foundation

struct APIServiceTemplateCatalog: Codable {
    let providers: [APIServiceProviderTemplate]
}

struct APIServiceProviderTemplate: Codable, Identifiable {
    let id: String
    let displayName: String
    let description: String?
    let defaultName: String?
    let note: String?
    let models: [APIServiceModelTemplate]

    var defaultModel: APIServiceModelTemplate? {
        models.first(where: { $0.isDefaultModel }) ?? models.first
    }

    var iconName: String { "logo_" + id }
}

struct APIServiceModelTemplate: Codable, Identifiable {
    let id: String
    let displayName: String
    let description: String?
    let note: String?
    private let isDefault: Bool?
    private let requiresExpert: Bool?
    let settings: APIServiceTemplateSettings?

    var isDefaultModel: Bool { isDefault ?? false }
    var requiresExpertMode: Bool { requiresExpert ?? false }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case description
        case isDefault
        case requiresExpert = "requiresExpertMode"
        case note
        case settings
    }
}

extension APIServiceTemplateCatalog {
    static let empty = APIServiceTemplateCatalog(providers: [])
}

struct APIServiceTemplateSettings: Codable {
    let generateChatNames: Bool?
    let contextSize: Int?
    let useStreaming: Bool?
    let allowImageUploads: Bool?
    let allowPdfUploads: Bool?
    let imageGenerationSupported: Bool?

    enum CodingKeys: String, CodingKey {
        case generateChatNames
        case contextSize
        case useStreaming
        case allowImageUploads
        case allowPdfUploads
        case imageGenerationSupported
    }
}
