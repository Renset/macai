//
//  ChatViewModel.swift
//  macai
//
//  Created by Renat on 29.07.2024.
//

import Combine
import Foundation
import SwiftUI
import CoreData

struct SearchOccurrence: Equatable {
    let messageID: NSManagedObjectID
    let range: NSRange
    let elementIndex: Int // Index of the MessageElement containing this occurrence
    let elementType: String // Type of element ("text", "code", "table", etc.)

    static func == (lhs: SearchOccurrence, rhs: SearchOccurrence) -> Bool {
        return lhs.messageID == rhs.messageID && 
               NSEqualRanges(lhs.range, rhs.range) &&
               lhs.elementIndex == rhs.elementIndex &&
               lhs.elementType == rhs.elementType
    }
    
    // Generate unique scroll target ID for this occurrence
    var scrollTargetID: String {
        let messageIDString = messageID.uriRepresentation().absoluteString
        return "\(messageIDString)_\(elementIndex)_\(range.location)_\(range.length)"
    }
}

class ChatViewModel: NSObject, ObservableObject, NSFetchedResultsControllerDelegate {
    // MARK: - Search State
    @Published var searchOccurrences: [SearchOccurrence] = []
    @Published var currentSearchIndex: Int? = nil
    @Published var sortedMessages: [MessageEntity] = []

    var currentSearchOccurrence: SearchOccurrence? {
        if let index = currentSearchIndex, searchOccurrences.indices.contains(index) {
            return searchOccurrences[index]
        }
        return nil
    }
    @Published var messages: NSSet?
    private let chat: ChatEntity
    private let viewContext: NSManagedObjectContext
    private var serviceChangesCancellable: AnyCancellable?
    private let fetchedResultsController: NSFetchedResultsController<MessageEntity>

    private var _messageManager: MessageManager?
    private var messageManager: MessageManager {
        get {
            if _messageManager == nil {
                _messageManager = createMessageManager()
            }
            return _messageManager!
        }
        set {
            _messageManager = newValue
        }
    }

    private var cancellables = Set<AnyCancellable>()
    private var searchDebounceTimer: Timer?
    private var isApplyingServiceChanges = false

    init(chat: ChatEntity, viewContext: NSManagedObjectContext) {
        self.chat = chat
        self.messages = chat.messages
        self.viewContext = viewContext

        let fetchRequest: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest() as! NSFetchRequest<MessageEntity>
        fetchRequest.predicate = NSPredicate(format: "chat == %@", chat)
        fetchRequest.sortDescriptors = chat.messageSortDescriptors

        self.fetchedResultsController = NSFetchedResultsController(
            fetchRequest: fetchRequest,
            managedObjectContext: viewContext,
            sectionNameKeyPath: nil,
            cacheName: nil
        )

        super.init()

        self.fetchedResultsController.delegate = self

        do {
            try fetchedResultsController.performFetch()
            self.sortedMessages = fetchedResultsController.fetchedObjects ?? []
        }
        catch {
            print("Error performing fetch: \(error)")
        }

        observeAPIServiceChanges()
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        DispatchQueue.main.async {
            self.sortedMessages = self.fetchedResultsController.fetchedObjects ?? []
            self.messages = self.chat.messages
        }
    }

