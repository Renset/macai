//
//  ChatView.swift
//  macai

//
//  Created by Renat Notfullin on 18.03.2023.
//

import CoreData
import SwiftUI
import UniformTypeIdentifiers

struct ChatView: View {
    let viewContext: NSManagedObjectContext
    @State var chat: ChatEntity
    @Binding var searchText: String
    @AppStorage("lastOpenedChatId") var lastOpenedChatId = ""
    
    // UI State
    @State private var messageField = ""
    @State private var newMessage: String = ""
    @State private var editSystemMessage: Bool = false
    @State private var attachedImages: [ImageAttachment] = []
    @State private var attachedFiles: [DocumentAttachment] = []
    @State private var isBottomContainerExpanded = false
    @State private var renderTime: Double = 0
    @State private var reasoningStartTimes: [NSManagedObjectID: Date] = [:]
    @State private var reasoningDurations: [NSManagedObjectID: TimeInterval] = [:]
    @State private var lastRequestStartTime: Date?
    @State private var activeReasoningMessageID: NSManagedObjectID?
    
    // View models and logic
    @StateObject private var chatViewModel: ChatViewModel
    @StateObject private var store = ChatStore(persistenceController: PersistenceController.shared)
    @StateObject private var logicHandler: ChatLogicHandler
    @StateObject private var draftManager: ChatDraftManager
    
    // Environment
    @Environment(\.colorScheme) private var colorScheme
    var backgroundColor = Color(NSColor.controlBackgroundColor)
    private let reasoningTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    
    // MARK: - Initialization
    init(viewContext: NSManagedObjectContext, chat: ChatEntity, searchText: Binding<String>) {
        self.viewContext = viewContext
        self._chat = State(initialValue: chat)
        self._searchText = searchText

        // Initialize view models
        let viewModel = ChatViewModel(chat: chat, viewContext: viewContext)
        self._chatViewModel = StateObject(wrappedValue: viewModel)
        
        // Initialize logic handler
        let store = ChatStore(persistenceController: PersistenceController.shared)
        let handler = ChatLogicHandler(viewContext: viewContext, chat: chat, chatViewModel: viewModel, store: store)
        self._logicHandler = StateObject(wrappedValue: handler)
        self._store = StateObject(wrappedValue: store)
        self._draftManager = StateObject(wrappedValue: ChatDraftManager(viewContext: viewContext))
    }

    private var pdfUploadsAllowed: Bool {
        chat.apiService?.pdfUploadsAllowed ?? false
    }

    private var imageUploadsAllowed: Bool {
        chat.apiService?.imageUploadsAllowed ?? false
    }

    private var imageGenerationSupported: Bool {
        chat.apiService?.imageGenerationSupported ?? false
    }

    private var isInferenceInProgress: Bool {
        logicHandler.isStreaming || chat.waitingForResponse
    }

