//
//  Models.swift
//  macai
//
//  Created by Renat Notfullin on 24.04.2023.
//

import Foundation
import CoreData
import SwiftUI

class ChatEntity: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var messages: Set<MessageEntity>
    @NSManaged public var requestMessages: [[String: String]]
    @NSManaged public var newChat: Bool
    @NSManaged public var temperature: Double
    @NSManaged public var top_p: Double
    @NSManaged public var behavior: String?
    @NSManaged public var newMessage: String?
    @NSManaged public var createdDate: Date
    @NSManaged public var updatedDate: Date
    @NSManaged public var systemMessage: String
    @NSManaged public var gptModel: String
    @NSManaged public var name: String
    
    func addToMessages(_ value: MessageEntity) {
        let items = self.mutableSetValue(forKey: "messages")
        items.add(value)
        value.chat = self

        self.objectWillChange.send()
    }

    func removeFromMessages(_ value: MessageEntity) {
        let items = self.mutableSetValue(forKey: "messages")
        items.remove(value)
        value.chat = nil
    }
    
    #warning("Temporary code for migrating old chats - remove after a while, when users have been updated. Issue link: https://github.com/Renset/macai/issues/7")
    @AppStorage("gptModel") var gptModelFromSettings = AppConstants.chatGptDefaultModel
    @AppStorage("systemMessage") var systemMessageFromSettings = AppConstants.chatGptSystemMessage
    @NSManaged public var systemMessageProcessed: Bool
    func extractSystemMessageAndModel() {
        guard !systemMessageProcessed && systemMessage == nil else {
            return
        }
        
        if let systemMessageIndex = requestMessages.firstIndex(where: { $0["role"] == "system" }) {
            systemMessage = requestMessages[systemMessageIndex]["content"]?.replacingOccurrences(of: "\n", with: " ") ?? systemMessageFromSettings
        } else {
            systemMessage = systemMessageFromSettings // Set your defåault value here
        }
        
        if (gptModel == nil) {
            gptModel = gptModelFromSettings
        }
        
        systemMessageProcessed = true
    }
}

class MessageEntity: NSManagedObject, Identifiable {
    @NSManaged public var id: Int64
    @NSManaged public var name: String
    @NSManaged public var body: String
    @NSManaged public var timestamp: Date
    @NSManaged public var own: Bool
    @NSManaged public var waitingForResponse: Bool
    @NSManaged public var chat: ChatEntity?
}

/// Legacy Chat struct, used for migration from old storage, for exporting and importing data in JSON
struct Chat: Codable {
    var id: UUID
    var messagePreview: Message?
    var messages: [Message] = []
    var requestMessages = [["role": "user", "content": ""]]
    var newChat: Bool = true
    var temperature: Float64?
    var top_p: Float64?
    var behavior: String?
    var newMessage: String?
    var gptModel: String?
    var systemMessage: String?
    var name: String?

    init(chatEntity: ChatEntity) {
        self.id = chatEntity.id
        self.newChat = chatEntity.newChat
        self.temperature = chatEntity.temperature
        self.top_p = chatEntity.top_p
        self.behavior = chatEntity.behavior
        self.newMessage = chatEntity.newMessage
        self.requestMessages = chatEntity.requestMessages
        self.gptModel = chatEntity.gptModel
        self.systemMessage = chatEntity.systemMessage
        self.name = chatEntity.name

        if let messageEntities = chatEntity.messages as? Set<MessageEntity> {
            self.messages = messageEntities.map { Message(messageEntity: $0) }
        }

        if let lastMessageEntity = chatEntity.messages.max(by: { $0.id < $1.id }) {
            self.messagePreview = Message(messageEntity: lastMessageEntity)
        }
    }
}

/// Legacy Message struct, used for migration from old storage, for exporting and importing data in JSON
struct Message: Codable, Equatable {
    var id: Int
    var name: String
    var body: String
    var timestamp: Date
    var own: Bool
    var waitingForResponse: Bool?

    init(messageEntity: MessageEntity) {
        self.id = Int(messageEntity.id)
        self.name = messageEntity.name
        self.body = messageEntity.body
        self.timestamp = messageEntity.timestamp
        self.own = messageEntity.own
        self.waitingForResponse = messageEntity.waitingForResponse
    }
}
