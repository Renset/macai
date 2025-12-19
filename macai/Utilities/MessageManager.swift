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
                let partsEnvelope = encodePartsEnvelope(
                    from: (self.apiService as? GeminiHandler)?.consumeLastResponseParts(),
                    serviceType: chat.apiService?.type
                )
                self.addMessageToChat(chat: chat, message: messageBody, partsEnvelope: partsEnvelope)
                self.addNewMessageToRequestMessages(
                    chat: chat,
                    content: messageBody,
                    role: AppConstants.defaultRole,
                    geminiParts: decodePartsEnvelopeToBase64(partsEnvelope)
                )
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

                let geminiParts = encodePartsEnvelope(
                    from: (self.apiService as? GeminiHandler)?.consumeLastResponseParts(),
                    serviceType: chat.apiService?.type
                )

                if deferImageResponse {
                    self.addMessageToChat(chat: chat, message: accumulatedResponse, partsEnvelope: geminiParts)
                }
                else if let assistantMessage = streamingMessage ?? (chat.lastMessage?.own == false ? chat.lastMessage : nil) {
                    updateLastMessage(
                        chat: chat,
                        lastMessage: assistantMessage,
                        accumulatedResponse: accumulatedResponse
                    )
                    assistantMessage.messageParts = geminiParts
                }
                else {
                    self.addMessageToChat(chat: chat, message: accumulatedResponse, partsEnvelope: geminiParts)
                }

                chat.waitingForResponse = false

                addNewMessageToRequestMessages(
                    chat: chat,
                    content: accumulatedResponse,
                    role: AppConstants.defaultRole,
                    geminiParts: decodePartsEnvelopeToBase64(geminiParts)
                )

                // Save once at the end of the stream
                try? self.viewContext.save()
                completion(.success(()))
            }
            catch {
                print("Streaming error: \(error)")
                completion(.failure(error))
            }
        }
    }

    func generateChatNameIfNeeded(chat: ChatEntity, force: Bool = false) {
        guard force || chat.name == "", !chat.messagesArray.isEmpty else {
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
        var messages = constructRequestMessages(chat: chat, forUserMessage: userMessage, contextSize: contextSize)

        // Strip vendor-specific payloads when current service is not Gemini to avoid API validation errors.
        if !(apiService is GeminiHandler) {
            messages = messages.map { msg in
                var m = msg
                m.removeValue(forKey: "message_parts")
                return m
            }
        }

        return messages
    }

    private func addMessageToChat(chat: ChatEntity, message: String, partsEnvelope: Data? = nil) {
        let newMessage = MessageEntity(context: self.viewContext)
        let sequence = chat.nextSequence()
        newMessage.id = sequence
        if chat.responds(to: #selector(getter: MessageEntity.sequence)) || (chat.managedObjectContext?.persistentStoreCoordinator?.managedObjectModel.entitiesByName["MessageEntity"]?.attributesByName["sequence"] != nil) {
            newMessage.sequence = sequence
        }
        newMessage.body = message
        newMessage.timestamp = Date()
        newMessage.own = false
        newMessage.messageParts = partsEnvelope
        newMessage.chat = chat

        chat.updatedDate = Date()
        chat.addToMessages(newMessage)
        chat.objectWillChange.send()
    }

    private func addNewMessageToRequestMessages(chat: ChatEntity, content: String, role: String, geminiParts: String? = nil) {
        var message: [String: String] = ["role": role, "content": content]
        if let geminiParts {
            message["message_parts"] = geminiParts
        }
        chat.requestMessages.append(message)
    }

    private func updateLastMessage(chat: ChatEntity, lastMessage: MessageEntity, accumulatedResponse: String) {
        print("Streaming chunk received: \(accumulatedResponse.suffix(20))")
        chat.waitingForResponse = false
        lastMessage.body = accumulatedResponse
        lastMessage.timestamp = Date()
        lastMessage.waitingForResponse = false

        chat.objectWillChange.send()
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
            .suffix(contextSize)

        // Add conversation history
        for message in sortedMessages {
            var payload: [String: String] = [
                "role": message.own ? "user" : "assistant",
                "content": message.body,
            ]

            if let envelope = message.messageParts,
               let base64 = decodePartsEnvelopeToBase64(envelope),
               envelopeHasVendorGemini(envelope) {
                payload["message_parts"] = base64
            }

            messages.append(payload)
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

    // MARK: - Parts encoding helpers
    private func encodePartsEnvelope(from parts: [GeminiPartRequest]?, serviceType: String?) -> Data? {
        guard let parts, !parts.isEmpty else { return nil }
        let envelope = PartsEnvelope(serviceType: (serviceType ?? "gemini"), parts: parts)
        return try? JSONEncoder().encode(envelope)
    }

    private func decodePartsEnvelopeToBase64(_ data: Data?) -> String? {
        guard let data else { return nil }
        return data.base64EncodedString()
    }

    private func envelopeHasVendorGemini(_ data: Data) -> Bool {
        guard let env = try? JSONDecoder().decode(PartsEnvelope.self, from: data) else { return false }
        return env.serviceType.lowercased() == "gemini"
    }
}
