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

class ChatStore: ObservableObject {
    let persistenceController: PersistenceController
    let viewContext: NSManagedObjectContext

    init(persistenceController: PersistenceController) {
        self.persistenceController = persistenceController
        self.viewContext = persistenceController.container.viewContext

        migrateFromJSONIfNeeded()
    }
    
    func saveInCoreData() {
        DispatchQueue.main.async {
            do {
                try  self.viewContext.saveWithRetry(attempts: 3)
            } catch {
                print("[Warning] Couldn't save to store")
            }
        }
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
                let fetchRequest = ChatEntity.fetchRequest() as! NSFetchRequest<ChatEntity>
                fetchRequest.predicate = NSPredicate(format: "id == %@", oldChat.id as CVarArg)
                
                let existingChats = try self.viewContext.fetch(fetchRequest)
                
                if existingChats.isEmpty {
                    
                    let chatEntity = ChatEntity(context: self.viewContext)
                    chatEntity.id = oldChat.id
                    chatEntity.newChat = oldChat.newChat
                    chatEntity.temperature = oldChat.temperature ?? 0.0
                    chatEntity.top_p = oldChat.top_p ?? 0.0
                    chatEntity.behavior = oldChat.behavior
                    chatEntity.newMessage = oldChat.newMessage ?? ""
                    chatEntity.createdDate = Date()
                    chatEntity.updatedDate = Date()
                    chatEntity.requestMessages = oldChat.requestMessages
                    chatEntity.gptModel = oldChat.gptModel ?? AppConstants.chatGptDefaultModel
                    chatEntity.systemMessage = oldChat.systemMessage ?? AppConstants.chatGptSystemMessage
                    chatEntity.name = oldChat.name ?? ""
                    
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
    
    func deleteAllChats() {
        let fetchRequest = ChatEntity.fetchRequest() as! NSFetchRequest<ChatEntity>

        do {
            let chatEntities = try self.viewContext.fetch(fetchRequest)

            for chat in chatEntities {
                self.viewContext.delete(chat)
            }

            try self.viewContext.save()
        } catch {
            print("Error deleting all chats: \(error)")
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
            UserDefaults.standard.set(true, forKey: migrationKey)
            print("Error migrating chats: \(error)")
        }

    }

}
