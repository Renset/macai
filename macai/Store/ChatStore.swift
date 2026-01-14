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
        //        DispatchQueue.main.async {
        //            do {
        //                try  self.viewContext.saveWithRetry(attempts: 3)
        //            } catch {
        //                print("[Warning] Couldn't save to store")
        //            }
        //        }
        Task {
            await MainActor.run {
                self.viewContext.saveWithRetry(attempts: 1)
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
            let defaultApiService: APIServiceEntity? = {
                let request = NSFetchRequest<APIServiceEntity>(entityName: "APIServiceEntity")
                request.predicate = NSPredicate(format: "isDefault == YES")
                request.fetchLimit = 1
                if let service = try? viewContext.fetch(request).first {
                    return service
                }

                if let defaultServiceIDString = UserDefaults.standard.string(forKey: "defaultApiService"),
                   let url = URL(string: defaultServiceIDString),
                   let objectID = viewContext.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: url),
                   let service = try? viewContext.existingObject(with: objectID) as? APIServiceEntity
                {
                    service.isDefault = true
                    viewContext.saveWithRetry(attempts: 1)
                    UserDefaults.standard.removeObject(forKey: "defaultApiService")
                    return service
                }

                return nil
            }()

            for oldChat in chats {
                let fetchRequest = ChatEntity.fetchRequest() as! NSFetchRequest<ChatEntity>
                fetchRequest.predicate = NSPredicate(format: "id == %@", oldChat.id as CVarArg)

                let existingChats = try viewContext.fetch(fetchRequest)

                if existingChats.isEmpty {
                    let chatEntity = ChatEntity(context: viewContext)
                    chatEntity.id = oldChat.id
                    chatEntity.newChat = oldChat.newChat
                    chatEntity.temperature = oldChat.temperature ?? 0.0
                    chatEntity.top_p = oldChat.top_p ?? 0.0
                    chatEntity.behavior = oldChat.behavior
                    chatEntity.newMessage = oldChat.newMessage ?? ""
                    chatEntity.createdDate = Date()
                    chatEntity.updatedDate = Date()
                    chatEntity.requestMessages = oldChat.requestMessages
                    chatEntity.gptModel = oldChat.gptModel ?? AppConstants.defaultModel(for: oldChat.apiServiceType)
                    chatEntity.systemMessage = oldChat.systemMessage ?? AppConstants.chatGptSystemMessage
                    chatEntity.name = oldChat.name ?? ""

                    if let apiServiceName = oldChat.apiServiceName,
                        let apiServiceType = oldChat.apiServiceType
                    {
                        let apiServiceFetch = NSFetchRequest<APIServiceEntity>(entityName: "APIServiceEntity")
                        apiServiceFetch.predicate = NSPredicate(
                            format: "name == %@ AND type == %@",
                            apiServiceName,
                            apiServiceType
                        )
                        if let existingService = try viewContext.fetch(apiServiceFetch).first {
                            chatEntity.apiService = existingService
                        }
                        else {
                            chatEntity.apiService = defaultApiService
                        }
                    }
                    else {
                        chatEntity.apiService = defaultApiService
                    }

                    if let personaName = oldChat.personaName {
                        let personaFetch = NSFetchRequest<PersonaEntity>(entityName: "PersonaEntity")
                        personaFetch.predicate = NSPredicate(format: "name == %@", personaName)
                        if let existingPersona = try viewContext.fetch(personaFetch).first {
                            chatEntity.persona = existingPersona
                        }
                    }

                    var nextSequence: Int64 = 0

                    for oldMessage in oldChat.messages {
                        nextSequence += 1
                        let messageEntity = MessageEntity(context: viewContext)
                        let legacyId = Int64(oldMessage.id)
                        messageEntity.id = legacyId
                        messageEntity.sequence = nextSequence
                        messageEntity.name = oldMessage.name
                        messageEntity.body = oldMessage.body
                        messageEntity.timestamp = oldMessage.timestamp
                        messageEntity.own = oldMessage.own
                        messageEntity.waitingForResponse = oldMessage.waitingForResponse ?? false
                        messageEntity.chat = chatEntity

                        chatEntity.applySequenceIfNeeded(to: messageEntity)
                        chatEntity.addToMessages(messageEntity)
                    }

                    chatEntity.lastSequence = max(chatEntity.lastSequence, nextSequence)
                }
            }

            DispatchQueue.main.async {
                completion(.success(chats.count))
            }

            try viewContext.save()
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

            DispatchQueue.main.async {
                do {
                    try self.viewContext.save()
                } catch {
                    print("Error saving context after deleting all chats: \(error)")
                    self.viewContext.rollback()
                }
            }
        } catch {
            print("Error deleting all chats: \(error)")
        }
    }

    func deleteAllPersonas() {
        let fetchRequest = PersonaEntity.fetchRequest()

        do {
            let personaEntities = try self.viewContext.fetch(fetchRequest)

            for persona in personaEntities {
                self.viewContext.delete(persona)
            }

            try self.viewContext.save()
        }
        catch {
            print("Error deleting all assistants: \(error)")
        }
    }

    func deleteAllAPIServices() {
        let fetchRequest = APIServiceEntity.fetchRequest()

        do {
            let apiServiceEntities = try self.viewContext.fetch(fetchRequest)

            for apiService in apiServiceEntities {
                let tokenIdentifier = apiService.tokenIdentifier
                try TokenManager.deleteToken(for: tokenIdentifier ?? "")
                self.viewContext.delete(apiService)
            }

            try self.viewContext.save()
        }
        catch {
            print("Error deleting all api services: \(error)")
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
