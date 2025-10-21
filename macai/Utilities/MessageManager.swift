//
//  MessageManager.swift
//  macai
//
//  Created by Renat on 28.07.2024.
//

import CoreData
import Foundation

class MessageManager: ObservableObject {
    private var apiService: APIService
    private var viewContext: NSManagedObjectContext
    private var lastUpdateTime = Date()
    private let updateInterval = AppConstants.streamedResponseUpdateUIInterval

    init(apiService: APIService, viewContext: NSManagedObjectContext) {
        self.apiService = apiService
        self.viewContext = viewContext
    }

    func update(apiService: APIService, viewContext: NSManagedObjectContext) {
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
        let temperature = (chat.persona?.temperature ?? AppConstants.defaultTemperatureForChat).roundedToOneDecimal()

        let handleResult: (Result<String, APIError>) -> Void = { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let messageBody):
                chat.waitingForResponse = false
                self.addMessageToChat(chat: chat, message: messageBody)
                self.addNewMessageToRequestMessages(chat: chat, content: messageBody, role: AppConstants.defaultRole)
                self.viewContext.saveWithRetry(attempts: 1)
                
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: NSNotification.Name("NonStreamingMessageCompleted"), object: chat)
                }
                
                completion(.success(()))

            case .failure(let error):
                completion(.failure(error))
            }
        }

        apiService.sendMessage(requestMessages, temperature: temperature) { result in
            handleResult(result)
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
        let temperature = (chat.persona?.temperature ?? AppConstants.defaultTemperatureForChat).roundedToOneDecimal()

        Task {
            do {

                let stream = try await apiService.sendMessageStream(requestMessages, temperature: temperature)
                var accumulatedResponse = ""
                var deferImageResponse = false
                var streamingMessage: MessageEntity?
                chat.waitingForResponse = true

                for try await chunk in stream {
                    guard !chunk.isEmpty else { continue }

                    accumulatedResponse += chunk

                    if !deferImageResponse && chunk.contains("<image-uuid>") {
                        deferImageResponse = true
                        if let message = streamingMessage ?? (chat.lastMessage?.own == false ? chat.lastMessage : nil) {
                            chat.removeFromMessages(message)
                            viewContext.delete(message)
                            streamingMessage = nil
                            chat.objectWillChange.send()
                        }
                    }

                    if deferImageResponse {
                        continue
                    }

                    guard let lastMessage = chat.lastMessage else { continue }

                    if lastMessage.own {
                        self.addMessageToChat(chat: chat, message: accumulatedResponse)
                        streamingMessage = chat.lastMessage
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
                            streamingMessage = lastMessage
                        }
                    }
                }

                guard !accumulatedResponse.isEmpty else {
                    completion(.failure(APIError.invalidResponse))
                    return
                }

                if deferImageResponse {
                    self.addMessageToChat(chat: chat, message: accumulatedResponse)
                }
                else if let assistantMessage = streamingMessage ?? (chat.lastMessage?.own == false ? chat.lastMessage : nil) {
                    updateLastMessage(
                        chat: chat,
                        lastMessage: assistantMessage,
                        accumulatedResponse: accumulatedResponse
                    )
                }
                else {
                    self.addMessageToChat(chat: chat, message: accumulatedResponse)
                }

                chat.waitingForResponse = false

                addNewMessageToRequestMessages(
                    chat: chat,
                    content: accumulatedResponse,
                    role: AppConstants.defaultRole
                )
                completion(.success(()))
            }
            catch {
                print("Streaming error: \(error)")
                completion(.failure(error))
            }
        }
    }

    func generateChatNameIfNeeded(chat: ChatEntity, force: Bool = false) {
        guard force || chat.name == "", chat.messages.count > 0 else {
            #if DEBUG
                print("Chat name not needed, skipping generation")
            #endif
            return
        }

        let requestMessages = prepareRequestMessages(
            userMessage: AppConstants.chatGptGenerateChatInstruction,
            chat: chat,
            contextSize: 3
        )
        let personaTemperature = (chat.persona?.temperature ?? AppConstants.defaultTemperatureForChat)
            .roundedToOneDecimal()

        apiService.sendMessage(requestMessages, temperature: personaTemperature) {
            [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let messageBody):
                let chatName = self.sanitizeChatName(messageBody)
                chat.name = chatName
                self.viewContext.saveWithRetry(attempts: 3)
            case .failure(let error):
                print("Error generating chat name: \(error)")
            }
        }
    }

    private func sanitizeChatName(_ rawName: String) -> String {
        if let range = rawName.range(of: "**(.+?)**", options: .regularExpression) {
            return String(rawName[range]).trimmingCharacters(in: CharacterSet(charactersIn: "*"))
        }

        let lines = rawName.components(separatedBy: .newlines)
        if let lastNonEmptyLine = lines.last(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return lastNonEmptyLine.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return rawName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func testAPI(model: String, completion: @escaping (Result<Void, Error>) -> Void) {
        var requestMessages: [[String: String]] = []
        let temperature: Float = 1

        if !AppConstants.openAiReasoningModels.contains(model) {
            requestMessages.append([
                "role": "system",
                "content": "You are a test assistant.",
            ])
        }

        requestMessages.append(
            [
                "role": "user",
                "content": "This is a test message.",
            ])

        apiService.sendMessage(requestMessages, temperature: temperature) { result in
            switch result {
            case .success(_):
                completion(.success(()))

            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func prepareRequestMessages(userMessage: String, chat: ChatEntity, contextSize: Int) -> [[String: String]] {
        return constructRequestMessages(chat: chat, forUserMessage: userMessage, contextSize: contextSize)
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
        print("Streaming chunk received: \(accumulatedResponse.suffix(20))")
        chat.waitingForResponse = false
        lastMessage.body = accumulatedResponse
        lastMessage.timestamp = Date()
        lastMessage.waitingForResponse = false

        chat.objectWillChange.send()

        Task {
            await MainActor.run {
                self.viewContext.saveWithRetry(attempts: 1)
            }
        }
    }

    private func constructRequestMessages(chat: ChatEntity, forUserMessage userMessage: String?, contextSize: Int)
        -> [[String: String]]
    {
        var messages: [[String: String]] = []

        if !AppConstants.openAiReasoningModels.contains(chat.gptModel) {
            messages.append([
                "role": "system",
                "content": chat.systemMessage,
            ])
        }
        else {
            // Models like o1-mini and o1-preview don't support "system" role. However, we can pass the system message with "user" role instead.
            messages.append([
                "role": "user",
                "content": "Take this message as the system message: \(chat.systemMessage)",
            ])
        }

        let sortedMessages = chat.messagesArray
            .sorted { $0.timestamp < $1.timestamp }
            .suffix(contextSize)

        // Add conversation history
        for message in sortedMessages {
            messages.append([
                "role": message.own ? "user" : "assistant",
                "content": message.body,
            ])
        }

        // Add new user message if provided
        let lastMessage = messages.last?["content"] ?? ""
        if lastMessage != userMessage {
            if let userMessage = userMessage {
                messages.append([
                    "role": "user",
                    "content": userMessage,
                ])
            }
        }

        return messages
    }
}
