//
//  DatabasePatcherTests.swift
//  macaiTests
//
//  Created by Renat Notfullin on 07.07.2026.
//

import CoreData
import XCTest

@testable import macai

/// Tests for the assistant-settings migration that runs when users update
/// from the service-centric model (v3) to the persona-centric model (v4).
final class DatabasePatcherTests: XCTestCase {

    private var container: NSPersistentContainer!
    private var context: NSManagedObjectContext!

    override func setUpWithError() throws {
        try super.setUpWithError()

        ValueTransformer.setValueTransformer(
            RequestMessagesTransformer(),
            forName: RequestMessagesTransformer.name
        )

        guard let model = NSManagedObjectModel.mergedModel(from: [Bundle(for: ChatEntity.self)]) else {
            throw XCTSkip("Core Data model not found in bundle")
        }

        container = NSPersistentContainer(name: "macaiDataModel", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if let loadError {
            throw loadError
        }
        context = container.viewContext
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
        try super.tearDownWithError()
    }

    // MARK: - Fixtures (simulate pre-migration, v3-shaped data)

    private func makeService(name: String, model: String = "gpt-4o") -> APIServiceEntity {
        let service = APIServiceEntity(context: context)
        service.id = UUID()
        service.name = name
        service.type = "chatgpt"
        service.url = URL(string: "https://api.openai.com/v1/chat/completions")
        service.model = model
        service.contextSize = 20
        service.generateChatNames = true
        service.useStreamResponse = true
        service.addedDate = Date()
        return service
    }

    private func makePersona(name: String) -> PersonaEntity {
        let persona = PersonaEntity(context: context)
        persona.id = UUID()
        persona.name = name
        persona.systemMessage = "You are \(name)."
        persona.temperature = 0.7
        persona.addedDate = Date()
        // v3 personas had no apiService, model, or per-persona settings
        persona.apiService = nil
        persona.model = nil
        persona.contextSize = 0
        return persona
    }

    private func makeChat(persona: PersonaEntity?, service: APIServiceEntity?) -> ChatEntity {
        let chat = ChatEntity(context: context)
        chat.id = UUID()
        chat.createdDate = Date()
        chat.updatedDate = Date()
        chat.systemMessage = "Chat system message"
        chat.gptModel = "gpt-4o"
        chat.name = "Test Chat"
        chat.lastSequence = 0
        chat.persona = persona
        chat.apiService = service
        return chat
    }

    private func addMessage(_ body: String, to chat: ChatEntity, own: Bool) {
        let message = MessageEntity(context: context)
        message.body = body
        message.own = own
        message.timestamp = Date()
        chat.addToMessages(message)
    }

    // MARK: - Tests

    func testMigrationOnEmptyStoreCompletes() {
        // A no-op migration must report success so it is not re-run on every launch.
        XCTAssertTrue(DatabasePatcher.migrateAssistantSettingsToPersonas(context: context))
    }

    func testMigrationBindsPersonaToSingleCandidateService() throws {
        let service = makeService(name: "OpenAI")
        let persona = makePersona(name: "Writer")
        let chat = makeChat(persona: persona, service: service)
        addMessage("Hello", to: chat, own: true)
        try context.save()

        XCTAssertTrue(DatabasePatcher.migrateAssistantSettingsToPersonas(context: context))

        XCTAssertEqual(persona.apiService?.objectID, service.objectID)
        XCTAssertEqual(persona.model, "gpt-4o")
        XCTAssertEqual(persona.contextSize, 20)
        XCTAssertEqual(chat.persona?.objectID, persona.objectID)
        XCTAssertEqual(chat.apiService?.objectID, service.objectID)
    }

    func testMigrationClonesPersonaUsedWithMultipleServicesAndPreservesChatServices() throws {
        let serviceA = makeService(name: "OpenAI")
        let serviceB = makeService(name: "Claude")
        let persona = makePersona(name: "Shared")
        serviceA.defaultPersona = persona
        serviceB.defaultPersona = persona
        let chatA = makeChat(persona: persona, service: serviceA)
        let chatB = makeChat(persona: persona, service: serviceB)
        try context.save()

        XCTAssertTrue(DatabasePatcher.migrateAssistantSettingsToPersonas(context: context))

        let migratedPersonaA = try XCTUnwrap(chatA.persona)
        let migratedPersonaB = try XCTUnwrap(chatB.persona)
        XCTAssertNotEqual(migratedPersonaA.objectID, migratedPersonaB.objectID)
        XCTAssertEqual(migratedPersonaA.apiService?.objectID, serviceA.objectID)
        XCTAssertEqual(migratedPersonaB.apiService?.objectID, serviceB.objectID)
        XCTAssertEqual(serviceA.defaultPersona?.objectID, migratedPersonaA.objectID)
        XCTAssertEqual(serviceB.defaultPersona?.objectID, migratedPersonaB.objectID)
        XCTAssertEqual(chatA.apiService?.objectID, serviceA.objectID)
        XCTAssertEqual(chatB.apiService?.objectID, serviceB.objectID)
        XCTAssertFalse(chatA.apiServiceOverridden)
        XCTAssertFalse(chatB.apiServiceOverridden)

        let personaCount = try context.count(for: PersonaEntity.fetchRequest())
        XCTAssertTrue(DatabasePatcher.migrateAssistantSettingsToPersonas(context: context))
        XCTAssertEqual(try context.count(for: PersonaEntity.fetchRequest()), personaCount)
        XCTAssertEqual(chatA.apiService?.objectID, serviceA.objectID)
        XCTAssertEqual(chatB.apiService?.objectID, serviceB.objectID)
    }

    func testMigrationCreatesDefaultPersonaForServiceWithoutOne() throws {
        let service = makeService(name: "Mistral")
        try context.save()

        XCTAssertTrue(DatabasePatcher.migrateAssistantSettingsToPersonas(context: context))

        let defaultPersona = try XCTUnwrap(service.defaultPersona)
        XCTAssertEqual(defaultPersona.apiService?.objectID, service.objectID)
        XCTAssertEqual(defaultPersona.model, "gpt-4o")
    }

    func testMigrationAssignsDefaultPersonaToChatWithoutPersona() throws {
        let service = makeService(name: "OpenAI")
        let chat = makeChat(persona: nil, service: service)
        try context.save()

        XCTAssertTrue(DatabasePatcher.migrateAssistantSettingsToPersonas(context: context))

        XCTAssertNotNil(chat.persona)
        XCTAssertEqual(chat.persona?.objectID, service.defaultPersona?.objectID)
    }

    func testMigrationRestoresServiceForChatWithBoundPersonaOnly() throws {
        let service = makeService(name: "OpenAI")
        let persona = makePersona(name: "Coder")
        persona.apiService = service
        let chat = makeChat(persona: persona, service: nil)
        try context.save()

        XCTAssertTrue(DatabasePatcher.migrateAssistantSettingsToPersonas(context: context))

        XCTAssertEqual(chat.apiService?.objectID, service.objectID)
    }

    func testMigrationPreservesChatContent() throws {
        let service = makeService(name: "OpenAI")
        let persona = makePersona(name: "Writer")
        let chat = makeChat(persona: persona, service: service)
        addMessage("Question", to: chat, own: true)
        addMessage("Answer", to: chat, own: false)
        try context.save()

        XCTAssertTrue(DatabasePatcher.migrateAssistantSettingsToPersonas(context: context))

        XCTAssertEqual(chat.name, "Test Chat")
        XCTAssertEqual(chat.systemMessage, "Chat system message")
        XCTAssertEqual(chat.messagesArray.count, 2)
        XCTAssertEqual(chat.messagesArray.map(\.body), ["Question", "Answer"])
    }

    func testMigrationMarksLegacyPerChatSettingsAsOverrides() throws {
        let service = makeService(name: "OpenAI")
        let persona = makePersona(name: "Writer")
        persona.apiService = service
        persona.model = "assistant-model"
        persona.systemMessage = "Assistant system message"
        let chat = makeChat(persona: persona, service: service)
        chat.gptModel = "chat-model"
        chat.systemMessage = "Chat-specific system message"
        try context.save()

        XCTAssertTrue(DatabasePatcher.migrateAssistantSettingsToPersonas(context: context))

        XCTAssertFalse(chat.apiServiceOverridden)
        XCTAssertTrue(chat.modelOverridden)
        XCTAssertTrue(chat.systemMessageOverridden)
        XCTAssertEqual(chat.effectiveModel, "chat-model")
        XCTAssertEqual(chat.effectiveSystemMessage, "Chat-specific system message")
    }

    func testMigrationIsIdempotent() throws {
        let service = makeService(name: "OpenAI")
        let persona = makePersona(name: "Writer")
        let chat = makeChat(persona: persona, service: service)
        try context.save()

        XCTAssertTrue(DatabasePatcher.migrateAssistantSettingsToPersonas(context: context))
        let personaCountAfterFirstRun = try context.count(for: PersonaEntity.fetchRequest())

        XCTAssertTrue(DatabasePatcher.migrateAssistantSettingsToPersonas(context: context))
        let personaCountAfterSecondRun = try context.count(for: PersonaEntity.fetchRequest())

        XCTAssertEqual(personaCountAfterFirstRun, personaCountAfterSecondRun)
        XCTAssertEqual(persona.apiService?.objectID, service.objectID)
        XCTAssertEqual(chat.persona?.objectID, persona.objectID)
    }
}
