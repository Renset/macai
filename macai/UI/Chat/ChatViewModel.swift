//
//  ChatViewModel.swift
//  macai
//
//  Created by Renat on 29.07.2024.
//

import Combine
import Foundation
import SwiftUI

struct SearchOccurrence: Equatable {
    let messageID: NSManagedObjectID
    let range: NSRange

    static func == (lhs: SearchOccurrence, rhs: SearchOccurrence) -> Bool {
        return lhs.messageID == rhs.messageID && NSEqualRanges(lhs.range, rhs.range)
    }
}

class ChatViewModel: ObservableObject {
    // MARK: - Search State
    @Published var searchOccurrences: [SearchOccurrence] = []
    @Published var currentSearchIndex: Int? = nil

    var currentSearchOccurrence: SearchOccurrence? {
        if let index = currentSearchIndex, searchOccurrences.indices.contains(index) {
            return searchOccurrences[index]
        }
        return nil
    }
    @Published var messages: NSOrderedSet
    private let chat: ChatEntity
    private let viewContext: NSManagedObjectContext

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
    }

    var sortedMessages: [MessageEntity] {
        return self.chat.messagesArray
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

    // MARK: - Search Logic
    func updateSearchOccurrences(searchText: String) {
        var occurrences: [SearchOccurrence] = []
        if !searchText.isEmpty {
            for message in sortedMessages {
                let body = message.body
                var searchStartIndex = body.startIndex
                while let range = body.range(of: searchText, options: .caseInsensitive, range: searchStartIndex..<body.endIndex) {
                    let nsRange = NSRange(range, in: body)
                    let occurrence = SearchOccurrence(messageID: message.objectID, range: nsRange)
                    occurrences.append(occurrence)
                    searchStartIndex = range.upperBound
                }
            }
        }
        searchOccurrences = occurrences
        currentSearchIndex = occurrences.isEmpty ? nil : 0
    }

    func goToNextOccurrence() {
        guard let currentIndex = currentSearchIndex, !searchOccurrences.isEmpty else { return }
        let nextIndex = currentIndex + 1
        currentSearchIndex = nextIndex >= searchOccurrences.count ? 0 : nextIndex
    }

    func goToPreviousOccurrence() {
        guard let currentIndex = currentSearchIndex, !searchOccurrences.isEmpty else { return }
        let prevIndex = currentIndex - 1
        currentSearchIndex = prevIndex < 0 ? searchOccurrences.count - 1 : prevIndex
    }
}