    private var draftSignature: DraftSignature {
        DraftSignature(
            message: newMessage,
            imageIDs: attachedImages.map(\.id),
            fileIDs: attachedFiles.map(\.id),
            imageReadyStates: attachedImages.map(\.isReadyForUpload),
            fileReadyStates: attachedFiles.map(\.isReadyForUpload)
        )
    }

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            chatMessagesView
            chatInputView
        }
        .background(backgroundColor)
        .navigationTitle(chat.name != "" ? chat.name : chat.persona?.name ?? "macai LLM chat")
        .onAppear(perform: {
            self.lastOpenedChatId = chat.id.uuidString
            print("lastOpenedChatId: \(lastOpenedChatId)")
            Self._printChanges()
            draftManager.restoreDraftIfNeeded(
                chat: chat,
                newMessage: &newMessage,
                attachedImages: &attachedImages,
                attachedFiles: &attachedFiles
            )
            DispatchQueue.main.asyncAfter(deadline: .now()) {
                let startTime = CFAbsoluteTimeGetCurrent()
                _ = self.body
                renderTime = CFAbsoluteTimeGetCurrent() - startTime
            }
        })
        .onDisappear {
            draftManager.persistImmediately(
                chat: chat,
                message: newMessage,
                images: attachedImages,
                files: attachedFiles,
                isEditingSystemMessage: editSystemMessage
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RecreateMessageManager"))) { notification in
            if let chatId = notification.userInfo?["chatId"] as? UUID,
                chatId == chat.id
            {
                print("RecreateMessageManager notification received for chat \(chatId)")
                chatViewModel.recreateMessageManager()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RetryMessage"))) { _ in
            lastRequestStartTime = Date()
            logicHandler.handleRetryMessage(newMessage: &newMessage)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("StopInference"))) { _ in
            logicHandler.stopInference()
            resetReasoningTimingState()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("IgnoreError"))) { _ in
            logicHandler.ignoreError()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("FindNext"))) { _ in
            if !searchText.isEmpty {
                chatViewModel.goToNextOccurrence()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("FindPrevious"))) { _ in
            if !searchText.isEmpty {
                chatViewModel.goToPreviousOccurrence()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ChatResponseCompleted"))) { notification in
            guard let notificationChat = notification.object as? ChatEntity, notificationChat == chat else { return }
            if let lastMessage = chat.lastMessage, !lastMessage.own {
                finalizeReasoningTimingIfNeeded(for: lastMessage)
            }
            lastRequestStartTime = nil
        }
        .onReceive(reasoningTimer) { _ in
            updateLiveReasoningDurationIfNeeded()
        }
        .toolbar {
            if !searchText.isEmpty && !chatViewModel.searchOccurrences.isEmpty {
                SearchNavigationView(chatViewModel: chatViewModel)
            }
        }
        .onChange(of: searchText) { newSearchText in
            chatViewModel.updateSearchOccurrences(searchText: newSearchText)
        }
        .onChange(of: draftSignature) { _ in
            guard !editSystemMessage else { return }
            scheduleDraftSave()
        }
        .onChange(of: editSystemMessage) { isEditing in
            if !isEditing, newMessage.isEmpty {
                newMessage = chat.newMessage ?? ""
            }
        }
        .onChange(of: chat.lastMessage?.body) { _ in
            guard let lastMessage = chat.lastMessage, !lastMessage.own else { return }
            updateReasoningTiming(for: lastMessage, isStreamingActive: logicHandler.isStreaming)
        }
        .onExitCommand {
            if editSystemMessage {
                cancelSystemMessageEdit()
            }
        }
    }

    private var chatMessagesView: some View {
        ChatMessagesView(
            chat: chat,
            chatViewModel: chatViewModel,
            newMessage: $newMessage,
            editSystemMessage: $editSystemMessage,
            isStreaming: $logicHandler.isStreaming,
            currentError: $logicHandler.currentError,
            userIsScrolling: $logicHandler.userIsScrolling,
            searchText: $searchText,
            reasoningDurations: reasoningDurations,
            activeReasoningMessageID: activeReasoningMessageID
        )
        .modifier(MeasureModifier(renderTime: $renderTime))
    }

    private var chatInputView: some View {
        ChatInputView(
            chat: chat,
            newMessage: $newMessage,
            editSystemMessage: $editSystemMessage,
            attachedImages: $attachedImages,
            attachedFiles: $attachedFiles,
            isBottomContainerExpanded: $isBottomContainerExpanded,
            isInferenceInProgress: isInferenceInProgress,
            imageUploadsAllowed: imageUploadsAllowed,
            pdfUploadsAllowed: pdfUploadsAllowed,
            imageGenerationSupported: imageGenerationSupported,
            onSendMessage: handleSendMessage,
            onAddImage: handleAddImage,
            onAddFile: handleAddFile,
            onStopInference: handleStopInference,
            onCancelSystemMessageEdit: cancelSystemMessageEdit
        )
    }

    private func handleSendMessage() {
        lastRequestStartTime = Date()
        logicHandler.sendMessage(
            messageText: newMessage,
            attachedImages: attachedImages,
            attachedFiles: attachedFiles
        )
        newMessage = ""
        attachedImages = []
        attachedFiles = []
        draftManager.clearDraft(chat: chat)

        if chatViewModel.sortedMessages.count == 1 { // First message just sent
            withAnimation {
                isBottomContainerExpanded = false
            }
        }
    }

    private func handleAddImage() {
        logicHandler.selectAndAddImages { newAttachments in
            withAnimation {
                attachedImages.append(contentsOf: newAttachments)
            }
        }
    }

    private func handleAddFile() {
        logicHandler.selectAndAddPDFs { newAttachments in
            withAnimation {
                attachedFiles.append(contentsOf: newAttachments)
            }
        }
    }

    private func handleStopInference() {
        logicHandler.stopInference()
        resetReasoningTimingState()
    }

    private func scheduleDraftSave() {
        draftManager.scheduleSave(
            chat: chat,
            message: newMessage,
            images: attachedImages,
            files: attachedFiles,
            isEditingSystemMessage: editSystemMessage
        )
    }

    private func cancelSystemMessageEdit() {
        guard editSystemMessage else { return }
        newMessage = chat.newMessage ?? ""
        editSystemMessage = false
    }

    private func updateReasoningTiming(for message: MessageEntity, isStreamingActive: Bool) {
        let body = message.body
        guard body.contains("<think>") else { return }

        let messageID = message.objectID
        if message.reasoningDuration > 0 {
            return
        }

        if reasoningStartTimes[messageID] == nil {
            guard isStreamingActive || lastRequestStartTime != nil else { return }
            let startTime = isStreamingActive ? Date() : (lastRequestStartTime ?? Date())
            reasoningStartTimes[messageID] = startTime
            activeReasoningMessageID = messageID
            reasoningDurations[messageID] = 0
        }

        if body.contains("</think>"), let startTime = reasoningStartTimes[messageID] {
            let duration = max(0, Date().timeIntervalSince(startTime))
            reasoningDurations[messageID] = duration
            persistReasoningDuration(duration, for: message)
            activeReasoningMessageID = nil
            reasoningStartTimes.removeValue(forKey: messageID)
        }
    }

    private func updateLiveReasoningDurationIfNeeded() {
        guard let messageID = activeReasoningMessageID,
              let startTime = reasoningStartTimes[messageID] else { return }
        reasoningDurations[messageID] = max(0, Date().timeIntervalSince(startTime))
    }

    private func finalizeReasoningTimingIfNeeded(for message: MessageEntity) {
        let messageID = message.objectID
        guard message.reasoningDuration == 0 else { return }
        guard let startTime = reasoningStartTimes[messageID] else { return }
        let duration = max(0, Date().timeIntervalSince(startTime))
        reasoningDurations[messageID] = duration
        persistReasoningDuration(duration, for: message)
        activeReasoningMessageID = nil
        reasoningStartTimes.removeValue(forKey: messageID)
    }

    private func persistReasoningDuration(_ duration: TimeInterval, for message: MessageEntity) {
        guard duration > 0 else { return }
        message.reasoningDuration = duration
        viewContext.saveWithRetry(attempts: 1)
    }

    private func resetReasoningTimingState() {
        lastRequestStartTime = nil
        for messageID in reasoningStartTimes.keys {
            reasoningDurations.removeValue(forKey: messageID)
        }
        reasoningStartTimes.removeAll()
        activeReasoningMessageID = nil
    }
}

