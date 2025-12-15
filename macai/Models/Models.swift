//
//  Models.swift
//  macai
//
//  Created by Renat Notfullin on 24.04.2023.
//

import CoreData
import Foundation
import SwiftUI

public class ChatEntity: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var messages: NSSet?
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
    @NSManaged public var lastSequence: Int64

    private var supportsSequencing: Bool {
        guard let model = self.managedObjectContext?.persistentStoreCoordinator?.managedObjectModel else { return true }
        return model.entitiesByName["MessageEntity"]?.attributesByName["sequence"] != nil
    }

    private var messageSortDescriptors: [NSSortDescriptor] {
        if supportsSequencing {
            return [
                NSSortDescriptor(keyPath: \MessageEntity.sequence, ascending: true),
                NSSortDescriptor(keyPath: \MessageEntity.timestamp, ascending: true),
            ]
        } else {
            return [NSSortDescriptor(keyPath: \MessageEntity.timestamp, ascending: true)]
        }
    }

    public var messagesArray: [MessageEntity] {
        guard let context = self.managedObjectContext else {
            let set = messages as? Set<MessageEntity> ?? []
            return set.sorted { lhs, rhs in
                if supportsSequencing, lhs.sequence == rhs.sequence {
                    return lhs.timestamp < rhs.timestamp
                }
                if supportsSequencing {
                    return lhs.sequence < rhs.sequence
                }
                if lhs.timestamp == rhs.timestamp {
                    return lhs.objectID.uriRepresentation().absoluteString < rhs.objectID.uriRepresentation().absoluteString
                }
                return lhs.timestamp < rhs.timestamp
            }
        }

        let fetchRequest = NSFetchRequest<MessageEntity>(entityName: "MessageEntity")
        fetchRequest.predicate = NSPredicate(format: "chat == %@", self)
        fetchRequest.sortDescriptors = messageSortDescriptors

        return (try? context.fetch(fetchRequest)) ?? []
    }

    public var messagesCount: Int {
        return messagesArray.count
    }

    public var lastMessage: MessageEntity? {
        return messagesArray.last
    }

    public func addToMessages(_ message: MessageEntity) {
        applySequenceIfNeeded(to: message)

        if message.chat !== self {
            message.chat = self
        }

        let mutableSet = NSMutableSet(set: messages ?? NSSet())
        mutableSet.add(message)
        messages = mutableSet
    }

    public func removeFromMessages(_ message: MessageEntity) {
        let mutableSet = NSMutableSet(set: messages ?? NSSet())
        mutableSet.remove(message)
        messages = mutableSet
    }

    @discardableResult
    public func nextSequence() -> Int64 {
        guard supportsSequencing else {
            return Int64(messagesArray.count + 1)
        }
        lastSequence += 1
        return lastSequence
    }

    public func applySequenceIfNeeded(to message: MessageEntity) {
        guard supportsSequencing else { return }
        guard message.sequence <= 0 else {
            if message.sequence > lastSequence {
                lastSequence = message.sequence
            }
            if message.id == 0 {
                message.id = message.sequence
            }
            return
        }

        let newSequence = nextSequence()
        message.sequence = newSequence
        if message.id == 0 {
            message.id = newSequence
        }
    }
}

public class MessageEntity: NSManagedObject, Identifiable {
    @NSManaged public var id: Int64
    @NSManaged public var name: String
    @NSManaged public var body: String
    @NSManaged public var timestamp: Date
    @NSManaged public var own: Bool
    @NSManaged public var waitingForResponse: Bool
    @NSManaged public var messageParts: Data?
    @NSManaged public var sequence: Int64
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
        let allMessages = self.messages as? Set<MessageEntity> ?? []
        for message in allMessages {
            self.managedObjectContext?.delete(message)
        }
        self.messages = NSSet()
        self.newChat = true
        self.lastSequence = 0
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
        copy.imageUploadsAllowed = self.imageUploadsAllowed
        copy.imageGenerationSupported = self.imageGenerationSupported
        copy.defaultPersona = self.defaultPersona
        copy.id = UUID()
        copy.tokenIdentifier = UUID().uuidString
        return copy
    }
}
