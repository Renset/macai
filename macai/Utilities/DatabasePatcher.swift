//
//  DatabasePatcher.swift
//  macai
//
//  Created by Renat Notfullin on 08.09.2024.
//

import CoreData
import Foundation
import SwiftUI

class DatabasePatcher {
    static func applyPatches(context: NSManagedObjectContext) {
        addDefaultPersonasIfNeeded(context: context)
        patchPersonaOrdering(context: context)
        //resetPersonaOrdering(context: context)
    }

    static func addDefaultPersonasIfNeeded(context: NSManagedObjectContext, force: Bool = false) {
        let defaults = UserDefaults.standard
        if force || !defaults.bool(forKey: AppConstants.defaultPersonasFlag) {
            for (index, persona) in AppConstants.PersonaPresets.allPersonas.enumerated() {
                let newPersona = PersonaEntity(context: context)
                newPersona.name = persona.name
                newPersona.color = persona.color
                newPersona.systemMessage = persona.message
                newPersona.addedDate = Date()
                newPersona.temperature = persona.temperature
                newPersona.id = UUID()
                newPersona.order = Int16(index)
            }

            do {
                try context.save()
                defaults.set(true, forKey: AppConstants.defaultPersonasFlag)
                print("Default assistants added successfully")
            }
            catch {
                print("Failed to add default assistants: \(error)")
            }
        }
    }

    static func patchPersonaOrdering(context: NSManagedObjectContext) {
        let fetchRequest = NSFetchRequest<PersonaEntity>(entityName: "PersonaEntity")
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \PersonaEntity.addedDate, ascending: true)]

        do {
            let personas = try context.fetch(fetchRequest)
            var needsSave = false

            for (index, persona) in personas.enumerated() {
                if persona.order == 0 && index != 0 {
                    persona.order = Int16(index)
                    needsSave = true
                }
            }

            if needsSave {
                try context.save()
                print("Successfully patched persona ordering")
            }
        }
        catch {
            print("Error patching persona ordering: \(error)")
        }
    }

    static func resetPersonaOrdering(context: NSManagedObjectContext) {
        let fetchRequest = NSFetchRequest<PersonaEntity>(entityName: "PersonaEntity")

        do {
            let personas = try context.fetch(fetchRequest)
            for persona in personas {
                persona.order = 0
            }
            try context.save()
            print("Successfully reset all persona ordering")

            // Re-apply the ordering patch
            patchPersonaOrdering(context: context)
        }
        catch {
            print("Error resetting persona ordering: \(error)")
        }
    }

    static func migrateExistingConfiguration(context: NSManagedObjectContext) {
        let apiServiceManager = APIServiceManager(viewContext: context)
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "APIServiceMigrationCompleted") {
            return
        }

        let apiUrl = defaults.string(forKey: "apiUrl") ?? AppConstants.apiUrlChatCompletions
        let gptModel = defaults.string(forKey: "gptModel") ?? AppConstants.chatGptDefaultModel
        let useStream = defaults.bool(forKey: "useStream")
        let useChatGptForNames = defaults.bool(forKey: "useChatGptForNames")

        var type = "chatgpt"
        var name = "Chat GPT"
        var chatContext = defaults.double(forKey: "chatContext")

        if apiUrl.contains(":11434/api/chat") {
            type = "ollama"
            name = "Ollama"
        }

        if chatContext < 5 {
            chatContext = AppConstants.chatGptContextSize
        }

        let apiService = apiServiceManager.createAPIService(
            name: name,
            type: type,
            url: URL(string: apiUrl)!,
            model: gptModel,
            contextSize: chatContext.toInt16() ?? 15,
            useStreamResponse: useStream,
            generateChatNames: useChatGptForNames
        )

        if let token = defaults.string(forKey: "gptToken") {
            print("Token found: \(token)")
            if token != "", let apiServiceId = apiService.id {
                try? TokenManager.setToken(token, for: apiServiceId.uuidString)
                defaults.set("", forKey: "gptToken")
            }
        }

        // Set Default Assistant as the default for default API service
        let personaFetchRequest = NSFetchRequest<PersonaEntity>(entityName: "PersonaEntity")
        personaFetchRequest.predicate = NSPredicate(format: "name == %@", "Default Assistant")

        do {
            let defaultPersonas = try context.fetch(personaFetchRequest)
            if let defaultPersona = defaultPersonas.first {
                print("Found default assistant: \(defaultPersona.name ?? "")")
                apiService.defaultPersona = defaultPersona
                try context.save()
                print("Successfully set default assistant for API service")
            }
            else {
                print("Warning: Default Assistant not found")
            }
        }
        catch {
            print("Error setting default assistant: \(error)")
        }

        // Update Chats
        let fetchRequest = NSFetchRequest<ChatEntity>(entityName: "ChatEntity")
        do {
            let existingChats = try context.fetch(fetchRequest)
            print("Found \(existingChats.count) existing chats to update")

            for chat in existingChats {
                chat.apiService = apiService
                chat.gptModel = apiService.model ?? AppConstants.chatGptDefaultModel
            }

            try context.save()
            print("Successfully updated all existing chats with new API service")
        }
        catch {
            print("Error updating existing chats: \(error)")
        }

        defaults.set(apiService.objectID.uriRepresentation().absoluteString, forKey: "defaultApiService")

        // Migration completed
        defaults.set(true, forKey: "APIServiceMigrationCompleted")
    }
}