private struct DraftSignature: Equatable {
    let message: String
    let imageIDs: [UUID]
    let fileIDs: [UUID]
    let imageReadyStates: [Bool]
    let fileReadyStates: [Bool]
}

struct SearchNavigationView: View {
    @ObservedObject var chatViewModel: ChatViewModel

    var body: some View {
        HStack {
            if let currentIndex = chatViewModel.currentSearchIndex {
                Text("\(currentIndex + 1) of \(chatViewModel.searchOccurrences.count)")
                    .font(.system(size: 12))
            }

            Button(action: {
                chatViewModel.goToPreviousOccurrence()
            }) {
                Image(systemName: "chevron.up")
            }
            .disabled(chatViewModel.searchOccurrences.isEmpty)

            Button(action: {
                chatViewModel.goToNextOccurrence()
            }) {
                Image(systemName: "chevron.down")
            }
            .disabled(chatViewModel.searchOccurrences.isEmpty)
        }
    }
}

// MARK: - Measure Modifier
struct MeasureModifier: ViewModifier {
    @Binding var renderTime: Double

    func body(content: Content) -> some View {
        content
            .onAppear {
                let start = DispatchTime.now()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    let end = DispatchTime.now()
                    let nanoTime = end.uptimeNanoseconds - start.uptimeNanoseconds
                    let timeInterval = Double(nanoTime) / 1_000_000  // Convert to milliseconds
                    renderTime = timeInterval
                    print("Render time: \(timeInterval) ms")
                }
            }
    }
}
