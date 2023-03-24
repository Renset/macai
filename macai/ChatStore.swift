//
//  ChatStore.swift
//  macai
//
//  Created by Renat Notfullin on 11.03.2023.
//

import CoreData
import Foundation
import SwiftUI

let migrationKey = "com.example.chatApp.migrationFromJSONCompleted"

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

    init(chatEntity: ChatEntity) {
        self.id = chatEntity.id
        self.newChat = chatEntity.newChat
        self.temperature = chatEntity.temperature
        self.top_p = chatEntity.top_p
        self.behavior = chatEntity.behavior
        self.newMessage = chatEntity.newMessage
        self.requestMessages = chatEntity.requestMessages

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

class ChatStore: ObservableObject {
    let persistenceController: PersistenceController
    let viewContext: NSManagedObjectContext

    init(persistenceController: PersistenceController) {
        self.persistenceController = persistenceController
        self.viewContext = persistenceController.container.viewContext

        migrateFromJSONIfNeeded()
    }

    func loadFromCoreData(completion: @escaping (Result<[Chat], Error>) -> Void) {
        let fetchRequest = ChatEntity.fetchRequest() as! NSFetchRequest<ChatEntity>

        do {
            let chatEntities = try self.viewContext.fetch(fetchRequest)
            let chats = chatEntities.map { Chat(chatEntity: $0) }

            DispatchQueue.main.async {
                completion(.success(chats))
            }
        }
        catch {
            DispatchQueue.main.async {
                completion(.failure(error))
            }
        }
    }

    func saveToCoreData(chats: [Chat], completion: @escaping (Result<Int, Error>) -> Void) {
        do {
            for oldChat in chats {
                let chatEntity = ChatEntity(context: self.viewContext)
                chatEntity.id = oldChat.id
                chatEntity.newChat = oldChat.newChat
                chatEntity.temperature = oldChat.temperature ?? 0.0
                chatEntity.top_p = oldChat.top_p ?? 0.0
                chatEntity.behavior = oldChat.behavior
                chatEntity.newMessage = oldChat.newMessage
                chatEntity.createdDate = Date()
                chatEntity.updatedDate = Date()
                chatEntity.requestMessages = oldChat.requestMessages

                for oldMessage in oldChat.messages {
                    let messageEntity = MessageEntity(context: self.viewContext)
                    messageEntity.id = Int64(oldMessage.id)
                    messageEntity.name = oldMessage.name
                    messageEntity.body = oldMessage.body
                    messageEntity.timestamp = oldMessage.timestamp
                    messageEntity.own = oldMessage.own
                    messageEntity.waitingForResponse = oldMessage.waitingForResponse ?? false
                    messageEntity.chat = chatEntity

                    chatEntity.addToMessages(messageEntity)
                }
            }

            DispatchQueue.main.async {
                completion(.success(chats.count))
            }

            try self.viewContext.save()
        }
        catch {
            DispatchQueue.main.async {
                completion(.failure(error))
            }
        }
    }

    private static func fileURL() throws -> URL {
        try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ).appendingPathComponent("chats.data")
    }

    private func migrateFromJSONIfNeeded() {
        if UserDefaults.standard.bool(forKey: migrationKey) {
            return
        }

        do {
            let fileURL = try ChatStore.fileURL()
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            let oldChats = try decoder.decode([Chat].self, from: data)

            saveToCoreData(chats: oldChats) { result in
                print("State saved")
                if case .failure(let error) = result {
                    fatalError(error.localizedDescription)
                }
            }

            UserDefaults.standard.set(true, forKey: migrationKey)
            try FileManager.default.removeItem(at: fileURL)

            print("Migration from JSON successful")
        }
        catch {
            print("Error migrating chats: \(error)")
        }

    }

}
