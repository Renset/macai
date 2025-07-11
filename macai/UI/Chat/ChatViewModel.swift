//
//  ChatViewModel.swift
//  macai
//
//  Created by Renat on 29.07.2024.
//

import Combine
import Foundation
import SwiftUI

class ChatViewModel: ObservableObject {
    @Published var messages: NSOrderedSet
    @Published var visibleMessages: [MessageEntity] = []
    @Published var isLoadingMoreMessages = false
    
    private let chat: ChatEntity
    private let viewContext: NSManagedObjectContext
    private let initialMessageCount = 5
    private let loadMoreBatchSize = 10
    private var currentLoadedCount = 0

    private var _messageManager: MessageManager?
    private var messageManager: MessageManager {
        get {
            if _messageManager == nil {
                _messageManager = createMessageManager()
            }
            return _messageManager!
        }
        set {
            _messageManager = newValue
        }
    }

    private var cancellables = Set<AnyCancellable>()

    init(chat: ChatEntity, viewContext: NSManagedObjectContext) {
        self.chat = chat
        self.messages = chat.messages
        self.viewContext = viewContext
        loadInitialMessages()
    }

    func sendMessage(_ message: String, contextSize: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        self.messageManager.sendMessage(message, in: chat, contextSize: contextSize) { [weak self] result in
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
        self.messageManager.sendMessageStream(message, in: chat, contextSize: contextSize) { [weak self] result in
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
        refreshVisibleMessages()
    }

    var sortedMessages: [MessageEntity] {
        return self.chat.messagesArray
    }
    
    private func loadInitialMessages() {
        let allMessages = self.chat.messagesArray
        let totalCount = allMessages.count
        
        if totalCount <= initialMessageCount {
            visibleMessages = allMessages
            currentLoadedCount = totalCount
        } else {
            // Load the latest N messages
            let startIndex = totalCount - initialMessageCount
            visibleMessages = Array(allMessages[startIndex...])
            currentLoadedCount = initialMessageCount
        }
    }
    
    func loadMoreMessages() {
        guard !isLoadingMoreMessages else { return }
        
        let allMessages = self.chat.messagesArray
        let totalCount = allMessages.count
        let remainingCount = totalCount - currentLoadedCount
        
        guard remainingCount > 0 else { return }
        
        isLoadingMoreMessages = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            
            let messagesToLoad = min(self.loadMoreBatchSize, remainingCount)
            let newStartIndex = totalCount - self.currentLoadedCount - messagesToLoad
            let newEndIndex = totalCount - self.currentLoadedCount
            
            let newMessages = Array(allMessages[newStartIndex..<newEndIndex])
            
            self.visibleMessages = newMessages + self.visibleMessages
            self.currentLoadedCount += messagesToLoad
            self.isLoadingMoreMessages = false
        }
    }
    
    func refreshVisibleMessages() {
        let allMessages = self.chat.messagesArray
        let totalCount = allMessages.count
        
        if totalCount <= currentLoadedCount {
            visibleMessages = allMessages
            currentLoadedCount = totalCount
        } else {
            let startIndex = totalCount - currentLoadedCount
            visibleMessages = Array(allMessages[startIndex...])
        }
    }

    private func createMessageManager() -> MessageManager {
        guard let config = self.loadCurrentAPIConfig() else {
            fatalError("No valid API configuration found")
        }
        print(">> Creating new MessageManager with URL: \(config.apiUrl) and model: \(config.model)")
        return MessageManager(
            apiService: APIServiceFactory.createAPIService(config: config),
            viewContext: self.viewContext
        )
    }

    func recreateMessageManager() {
        _messageManager = createMessageManager()
    }

    var canSendMessage: Bool {
        return chat.apiService != nil
    }

    private func loadCurrentAPIConfig() -> APIServiceConfiguration? {
        guard let apiService = chat.apiService, let apiServiceUrl = apiService.url else {
            return nil
        }

        var apiKey = ""
        do {
            apiKey = try TokenManager.getToken(for: apiService.id?.uuidString ?? "") ?? ""
        }
        catch {
            print("Error extracting token: \(error) for \(apiService.id?.uuidString ?? "")")
        }

        return APIServiceConfig(
            name: getApiServiceName(),
            apiUrl: apiServiceUrl,
            apiKey: apiKey,
            model: chat.gptModel
        )
    }

    private func getApiServiceName() -> String {
        return chat.apiService?.type ?? "chatgpt"
    }
    
    func regenerateChatName() {
        messageManager.generateChatNameIfNeeded(chat: chat, force: true)
    }
}
