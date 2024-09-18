//
//  ChatViewModel.swift
//  macai
//
//  Created by Renat on 29.07.2024.
//

import Foundation
import SwiftUI

class ChatViewModel: ObservableObject {
    @Published var messages: NSOrderedSet
    private let chat: ChatEntity
    private let viewContext: NSManagedObjectContext
    private lazy var messageManager: MessageManager = {
        guard let config = self.loadCurrentAPIConfig() else {
            fatalError("No valid API configuration found")
        }
        return MessageManager(apiService: APIServiceFactory.createAPIService(config: config), viewContext: self.viewContext)
    }()
    @AppStorage("gptToken") var apiKey = ""
    @AppStorage("apiUrl") var apiUrl: String = AppConstants.apiUrlChatCompletions

    init(chat: ChatEntity, viewContext: NSManagedObjectContext) {
        self.chat = chat
        self.messages = chat.messages
        self.viewContext = viewContext
    }

    func sendMessage(_ message: String, contextSize: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        messageManager.sendMessage(message, in: chat, contextSize: contextSize) { [weak self] result in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    @MainActor
    func sendMessageStream(_ message: String, contextSize: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        messageManager.sendMessageStream(message, in: chat, contextSize: contextSize) { [weak self] result in
            switch result {
            case .success:
                self?.chat.objectWillChange.send()
                completion(.success(()))
                self?.reloadMessages()
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    func generateChatNameIfNeeded() {
        messageManager.generateChatNameIfNeeded(chat: chat)
    }

    func reloadMessages() {
        messages = self.messages
    }
    
    var sortedMessages: [MessageEntity] {
        return self.chat.messagesArray
    }
    
    private func loadCurrentAPIConfig() -> APIServiceConfiguration? {
        var apiKey = ""
        do {
            apiKey = try TokenManager.getToken(for: chat.apiService?.id?.uuidString ?? "") ?? ""
        } catch {
            print("Error extracting token: \(error) for \(chat.apiService?.id?.uuidString ?? "")")
        }
        
        print(">> Extracted token: \(apiKey)")
        
        return APIServiceConfig(
            name: getApiServiceName(),
            apiUrl: URL(string: apiUrl)!,
            apiKey: apiKey,
            model: chat.apiService?.model ?? ""
        )
    }
    
    // Temp function until GPT Service configurator is implemented
    private func getApiServiceName() -> String {
        if apiUrl.contains(":11434/api/chat") {
            return "Ollama"
        }
        
        return "ChatGPT"
    }
}
