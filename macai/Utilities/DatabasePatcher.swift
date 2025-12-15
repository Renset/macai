//
//  DatabasePatcher.swift
//  macai
//
//  Created by Renat Notfullin on 08.09.2024.
//

import CoreData
import Foundation

class DatabasePatcher {
    static func applyPatches(context: NSManagedObjectContext) {
        addDefaultPersonasIfNeeded(context: context)
        patchMissingIDs(context: context)
        patchPersonaOrdering(context: context)
        backfillMessageSequencesIfNeeded(context: context)
        patchImageUploadsForAPIServices(context: context)
        patchImageGenerationForAPIServices(context: context)
        //resetMigrationState()
        patchGeminiLegacyEndpoint(context: context)
        patchChatGPTLegacyEndpoint(context: context)
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

    static func patchImageUploadsForAPIServices(context: NSManagedObjectContext) {
        let fetchRequest = NSFetchRequest<APIServiceEntity>(entityName: "APIServiceEntity")
        
        do {
            let apiServices = try context.fetch(fetchRequest)
            var needsSave = false
            
            for service in apiServices {
                if let type = service.type, 
                   let config = AppConstants.defaultApiConfigurations[type], 
                   config.imageUploadsSupported && !service.imageUploadsAllowed {
                    service.imageUploadsAllowed = true
                    needsSave = true
                    print("Enabled image uploads for API service: \(service.name ?? "Unnamed")")
                }
            }
            
            if needsSave {
                try context.save()
                print("Successfully patched image uploads for API services")
            }
        }
        catch {
            print("Error patching image uploads for API services: \(error)")
        }
    }

    static func patchImageGenerationForAPIServices(context: NSManagedObjectContext) {
        let fetchRequest = NSFetchRequest<APIServiceEntity>(entityName: "APIServiceEntity")

        do {
            let apiServices = try context.fetch(fetchRequest)
            var needsSave = false

            for service in apiServices {
                guard let type = service.type,
                      let config = AppConstants.defaultApiConfigurations[type] else {
                    continue
                }

                let currentModel = service.model ?? config.defaultModel
                if config.imageGenerationSupported,
                   config.autoEnableImageGenerationModels.contains(currentModel),
                   service.imageGenerationSupported == false
                {
                    service.imageGenerationSupported = true
                    needsSave = true
                    print("Enabled image generation for API service: \(service.name ?? "Unnamed")")
                }
            }

            if needsSave {
                try context.save()
                print("Successfully patched image generation for API services")
            }
        }
        catch {
            print("Error patching image generation for API services: \(error)")
        }
    }

    static func patchGeminiLegacyEndpoint(context: NSManagedObjectContext) {
        deliverPendingGeminiMigrationNotificationIfNeeded()

        let defaults = UserDefaults.standard

        if defaults.bool(forKey: AppConstants.geminiURLMigrationCompletedKey) {
            return
        }

        let fetchRequest = NSFetchRequest<APIServiceEntity>(entityName: "APIServiceEntity")
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "(type CONTAINS[cd] %@)", "gemini"),
            NSPredicate(format: "(url CONTAINS[cd] %@)", "/chat/completions")
        ])

        let legacyServices: [APIServiceEntity]

        do {
            legacyServices = try context.fetch(fetchRequest)
        }
        catch {
            print("Error fetching Gemini services for migration: \(error)")
            return
        }

        guard !legacyServices.isEmpty else {
            defaults.set(true, forKey: AppConstants.geminiURLMigrationCompletedKey)
            return
        }

        guard let newURL = URL(string: AppConstants.geminiCurrentAPIURL) else {
            print("Invalid Gemini models URL: \(AppConstants.geminiCurrentAPIURL)")
            return
        }

        var updatedCount = 0

        context.performAndWait {
            for service in legacyServices {
                if service.url != newURL {
                    service.url = newURL
                    updatedCount += 1
                }
            }

            if updatedCount > 0 {
                context.saveWithRetry(attempts: 1)
            }
        }

        defaults.set(true, forKey: AppConstants.geminiURLMigrationCompletedKey)
        defaults.removeObject(forKey: AppConstants.geminiURLMigrationSkippedKey)

        guard updatedCount > 0 else { return }

        let message = updatedCount == 1
            ? "Updated 1 Gemini API service to the native API endpoint (vision and image generation are now supported)"
            : "Updated \(updatedCount) Gemini API services to the native API endpoint (vision and image generation are now supported)"

        scheduleGeminiNotification(message)
    }

    static func patchChatGPTLegacyEndpoint(context: NSManagedObjectContext) {
        deliverPendingChatCompletionsMigrationNotificationIfNeeded()

        let defaults = UserDefaults.standard

        if defaults.bool(forKey: AppConstants.chatCompletionsMigrationCompletedKey) {
            return
        }

        let fetchRequest = NSFetchRequest<APIServiceEntity>(entityName: "APIServiceEntity")
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "(type CONTAINS[cd] %@)", "chatgpt"),
            NSPredicate(format: "(url CONTAINS[cd] %@)", "/chat/completions")
        ])

        let legacyServices: [APIServiceEntity]

        do {
            legacyServices = try context.fetch(fetchRequest)
        }
        catch {
            print("Error fetching ChatGPT services for migration: \(error)")
            return
        }

        guard !legacyServices.isEmpty else {
        defaults.set(true, forKey: AppConstants.chatCompletionsMigrationCompletedKey)
        defaults.removeObject(forKey: AppConstants.chatCompletionsMigrationPendingNotificationKey)
        return
    }

        guard let targetURL = URL(string: AppConstants.apiUrlOpenAIResponses) else {
            print("Invalid OpenAI Responses URL: \(AppConstants.apiUrlOpenAIResponses)")
            return
        }

        let defaultServiceName = AppConstants.defaultApiConfigurations[AppConstants.defaultApiType]?.name
            ?? "OpenAI"

        var updatedCount = 0

        context.performAndWait {
            for service in legacyServices {
                guard let existingURL = service.url else { continue }
                guard let host = existingURL.host?.lowercased(), host == "api.openai.com" else { continue }
                guard existingURL.path.contains("/chat/completions") else { continue }

                var serviceUpdated = false

                if service.url != targetURL {
                    service.url = targetURL
                    serviceUpdated = true
                }

                if service.type?.caseInsensitiveCompare(AppConstants.defaultApiType) != .orderedSame {
                    service.type = AppConstants.defaultApiType
                    serviceUpdated = true
                }

                if let currentName = service.name,
                   ["Chat GPT", "ChatGPT", "OpenAI - Completions"]
                   .contains(where: { currentName.caseInsensitiveCompare($0) == .orderedSame }) {
                    if currentName != defaultServiceName {
                        service.name = defaultServiceName
                        serviceUpdated = true
                    }
                }

                if serviceUpdated {
                    updatedCount += 1
                }
            }

            if updatedCount > 0 {
                context.saveWithRetry(attempts: 1)
            }
        }

        defaults.set(true, forKey: AppConstants.chatCompletionsMigrationCompletedKey)

        guard updatedCount > 0 else {
            defaults.removeObject(forKey: AppConstants.chatCompletionsMigrationPendingNotificationKey)
            return
        }

        let message = updatedCount == 1
            ? "Updated 1 OpenAI Chat Completions API service to the Responses API (latest features enabled)."
            : "Updated \(updatedCount) OpenAI Chat Completions API services to the Responses API (latest features enabled)."

        scheduleChatCompletionsNotification(message)
    }

    static func resetMigrationState() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: AppConstants.geminiURLMigrationCompletedKey)
        defaults.removeObject(forKey: AppConstants.geminiURLMigrationSkippedKey)
        defaults.removeObject(forKey: AppConstants.geminiMigrationPendingNotificationKey)
        defaults.removeObject(forKey: AppConstants.chatCompletionsMigrationCompletedKey)
        defaults.removeObject(forKey: AppConstants.chatCompletionsMigrationPendingNotificationKey)
    }

    static func deliverPendingGeminiMigrationNotificationIfNeeded() {
        let defaults = UserDefaults.standard
        guard let pendingMessage = defaults.string(forKey: AppConstants.geminiMigrationPendingNotificationKey) else {
            return
        }
        scheduleGeminiNotification(pendingMessage)
    }

    static func deliverPendingChatCompletionsMigrationNotificationIfNeeded() {
        let defaults = UserDefaults.standard
        guard let pendingMessage = defaults.string(forKey: AppConstants.chatCompletionsMigrationPendingNotificationKey)
        else {
            return
        }
        scheduleChatCompletionsNotification(pendingMessage)
    }

    private static func scheduleGeminiNotification(_ message: String) {
        let defaults = UserDefaults.standard
        defaults.set(message, forKey: AppConstants.geminiMigrationPendingNotificationKey)

        NotificationPresenter.shared.scheduleNotification(
            identifier: "macai.gemini.migration",
            title: "Gemini Endpoint Updated",
            body: message
        ) { success in
            if success {
                defaults.removeObject(forKey: AppConstants.geminiMigrationPendingNotificationKey)
            }
        }
    }

    private static func scheduleChatCompletionsNotification(_ message: String) {
        let defaults = UserDefaults.standard
        defaults.set(message, forKey: AppConstants.chatCompletionsMigrationPendingNotificationKey)

        NotificationPresenter.shared.scheduleNotification(
            identifier: "macai.openai.migration",
            title: "OpenAI Endpoint Updated",
            body: message
        ) { success in
            if success {
                defaults.removeObject(forKey: AppConstants.chatCompletionsMigrationPendingNotificationKey)
            }
        }
    }
    
    static func migrateExistingConfiguration(context: NSManagedObjectContext) {
        let apiServiceManager = APIServiceManager(viewContext: context)
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "APIServiceMigrationCompleted") {
            return
        }

        let apiUrl = defaults.string(forKey: "apiUrl") ?? AppConstants.apiUrlOpenAIResponses
        let gptModel = defaults.string(forKey: "gptModel") ?? AppConstants.defaultPrimaryModel
        let useStream = defaults.bool(forKey: "useStream")
        let useChatGptForNames = defaults.bool(forKey: "useChatGptForNames")

        var type = AppConstants.defaultApiType
        var name = AppConstants.defaultApiConfigurations[type]?.name ?? "OpenAI"
        var chatContext = defaults.double(forKey: "chatContext")

        if apiUrl.contains(":11434/api/chat") {
            type = "ollama"
            name = "Ollama"
        }
        else if apiUrl.contains("/chat/completions") {
            type = "chatgpt"
            name = AppConstants.defaultApiConfigurations[type]?.name ?? "Generic Completions API"
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

        if let token = defaults.string(forKey: "gptToken"),
           token.isEmpty == false,
           let serviceId = apiService.id {
            print("Token found: \(token)")
            try? TokenManager.setToken(token, for: serviceId.uuidString)
            defaults.set("", forKey: "gptToken")
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
                chat.gptModel = apiService.model ?? AppConstants.defaultModel(for: apiService.type)
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

    // MARK: - ID backfill for non-optional UUIDs
    static func patchMissingIDs(context: NSManagedObjectContext) {
        let defaults = UserDefaults.standard
        let key = "EntityIDBackfillCompleted"

        if defaults.bool(forKey: key) {
            return
        }

        var saveSucceeded = false

        context.performAndWait {
            let zeroUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
            var didChange = false

            func refresh<T: NSManagedObject>(_ request: NSFetchRequest<T>, _ updater: (T) -> Void) {
                if let results = try? context.fetch(request) {
                    results.forEach(updater)
                }
            }

            refresh(NSFetchRequest<APIServiceEntity>(entityName: "APIServiceEntity")) { service in
                let currentID = service.value(forKey: "id") as? UUID
                if currentID == nil || currentID == zeroUUID {
                    service.id = UUID()
                    didChange = true
                }

                if service.tokenIdentifier == nil || service.tokenIdentifier?.isEmpty == true {
                    service.tokenIdentifier = UUID().uuidString
                    didChange = true
                }
            }

            refresh(NSFetchRequest<ChatEntity>(entityName: "ChatEntity")) { chat in
                let currentID = (chat.value(forKey: "id") as? UUID) ?? chat.id
                if currentID == zeroUUID {
                    chat.id = UUID()
                    didChange = true
                }
            }

            refresh(NSFetchRequest<PersonaEntity>(entityName: "PersonaEntity")) { persona in
                let currentID = persona.value(forKey: "id") as? UUID
                if currentID == nil || currentID == zeroUUID {
                    persona.id = UUID()
                    didChange = true
                }
            }

            refresh(NSFetchRequest<ImageEntity>(entityName: "ImageEntity")) { image in
                let currentID = image.value(forKey: "id") as? UUID
                if currentID == nil || currentID == zeroUUID {
                    image.id = UUID()
                    didChange = true
                }
            }

            if didChange {
                do {
                    try context.save()
                    saveSucceeded = true
                }
                catch {
                    print("Error saving ID backfill: \(error)")
                    context.rollback()
                }
            } else {
                saveSucceeded = true
            }
        }

        if saveSucceeded {
            defaults.set(true, forKey: key)
        }
    }

    // MARK: - Message sequencing migration
    static func backfillMessageSequencesIfNeeded(context: NSManagedObjectContext) {
        let defaults = UserDefaults.standard
        let migrationKey = "MessageSequenceBackfillCompleted"

        if defaults.bool(forKey: migrationKey) {
            return
        }

        context.performAndWait {
            let model = context.persistentStoreCoordinator?.managedObjectModel
            let messageEntityDesc = model?.entitiesByName["MessageEntity"]
            let chatEntityDesc = model?.entitiesByName["ChatEntity"]
            let hasSequence = messageEntityDesc?.attributesByName["sequence"] != nil
            let hasLastSequence = chatEntityDesc?.attributesByName["lastSequence"] != nil

            // If the loaded model does not yet contain the new fields, skip to avoid KVC crashes.
            guard hasSequence, hasLastSequence else {
                print("Skipping sequence backfill: model missing sequence/lastSequence attributes")
                defaults.set(true, forKey: migrationKey)
                return
            }

            let chatRequest = NSFetchRequest<ChatEntity>(entityName: "ChatEntity")
            chatRequest.sortDescriptors = [NSSortDescriptor(keyPath: \ChatEntity.createdDate, ascending: true)]

            do {
                let chats = try context.fetch(chatRequest)
                var didChange = false

                for chat in chats {
                    let modelHasSequence = messageEntityDesc?.attributesByName["sequence"] != nil
                    let messageRequest = NSFetchRequest<MessageEntity>(entityName: "MessageEntity")
                    messageRequest.predicate = NSPredicate(format: "chat == %@", chat)
                    messageRequest.sortDescriptors = [
                        NSSortDescriptor(key: "timestamp", ascending: true),
                    ]

                    let fetchedMessages = try context.fetch(messageRequest)

                    let messages = fetchedMessages.sorted { lhs, rhs in
                        let lhsDate = lhs.timestamp
                        let rhsDate = rhs.timestamp
                        if lhsDate == rhsDate {
                            return lhs.objectID.uriRepresentation().absoluteString
                                < rhs.objectID.uriRepresentation().absoluteString
                        }
                        return lhsDate < rhsDate
                    }

                    var sequence: Int64 = 0
                    for message in messages {
                        sequence += 1

                        if modelHasSequence {
                            let currentSequence = (message.value(forKey: "sequence") as? Int64) ?? 0
                            if currentSequence != sequence {
                                message.setValue(sequence, forKey: "sequence")
                                didChange = true
                            }
                        }

                        if let currentId = message.value(forKey: "id") as? Int64, currentId == 0 {
                            message.setValue(sequence, forKey: "id")
                            didChange = true
                        }
                    }

                    if let lastAttr = chatEntityDesc?.attributesByName["lastSequence"],
                       lastAttr.attributeType == .integer64AttributeType
                    {
                        let currentLast = (chat.value(forKey: "lastSequence") as? Int64) ?? 0
                        if currentLast != sequence {
                            chat.setValue(sequence, forKey: "lastSequence")
                            didChange = true
                        }
                    }
                }

                if didChange {
                    context.saveWithRetry(attempts: 1)
                }

                defaults.set(true, forKey: migrationKey)
            }
            catch {
                print("Error backfilling message sequences: \(error)")
            }
        }
    }
}
