//
//  ChatEntityTests.swift
//  macaiTests
//
//  Created by Renat Notfullin on 07.07.2026.
//

import CoreData
import XCTest

@testable import macai

final class ChatEntityTests: XCTestCase {

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

    private func makeChat() -> ChatEntity {
        let chat = ChatEntity(context: context)
        chat.id = UUID()
        chat.createdDate = Date()
        chat.updatedDate = Date()
        chat.systemMessage = "Test system message"
        chat.gptModel = "test-model"
        chat.name = "Test Chat"
        chat.lastSequence = 0
        return chat
    }

    private func makeMessage(body: String, own: Bool, timestamp: Date = Date()) -> MessageEntity {
        let message = MessageEntity(context: context)
        message.body = body
        message.own = own
        message.timestamp = timestamp
        return message
    }

    // MARK: - Sequencing

    func testAddToMessagesAssignsIncreasingSequences() {
        let chat = makeChat()

        let first = makeMessage(body: "one", own: true)
        let second = makeMessage(body: "two", own: false)
        let third = makeMessage(body: "three", own: true)

        chat.addToMessages(first)
        chat.addToMessages(second)
        chat.addToMessages(third)

        XCTAssertEqual(first.sequence, 1)
        XCTAssertEqual(second.sequence, 2)
        XCTAssertEqual(third.sequence, 3)
        XCTAssertEqual(chat.lastSequence, 3)
    }

    func testNextSequenceContinuesAfterExistingMax() throws {
        let chat = makeChat()

        let message = makeMessage(body: "existing", own: true)
        message.sequence = 41
        message.chat = chat
        try context.save()

        // Simulate a stale lastSequence (e.g. after iCloud sync merged messages)
        chat.lastSequence = 0

        XCTAssertEqual(chat.nextSequence(), 42)
    }

    func testMessagesArraySortedBySequence() throws {
        let chat = makeChat()
        let now = Date()

        // Insert out of chronological order with explicit sequences
        let late = makeMessage(body: "late", own: false, timestamp: now.addingTimeInterval(-100))
        late.sequence = 2
        late.chat = chat
        let early = makeMessage(body: "early", own: true, timestamp: now)
        early.sequence = 1
        early.chat = chat
        try context.save()

        let bodies = chat.messagesArray.map { $0.body }
        XCTAssertEqual(bodies, ["early", "late"])
    }

    func testLastMessageReturnsHighestSequence() throws {
        let chat = makeChat()

        for index in 1...5 {
            let message = makeMessage(body: "message \(index)", own: index % 2 == 0)
            chat.addToMessages(message)
        }
        try context.save()

        XCTAssertEqual(chat.lastMessage?.body, "message 5")
        XCTAssertEqual(chat.messagesCount, 5)
    }

    func testClearMessagesRemovesAllAndResetsSequence() throws {
        let chat = makeChat()

        chat.addToMessages(makeMessage(body: "one", own: true))
        chat.addToMessages(makeMessage(body: "two", own: false))
        try context.save()

        chat.clearMessages()
        try context.save()

        XCTAssertEqual(chat.messagesCount, 0)
        XCTAssertEqual(chat.lastSequence, 0)
        XCTAssertTrue(chat.newChat)
    }

    func testApplySequenceIfNeededKeepsExistingSequence() {
        let chat = makeChat()

        let message = makeMessage(body: "presequenced", own: true)
        message.sequence = 7
        chat.applySequenceIfNeeded(to: message)

        XCTAssertEqual(message.sequence, 7)
        XCTAssertEqual(chat.lastSequence, 7)

        let next = makeMessage(body: "next", own: false)
        chat.applySequenceIfNeeded(to: next)
        XCTAssertEqual(next.sequence, 8)
    }

    // MARK: - Per-chat settings inheritance

    private func makePersona(temperature: Float = 0.7, contextSize: Int16 = 30, model: String = "persona-model") -> PersonaEntity {
        let persona = PersonaEntity(context: context)
        persona.id = UUID()
        persona.name = "Test Assistant"
        persona.temperature = temperature
        persona.contextSize = contextSize
        persona.model = model
        return persona
    }

    private func makeService(name: String = "Service") -> APIServiceEntity {
        let service = APIServiceEntity(context: context)
        service.id = UUID()
        service.name = name
        service.type = "chatgpt"
        return service
    }

    func testEffectiveTemperatureInheritsFromPersonaUntilOverridden() {
        let chat = makeChat()
        chat.persona = makePersona(temperature: 0.7)

        // Legacy chats carry stale temperature values (old versions wrote 0/1
        // unconditionally); without the flag they must still inherit.
        chat.temperature = 1.0
        XCTAssertEqual(chat.effectiveTemperature, 0.7)

        chat.temperature = 0.2
        chat.temperatureOverridden = true
        XCTAssertEqual(chat.effectiveTemperature, 0.2)
    }

    func testEffectiveContextSizeInheritsFromPersonaUntilOverridden() {
        let chat = makeChat()
        chat.persona = makePersona(contextSize: 30)

        XCTAssertEqual(chat.effectiveContextSize, 30)

        chat.contextSize = 50
        XCTAssertEqual(chat.effectiveContextSize, 50)
    }

    func testEffectiveModelPrefersChatOverPersona() {
        let chat = makeChat()
        chat.persona = makePersona(model: "persona-model")

        chat.gptModel = "chat-model"
        XCTAssertEqual(chat.effectiveModel, "chat-model")

        chat.gptModel = ""
        XCTAssertEqual(chat.effectiveModel, "persona-model")
    }

    func testEffectiveApiServicePrefersChatOverPersona() {
        let chat = makeChat()
        let persona = makePersona()
        let personaService = makeService(name: "Persona Service")
        let chatService = makeService(name: "Chat Service")
        persona.apiService = personaService
        chat.persona = persona

        chat.apiService = chatService
        XCTAssertEqual(chat.effectiveApiService?.objectID, chatService.objectID)

        chat.apiService = nil
        XCTAssertEqual(chat.effectiveApiService?.objectID, personaService.objectID)
    }

    func testImageGenerationModeOverridesPersona() {
        let chat = makeChat()
        let persona = makePersona()
        persona.imageGenerationEnabled = true
        chat.persona = persona

        XCTAssertTrue(chat.imageGenerationEnabled)  // inherit

        chat.imageGenerationMode = 2
        XCTAssertFalse(chat.imageGenerationEnabled)  // explicit off

        chat.imageGenerationMode = 1
        XCTAssertTrue(chat.imageGenerationEnabled)  // explicit on
    }

    func testResetToAssistantDefaultsClearsOverridesAndResnapshots() {
        let chat = makeChat()
        let persona = makePersona(temperature: 0.7, contextSize: 30, model: "persona-model")
        let personaService = makeService(name: "Persona Service")
        persona.apiService = personaService
        persona.systemMessage = "Persona system message"
        chat.persona = persona

        chat.temperature = 0.1
        chat.temperatureOverridden = true
        chat.contextSize = 90
        chat.imageGenerationMode = 2
        chat.gptModel = "chat-model"
        chat.apiService = makeService(name: "Chat Service")

        chat.resetToAssistantDefaults()

        XCTAssertFalse(chat.temperatureOverridden)
        XCTAssertEqual(chat.effectiveTemperature, 0.7)
        XCTAssertEqual(chat.effectiveContextSize, 30)
        XCTAssertEqual(chat.imageGenerationMode, 0)
        XCTAssertEqual(chat.gptModel, "persona-model")
        XCTAssertEqual(chat.apiService?.objectID, personaService.objectID)
        XCTAssertEqual(chat.systemMessage, "Persona system message")
    }
}