    func sendMessage(
        _ message: String,
        contextSize: Int,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        self.messageManager.sendMessage(
            message,
            in: chat,
            contextSize: contextSize
        ) { [weak self] result in
            switch result {
            case .success:
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    @MainActor
    func sendMessageStream(_ message: String, contextSize: Int, completion: @escaping (Result<Void, Error>) -> Void) {
        self.messageManager.sendMessageStream(message, in: chat, contextSize: contextSize) { [weak self] result in
            switch result {
            case .success:
                self?.chat.objectWillChange.send()
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func generateChatNameIfNeeded() {
        messageManager.generateChatNameIfNeeded(chat: chat)
    }

    func reloadMessages() {
        self.sortedMessages = fetchedResultsController.fetchedObjects ?? []
        self.messages = chat.messages
    }

    // sortedMessages is now a @Published property initialized in init() and updated in reloadMessages()

    private func createMessageManager() -> MessageManager {
        guard let config = self.loadCurrentAPIConfig() else {
            fatalError("No valid API configuration found")
        }
        print(">> Creating new MessageManager with URL: \(config.apiUrl) and model: \(config.model)")
        let supportsImageGeneration = chat.apiService?.imageGenerationSupported ?? false
        return MessageManager(
            apiService: APIServiceFactory.createAPIService(
                config: config,
                imageGenerationSupported: supportsImageGeneration
            ),
            viewContext: self.viewContext
        )
    }

    func recreateMessageManager() {
        _messageManager = createMessageManager()
    }

    // MARK: - Service change observation
    private func observeAPIServiceChanges() {
        guard serviceChangesCancellable == nil else { return }

        serviceChangesCancellable = NotificationCenter.default
            .publisher(for: .NSManagedObjectContextObjectsDidChange, object: viewContext)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self = self,
                      !self.isApplyingServiceChanges,
                      let serviceObjectID = self.chat.apiService?.objectID else { return }

                let updated = notification.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject> ?? []
                let refreshed = notification.userInfo?[NSRefreshedObjectsKey] as? Set<NSManagedObject> ?? []
                let changedServices = updated.union(refreshed)

                guard changedServices.contains(where: { $0.objectID == serviceObjectID }) else { return }

                self.applyAPIServiceChanges()
            }
    }

    private func applyAPIServiceChanges() {
        guard let apiService = chat.apiService else { return }

        isApplyingServiceChanges = true
        defer { isApplyingServiceChanges = false }

        var didChange = false

        let newModel = apiService.model ?? AppConstants.defaultModel(for: apiService.type)
        if chat.gptModel != newModel {
            chat.gptModel = newModel
            didChange = true
        }

        // Ensure we keep the latest managed object instance (it may have been refreshed)
        if chat.apiService != apiService {
            chat.apiService = apiService
            didChange = true
        }

        if didChange {
            chat.objectWillChange.send()
            recreateMessageManager()
            try? viewContext.save()
        }
    }

    deinit {
        serviceChangesCancellable?.cancel()
    }

    var canSendMessage: Bool {
        return chat.apiService != nil
    }

    private func loadCurrentAPIConfig() -> APIServiceConfiguration? {
        guard let apiService = chat.apiService, let apiServiceUrl = apiService.url else {
            return nil
        }

        guard let serviceID = apiService.id else {
            print("Error extracting token: missing apiService.id")
            return nil
        }

        var apiKey = ""
        do {
            apiKey = try TokenManager.getToken(for: serviceID.uuidString) ?? ""
        }
        catch {
            print("Error extracting token: \(error) for \(serviceID.uuidString)")
        }

        return APIServiceConfig(
            name: getApiServiceName(),
            apiUrl: apiServiceUrl,
            apiKey: apiKey,
            model: chat.gptModel
        )
    }

    private func getApiServiceName() -> String {
        return chat.apiService?.type ?? AppConstants.defaultApiType
    }
    
    func regenerateChatName() {
        messageManager.generateChatNameIfNeeded(chat: chat, force: true)
    }

    // MARK: - Search Logic
    func updateSearchOccurrences(searchText: String) {
        searchDebounceTimer?.invalidate()
        
        if searchText.isEmpty {
            searchOccurrences = []
            currentSearchIndex = nil
            return
        }
        
        searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: AppConstants.searchDebounceTime, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            
            // To ensure thread safety when accessing Core Data objects on background thread,
            // we capture the necessary data on the main thread first.
            let messagesData = self.sortedMessages.map { (id: $0.objectID, body: $0.body) }
            
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.performSearch(searchText: searchText, messagesData: messagesData)
            }
        }
    }
    
    private func performSearch(searchText: String, messagesData: [(id: NSManagedObjectID, body: String)]) {
        var occurrences: [SearchOccurrence] = []
        if !searchText.isEmpty {
            let parser = MessageParser(colorScheme: .light) // Color scheme doesn't matter for parsing
            
            for message in messagesData {
                let parsedElements = parser.parseMessageFromString(input: message.body)
                
                for (elementIndex, element) in parsedElements.enumerated() {
                    if case .table(let header, let data) = element {
                        // Handle table elements specially to match HighlightedText behavior
                        // Search in header cells
                        for (columnIndex, headerCell) in header.enumerated() {
                            var searchStartIndex = headerCell.startIndex
                            
                            while let range = headerCell.range(of: searchText, options: .caseInsensitive, range: searchStartIndex..<headerCell.endIndex) {
                                
                                let nsRange = NSRange(range, in: headerCell)
                                let adjustedRange = NSRange(location: nsRange.location + columnIndex * 10000, length: nsRange.length)
                                let occurrence = SearchOccurrence(
                                    messageID: message.id,
                                    range: adjustedRange,
                                    elementIndex: elementIndex,
                                    elementType: "table"
                                )
                                occurrences.append(occurrence)
                                
                                if range.upperBound <= searchStartIndex {
                                    searchStartIndex = headerCell.index(after: searchStartIndex)
                                } else {
                                    searchStartIndex = range.upperBound
                                }
                                
                                if searchStartIndex >= headerCell.endIndex {
                                    break
                                }
                            }
                        }
                        
                        // Search in data cells
                        for (rowIndex, row) in data.enumerated() {
                            for (columnIndex, cell) in row.enumerated() {
                                var searchStartIndex = cell.startIndex
                                
                                while let range = cell.range(of: searchText, options: .caseInsensitive, range: searchStartIndex..<cell.endIndex) {
                                    
                                    let nsRange = NSRange(range, in: cell)
                                    let cellPosition = (rowIndex + 1) * 1000 + columnIndex // FIXME: bit tricky, but this is needed to properly handle search occurrences in tables
                                    let adjustedRange = NSRange(location: nsRange.location + cellPosition * 10000, length: nsRange.length)
                                    let occurrence = SearchOccurrence(
                                        messageID: message.id,
                                        range: adjustedRange,
                                        elementIndex: elementIndex,
                                        elementType: "table"
                                    )
                                    occurrences.append(occurrence)
                                    
                                    if range.upperBound <= searchStartIndex {
                                        searchStartIndex = cell.index(after: searchStartIndex)
                                    } else {
                                        searchStartIndex = range.upperBound
                                    }
                                    
                                    if searchStartIndex >= cell.endIndex {
                                        break
                                    }
                                }
                            }
                        }
                    } else {
                        let (content, elementType) = extractContentAndType(from: element)
                        
                        var searchStartIndex = content.startIndex
                        
                        while let range = content.range(of: searchText, options: .caseInsensitive, range: searchStartIndex..<content.endIndex) {
                            
                            let nsRange = NSRange(range, in: content)
                            let occurrence = SearchOccurrence(
                                messageID: message.id,
                                range: nsRange,
                                elementIndex: elementIndex,
                                elementType: elementType
                            )
                            occurrences.append(occurrence)
                            
                            if range.upperBound <= searchStartIndex {
                                searchStartIndex = content.index(after: searchStartIndex)
                            } else {
                                searchStartIndex = range.upperBound
                            }
                            
                            if searchStartIndex >= content.endIndex {
                                break
                            }
                        }
                    }
                }
            }
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.searchOccurrences = occurrences
            self?.currentSearchIndex = occurrences.isEmpty ? nil : 0
        }
    }
    
    private func extractContentAndType(from element: MessageElements) -> (String, String) {
        switch element {
        case .text(let content):
            return (content, "text")
        case .code(let code, _, _):
            return (code, "code")
        case .table(let header, let data):
            // Combine header and data for search
            let headerText = header.joined(separator: " ")
            let dataText = data.map { $0.joined(separator: " ") }.joined(separator: " ")
            let combinedText = headerText + " " + dataText
            return (combinedText, "table")
        case .formula(let content):
            return (content, "formula")
        case .thinking(let content, _):
            return (content, "thinking")
        case .image(_):
            return ("", "image") // Images don't have searchable text content
        }
    }

    func goToNextOccurrence() {
        guard let currentIndex = currentSearchIndex, !searchOccurrences.isEmpty else { return }
        let nextIndex = currentIndex + 1
        currentSearchIndex = nextIndex >= searchOccurrences.count ? 0 : nextIndex
    }

    func goToPreviousOccurrence() {
        guard let currentIndex = currentSearchIndex, !searchOccurrences.isEmpty else { return }
        let prevIndex = currentIndex - 1
        currentSearchIndex = prevIndex < 0 ? searchOccurrences.count - 1 : prevIndex
    }
}
