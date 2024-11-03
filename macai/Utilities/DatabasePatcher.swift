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
    }

    static func addDefaultPersonasIfNeeded(context: NSManagedObjectContext, force: Bool = false) {
        let defaults = UserDefaults.standard
        if force || !defaults.bool(forKey: AppConstants.defaultPersonasFlag) {
            for persona in AppConstants.PersonaPresets.allPersonas {
                let newPersona = PersonaEntity(context: context)
                newPersona.name = persona.name
                newPersona.color = persona.color
                newPersona.systemMessage = persona.message
                newPersona.addedDate = Date()
                newPersona.temperature = persona.temperature
                newPersona.id = UUID()
            }

            do {
                try context.save()
                defaults.set(true, forKey: AppConstants.defaultPersonasFlag)
                print("Default personas added successfully")
            }
            catch {
                print("Failed to add default personas: \(error)")
            }
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

        // Migration completed
        defaults.set(true, forKey: "APIServiceMigrationCompleted")
    }
}
