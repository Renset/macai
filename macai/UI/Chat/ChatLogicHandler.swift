//
//  ChatLogicHandler.swift
//  macai
//
//  Created by AI Assistant on 20.01.2025.
//

import CoreData
import SwiftUI
import Foundation
import UniformTypeIdentifiers

class ChatLogicHandler: ObservableObject {
    private let viewContext: NSManagedObjectContext
    private let chat: ChatEntity
    private let chatViewModel: ChatViewModel
    private let store: ChatStore
    
    @Published var currentError: ErrorMessage?
    @Published var isStreaming: Bool = false
    @Published var userIsScrolling: Bool = false
    
    init(viewContext: NSManagedObjectContext, chat: ChatEntity, chatViewModel: ChatViewModel, store: ChatStore) {
        self.viewContext = viewContext
        self.chat = chat
        self.chatViewModel = chatViewModel
        self.store = store
    }
    
    func sendMessage(messageText: String, attachedImages: [ImageAttachment], generateImage: Bool = false) {
        guard chatViewModel.canSendMessage else {
            currentError = ErrorMessage(
                type: .noApiService("No API service selected. Select the API service to send your first message"),
                timestamp: Date()
            )
            return
        }

        resetError()

        var messageContents: [MessageContent] = []

        if !messageText.isEmpty {
            messageContents.append(MessageContent(text: messageText))
        }

        for attachment in attachedImages {
            if attachment.imageEntity?.image == nil {
                attachment.saveToEntity(context: viewContext, waitForCompletion: true)
            }
            messageContents.append(MessageContent(imageAttachment: attachment))
        }

        let messageBody: String
        let hasImages = !attachedImages.isEmpty

        if hasImages {
            messageBody = messageContents.toString()
        } else {
            messageBody = messageText
        }

        saveNewMessageInStore(with: messageBody)
        userIsScrolling = false

        if (chat.apiService?.useStreamResponse ?? false) && !generateImage {
            sendStreamMessage(messageBody)
        } else {
            sendRegularMessage(messageBody, generateImage: generateImage)
        }
    }
    
    func selectAndAddImages(completion: @escaping ([ImageAttachment]) -> Void) {
        guard chat.apiService?.imageUploadsAllowed == true else { return }

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.jpeg, .png, .heic, .heif, UTType(filenameExtension: "webp")].compactMap { $0 }
        panel.title = "Select Images"
        panel.message = "Choose images to upload"

        panel.begin { response in
            if response == .OK {
                var newAttachments: [ImageAttachment] = []
                for url in panel.urls {
                    let attachment = ImageAttachment(url: url, context: self.viewContext)
                    newAttachments.append(attachment)
                }
                DispatchQueue.main.async {
                    completion(newAttachments)
                }
            }
        }
    }
    
    func handleRetryMessage(newMessage: inout String) {
        guard !chat.waitingForResponse && !isStreaming else { return }

        if currentError != nil {
            sendMessage(messageText: newMessage, attachedImages: [])
        } else {
            if let lastUserMessage = chatViewModel.sortedMessages.last(where: { $0.own }) {
                let messageToResend = lastUserMessage.body

                if let lastMessage = chatViewModel.sortedMessages.last {
                    viewContext.delete(lastMessage)
                    if !lastMessage.own,
                        let secondLastMessage = chatViewModel.sortedMessages.dropLast().last
                    {
                        viewContext.delete(secondLastMessage)
                    }
                    try? viewContext.save()
                }

                newMessage = messageToResend
                sendMessage(messageText: newMessage, attachedImages: [])
            }
        }
    }
    
    func ignoreError() {
        currentError = nil
    }
    
    // MARK: - Private Methods
    
    private func sendStreamMessage(_ messageBody: String) {
        isStreaming = true
        Task { @MainActor in
            chatViewModel.sendMessageStream(
                messageBody,
                contextSize: Int(chat.apiService?.contextSize ?? Int16(AppConstants.chatGptContextSize))
            ) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        self.handleResponseFinished()
                        self.chatViewModel.generateChatNameIfNeeded()
                    case .failure(let error):
                        print("Error sending message: \(error)")
                        let apiError = error as? APIError ?? .unknown("Unknown error occurred")
                        self.currentError = ErrorMessage(type: apiError, timestamp: Date())
                        self.handleResponseFinished()
                    }
                }
            }
        }
    }
    
    private func sendRegularMessage(_ messageBody: String, generateImage: Bool) {
        chat.waitingForResponse = true
        chatViewModel.sendMessage(
            messageBody,
            contextSize: Int(chat.apiService?.contextSize ?? Int16(AppConstants.chatGptContextSize)),
            generateImage: generateImage
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.chatViewModel.generateChatNameIfNeeded()
                    self.handleResponseFinished()
                case .failure(let error):
                    print("Error sending message: \(error)")
                    let apiError = error as? APIError ?? .unknown("Unknown error occurred")
                    self.currentError = ErrorMessage(type: apiError, timestamp: Date())
                    self.handleResponseFinished()
                }
            }
        }
    }
    
    private func saveNewMessageInStore(with messageBody: String) {
        let newMessageEntity = MessageEntity(context: viewContext)
        newMessageEntity.id = Int64(chat.messages.count + 1)
        newMessageEntity.body = messageBody
        newMessageEntity.timestamp = Date()
        newMessageEntity.own = true
        newMessageEntity.chat = chat

        chat.updatedDate = Date()
        chat.addToMessages(newMessageEntity)
        chat.objectWillChange.send()
        
        store.saveInCoreData()
    }
    
    private func handleResponseFinished() {
        isStreaming = false
        chat.waitingForResponse = false
        userIsScrolling = false
    }
    
    private func resetError() {
        currentError = nil
    }
}
