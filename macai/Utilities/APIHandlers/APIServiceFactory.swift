//
//  APIServiceFactory.swift
//  macai
//
//  Created by Renat on 28.07.2024.
//

import Foundation

class APIServiceFactory {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = AppConstants.requestTimeout
        configuration.timeoutIntervalForResource = AppConstants.requestTimeout
        return URLSession(configuration: configuration)
    }()
    
    static func createAPIService(config: APIServiceConfiguration) -> APIService {
        let configName = AppConstants.defaultApiConfigurations[config.name.lowercased()]?.inherits ?? config.name.lowercased()
        
        switch configName {
        case "chatgpt":
            return ChatGPTHandler(config: config, session: session)
        case "ollama":
            return OllamaHandler(config: config, session: session)
        case "claude":
            return ClaudeHandler(config: config, session: session)
        default:
            fatalError("Unsupported API service: \(config.name)")
        }
    }
}
