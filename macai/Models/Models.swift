//
//  Models.swift
//  macai
//
//  Created by Renat Notfullin on 24.04.2023.
//

import CoreData
import Foundation
import SwiftUI

class ChatEntity: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var messages: NSOrderedSet
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
    @NSManaged public var waitingForResponse: Bool
    @NSManaged public var persona: PersonaEntity?
    @NSManaged public var apiService: APIServiceEntity?
    @NSManaged public var isPinned: Bool

    public var messagesArray: [MessageEntity] {
        let array = messages.array as? [MessageEntity] ?? []
        return array
    }

    public var lastMessage: MessageEntity? {
        return messages.lastObject as? MessageEntity
    }

    public func addToMessages(_ message: MessageEntity) {
        let newMessages = NSMutableOrderedSet(orderedSet: messages)
        newMessages.add(message)
        messages = newMessages
    }

    public func removeFromMessages(_ message: MessageEntity) {
        let newMessages = NSMutableOrderedSet(orderedSet: messages)
        newMessages.remove(message)
        messages = newMessages
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
    var apiServiceName: String?
    var apiServiceType: String?
    var personaName: String?

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
        self.apiServiceName = chatEntity.apiService?.name
        self.apiServiceType = chatEntity.apiService?.type
        self.personaName = chatEntity.persona?.name
        
        self.messages = chatEntity.messagesArray.map { Message(messageEntity: $0) }

        if chatEntity.lastMessage != nil {
            self.messagePreview = Message(messageEntity: chatEntity.lastMessage!)
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

extension ChatEntity {
    func addUserMessage(_ message: String) {
        let newMessage = ["role": "user", "content": message]
        self.requestMessages.append(newMessage)
    }
}

extension ChatEntity {
    func clearMessages() {
        let allMessages = self.messages.array as? [MessageEntity] ?? []
        for message in allMessages {
            self.managedObjectContext?.delete(message)
        }
        self.messages = NSOrderedSet()
        self.newChat = true
    }
}

extension APIServiceEntity: NSCopying {
    public func copy(with zone: NSZone? = nil) -> Any {
        let copy = APIServiceEntity(context: self.managedObjectContext!)
        copy.name = self.name
        copy.type = self.type
        copy.url = self.url
        copy.model = self.model
        copy.contextSize = self.contextSize
        copy.useStreamResponse = self.useStreamResponse
        copy.generateChatNames = self.generateChatNames
        copy.defaultPersona = self.defaultPersona
        return copy
    }
}
