//
//  MessageManager.swift
//  macai
//
//  Created by Renat on 28.07.2024.
//

import CoreData
import Foundation

class MessageManager: ObservableObject {
    private let apiService: APIService
    private let viewContext: NSManagedObjectContext
    private var lastUpdateTime = Date()
    private let updateInterval = AppConstants.streamedResponseUpdateUIInterval

    init(apiService: APIService, viewContext: NSManagedObjectContext) {
        self.apiService = apiService
        self.viewContext = viewContext
    }

    func sendMessage(
        _ message: String,
        in chat: ChatEntity,
        contextSize: Int,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let requestMessages = prepareRequestMessages(userMessage: message, chat: chat, contextSize: contextSize)
        chat.waitingForResponse = true

        apiService.sendMessage(requestMessages) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let messageBody):
                chat.waitingForResponse = false
                addMessageToChat(chat: chat, message: messageBody)
                addNewMessageToRequestMessages(chat: chat, content: messageBody, role: AppConstants.defaultRole)
                self.viewContext.saveWithRetry(attempts: 1)
                completion(.success(()))

            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    @MainActor
    func sendMessageStream(
        _ message: String,
        in chat: ChatEntity,
        contextSize: Int,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let requestMessages = prepareRequestMessages(userMessage: message, chat: chat, contextSize: contextSize)
        Task {
            do {
                let stream = try await apiService.sendMessageStream(requestMessages)
                var accumulatedResponse = ""
                chat.waitingForResponse = true

                for try await chunk in stream {
                    accumulatedResponse += chunk
                    if let lastMessage = chat.lastMessage {
                        if lastMessage.own {
                            self.addMessageToChat(chat: chat, message: accumulatedResponse)
                        }
                        else {
                            let now = Date()
                            if now.timeIntervalSince(lastUpdateTime) >= updateInterval {
                                updateLastMessage(
                                    chat: chat,
                                    lastMessage: lastMessage,
                                    accumulatedResponse: accumulatedResponse
                                )
                                lastUpdateTime = now
                            }
                        }
                    }
                }
                updateLastMessage(chat: chat, lastMessage: chat.lastMessage!, accumulatedResponse: accumulatedResponse)
                addNewMessageToRequestMessages(chat: chat, content: accumulatedResponse, role: AppConstants.defaultRole)
                completion(.success(()))
            }
            catch {
                print("Streaming error: \(error)")
                completion(.failure(error))
            }
        }
    }

    func generateChatNameIfNeeded(chat: ChatEntity) {
        guard chat.name == "", chat.messages.count > 0 else {
            #if DEBUG
                print("Chat name not needed, skipping generation")
            #endif
            return
        }

        if !(chat.apiService?.generateChatNames ?? false) {
            return
        }

        let requestMessages = prepareRequestMessages(
            userMessage: AppConstants.chatGptGenerateChatInstruction,
            chat: chat,
            contextSize: 3
        )
        apiService.sendMessage(requestMessages) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let messageBody):
                let chatName = messageBody
                chat.name = chatName

                // remove 'generate chat name' instruction from requestMessages
                #if DEBUG
                    print("Length of requestMessages before deletion: \(chat.requestMessages.count)")
                #endif
                chat.requestMessages = chat.requestMessages.filter {
                    $0["content"] != AppConstants.chatGptGenerateChatInstruction
                }
                #if DEBUG
                    print("Length of requestMessages after deletion: \(chat.requestMessages.count)")
                #endif
                self.viewContext.saveWithRetry(attempts: 3)
            case .failure(let error):
                print("Error generating chat name: \(error)")
            }
        }
    }

    func testAPI(completion: @escaping (Result<Void, Error>) -> Void) {
        let requestMessages = [
            [
                "role": "system",
                "content": "You are a test assistant.",
            ],
            [
                "role": "user",
                "content": "This is a test message.",
            ],
        ]

        apiService.sendMessage(requestMessages) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let messageBody):
                completion(.success(()))

            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func prepareRequestMessages(userMessage: String, chat: ChatEntity, contextSize: Int) -> [[String: String]] {
        if chat.newChat {
            chat.requestMessages = [
                [
                    "role": "system",
                    "content": chat.systemMessage,
                ]
            ]
            chat.newChat = false
        }

        chat.requestMessages.append(["role": "user", "content": userMessage])

        return Array(
            chat.requestMessages.prefix(1)
                + chat.requestMessages.suffix(
                    contextSize > chat.requestMessages.count - 1 ? chat.requestMessages.count - 1 : contextSize
                )
        )
    }

    private func addMessageToChat(chat: ChatEntity, message: String) {
        let newMessage = MessageEntity(context: self.viewContext)
        newMessage.id = Int64(chat.messages.count + 1)
        newMessage.body = message
        newMessage.timestamp = Date()
        newMessage.own = false
        newMessage.chat = chat

        chat.updatedDate = Date()
        chat.addToMessages(newMessage)
        chat.objectWillChange.send()
    }

    private func addNewMessageToRequestMessages(chat: ChatEntity, content: String, role: String) {
        chat.requestMessages.append(["role": role, "content": content])
        self.viewContext.saveWithRetry(attempts: 1)
    }

    private func updateLastMessage(chat: ChatEntity, lastMessage: MessageEntity, accumulatedResponse: String) {
        chat.waitingForResponse = false
        lastMessage.body = accumulatedResponse
        lastMessage.timestamp = Date()
        lastMessage.waitingForResponse = false
        chat.objectWillChange.send()
        self.viewContext.saveWithRetry(attempts: 1)
    }
}
