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
    /// Whether `temperature` holds a per-chat override. The legacy `temperature`
    /// column contains stale values (old versions wrote 0/1 unconditionally),
    /// so a companion flag is required to tell an override from leftovers.
    @NSManaged public var temperatureOverridden: Bool
    /// Per-chat context size override; 0 means "inherit from the assistant".
    @NSManaged public var contextSize: Int16
    /// Per-chat image generation override: 0 = inherit, 1 = enabled, 2 = disabled.
    @NSManaged public var imageGenerationMode: Int16
    @NSManaged public var apiServiceOverridden: Bool
    @NSManaged public var modelOverridden: Bool
    @NSManaged public var systemMessageOverridden: Bool
    @NSManaged public var top_p: Double
    @NSManaged public var behavior: String?
    @NSManaged public var draftMessage: String?
    @NSManaged public var draftImageIDs: String?
    @NSManaged public var draftFileIDs: String?
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

    // Cache for supportsSequencing check - computed once per app lifecycle
    private static var _supportsSequencingCache: Bool?
    
    private var supportsSequencing: Bool {
        // Return cached value if available
        if let cached = ChatEntity._supportsSequencingCache {
            return cached
        }
        
        // Compute and cache the value
        guard let context = self.managedObjectContext,
              let model = context.persistentStoreCoordinator?.managedObjectModel else {
            return true // Default to true if we can't check, but don't cache yet
        }
        let supports = model.entitiesByName["MessageEntity"]?.attributesByName["sequence"] != nil
        ChatEntity._supportsSequencingCache = supports
        return supports
    }

    public var messageSortDescriptors: [NSSortDescriptor] {
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
        fetchRequest.fetchBatchSize = 20  // Avoid materializing all objects at once

        return (try? context.fetch(fetchRequest)) ?? []
    }

    /// Optimized count that doesn't materialize all message objects
    public var messagesCount: Int {
        guard let context = self.managedObjectContext else {
            return (messages as? Set<MessageEntity>)?.count ?? 0
        }
        
        let fetchRequest = NSFetchRequest<MessageEntity>(entityName: "MessageEntity")
        fetchRequest.predicate = NSPredicate(format: "chat == %@", self)
        return (try? context.count(for: fetchRequest)) ?? 0
    }

    /// Optimized fetch that only retrieves the last message
    public var lastMessage: MessageEntity? {
        guard let context = self.managedObjectContext else {
            let set = messages as? Set<MessageEntity> ?? []
            return set.max { lhs, rhs in
                if supportsSequencing {
                    if lhs.sequence == rhs.sequence {
                        return lhs.timestamp < rhs.timestamp
                    }
                    return lhs.sequence < rhs.sequence
                }
                return lhs.timestamp < rhs.timestamp
            }
        }
        
        // Use a limit-1 fetch with descending sort to get only the last message
        let fetchRequest = NSFetchRequest<MessageEntity>(entityName: "MessageEntity")
        fetchRequest.predicate = NSPredicate(format: "chat == %@", self)
        
        // Reverse the sort descriptors to get the last message first
        if supportsSequencing {
            fetchRequest.sortDescriptors = [
                NSSortDescriptor(keyPath: \MessageEntity.sequence, ascending: false),
                NSSortDescriptor(keyPath: \MessageEntity.timestamp, ascending: false),
            ]
        } else {
            fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \MessageEntity.timestamp, ascending: false)]
        }
        fetchRequest.fetchLimit = 1
        
        return (try? context.fetch(fetchRequest))?.first
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
        
        // Ensure lastSequence is up to date with the actual messages in the database
        let dbMax = fetchMaxSequence()
        if dbMax > lastSequence {
            lastSequence = dbMax
        }
        
        lastSequence += 1
        return lastSequence
    }

    private func fetchMaxSequence() -> Int64 {
        guard let context = self.managedObjectContext else { return 0 }
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "MessageEntity")
        fetchRequest.predicate = NSPredicate(format: "chat == %@", self)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "sequence", ascending: false)]
        fetchRequest.fetchLimit = 1
        fetchRequest.resultType = .dictionaryResultType
        fetchRequest.propertiesToFetch = ["sequence"]
        
        do {
            if let results = try context.fetch(fetchRequest) as? [[String: Any]],
               let first = results.first,
               let maxSeq = first["sequence"] as? Int64 {
                return maxSeq
            }
        } catch {
            print("Error fetching max sequence: \(error)")
        }
        
        return 0
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
    @NSManaged public var reasoningDuration: Double
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
        self.newMessage = chatEntity.draftMessage
        self.requestMessages = chatEntity.requestMessages
        self.gptModel = chatEntity.gptModel
        self.systemMessage = chatEntity.systemMessage
        self.name = chatEntity.name
        self.apiServiceName = chatEntity.apiService?.name
        self.apiServiceType = chatEntity.apiService?.type
        self.personaName = chatEntity.persona?.name
        
        // Fetch messagesArray once and reuse for both messages and messagePreview
        let fetchedMessages = chatEntity.messagesArray
        self.messages = fetchedMessages.map { Message(messageEntity: $0) }

        // Use the last element from already-fetched messages instead of calling lastMessage again
        if let lastMsg = fetchedMessages.last {
            self.messagePreview = Message(messageEntity: lastMsg)
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

// Effective settings: the chat's own values win; anything the chat does not
// define is inherited from its assistant (persona). The Chat Settings panel
// writes to the chat only — assistants are edited in Settings → AI Assistants.
extension ChatEntity {
    var effectiveApiService: APIServiceEntity? {
        if apiServiceOverridden {
            return apiService
        }
        return persona?.apiService ?? apiService
    }

    var effectiveModel: String {
        let chatModel = gptModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if modelOverridden, chatModel.isEmpty == false {
            return chatModel
        }
        let personaModel = persona?.model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if personaModel.isEmpty == false {
            return personaModel
        }
        if chatModel.isEmpty == false {
            return chatModel
        }
        return AppConstants.defaultModel(for: effectiveApiService?.type)
    }

    var effectiveSystemMessage: String {
        if systemMessageOverridden || persona == nil {
            return systemMessage
        }
        return persona?.systemMessage ?? systemMessage
    }

    var effectiveTemperature: Float {
        if temperatureOverridden {
            return Float(min(max(temperature, 0), 1))
        }
        return persona?.temperature ?? AppConstants.defaultTemperatureForChat
    }

    var effectiveContextSize: Int {
        if contextSize > 0 {
            return Int(contextSize)
        }
        let personaSize = Int(persona?.contextSize ?? 0)
        if personaSize > 0 {
            return personaSize
        }
        return Int(AppConstants.chatGptContextSize)
    }

    var shouldUseStreamResponse: Bool {
        persona?.useStreamResponse ?? true
    }

    var shouldGenerateChatNames: Bool {
        persona?.generateChatNames ?? true
    }

    var imageGenerationEnabled: Bool {
        switch imageGenerationMode {
        case 1: return true
        case 2: return false
        default: return persona?.imageGenerationEnabled ?? false
        }
    }

    var supportsImageGeneration: Bool {
        (effectiveApiService?.imageGenerationSupported ?? false) && imageGenerationEnabled
    }

    /// Drops every per-chat override so the chat follows its assistant again,
    /// and re-snapshots the service/model/system message from the assistant.
    func resetToAssistantDefaults() {
        temperatureOverridden = false
        contextSize = 0
        imageGenerationMode = 0
        apiServiceOverridden = false
        modelOverridden = false
        systemMessageOverridden = false

        guard let persona else { return }
        if let personaService = persona.apiService {
            apiService = personaService
        }
        let personaModel = persona.model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        gptModel = personaModel.isEmpty
            ? AppConstants.defaultModel(for: effectiveApiService?.type)
            : personaModel
        systemMessage = persona.systemMessage ?? systemMessage
    }

    var allowsImageUploads: Bool {
        effectiveApiService?.imageUploadsAllowed ?? false
    }

    var allowsPdfUploads: Bool {
        effectiveApiService?.pdfUploadsAllowed ?? false
    }
}

extension APIServiceEntity: NSCopying {
    public func copy(with zone: NSZone? = nil) -> Any {
        let copy = APIServiceEntity(context: self.managedObjectContext!)
        copy.name = self.name
        copy.type = self.type
        copy.url = self.url
        copy.imageUploadsAllowed = self.imageUploadsAllowed
        copy.pdfUploadsAllowed = self.pdfUploadsAllowed
        copy.imageGenerationSupported = self.imageGenerationSupported
        // Legacy migration bridge only; API Services no longer own a default assistant.
        copy.defaultPersona = nil
        copy.isDefault = false
        copy.id = UUID()
        copy.tokenIdentifier = UUID().uuidString
        return copy
    }
}

extension PersonaEntity {
    /// Resolves the assistant used for a new chat. A global default is preferred
    /// for ordinary chats; service-specific shortcuts fall back to the first
    /// assistant bound to that service.
    static func preferredAssistant(
        in context: NSManagedObjectContext,
        for service: APIServiceEntity? = nil
    ) throws -> PersonaEntity? {
        let request = NSFetchRequest<PersonaEntity>(entityName: "PersonaEntity")
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \PersonaEntity.order, ascending: true),
            NSSortDescriptor(keyPath: \PersonaEntity.addedDate, ascending: true),
        ]
        if let service {
            request.predicate = NSPredicate(format: "apiService == %@", service)
        } else {
            request.predicate = NSPredicate(format: "apiService != nil")
        }

        let assistants = try context.fetch(request)
        return assistants.first(where: { $0.isDefault }) ?? assistants.first
    }

    static func setDefault(_ selected: PersonaEntity, in context: NSManagedObjectContext) throws {
        let request = NSFetchRequest<PersonaEntity>(entityName: "PersonaEntity")
        request.predicate = NSPredicate(format: "isDefault == YES")
        for assistant in try context.fetch(request) where assistant !== selected {
            assistant.isDefault = false
        }
        selected.isDefault = true
    }
}
