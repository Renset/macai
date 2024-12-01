//
//  APIServiceFactory.swift
//  macai
//
//  Created by Renat on 28.07.2024.
//

import Foundation

class APIServiceFactory {
    static func createAPIService(config: APIServiceConfiguration) -> APIService {
        var configName = AppConstants.defaultApiConfigurations[config.name.lowercased()]?.inherits ?? config.name.lowercased()
        
        switch configName {
        case "chatgpt":
            return ChatGPTHandler(config: config)
        case "ollama":
            return OllamaHandler(config: config)
        case "claude":
            return ClaudeHandler(config: config)
        default:
            fatalError("Unsupported API service: \(config.name)")
        }
    }
}
