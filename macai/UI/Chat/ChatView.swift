//
//  ChatView.swift
//  macai

//
//  Created by Renat Notfullin on 18.03.2023.
//

import CoreData
import SwiftUI
import UniformTypeIdentifiers

#if os(iOS)
import PhotosUI
#endif

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
    @State private var isBottomContainerExpanded = false
    @State private var renderTime: Double = 0
    @State private var draftSaveWorkItem: DispatchWorkItem?
    #if os(iOS)
    @State private var isPhotoPickerPresented = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    #endif
    
    // View models and logic
    @StateObject private var chatViewModel: ChatViewModel
    @StateObject private var store = ChatStore(persistenceController: PersistenceController.shared)
    @StateObject private var logicHandler: ChatLogicHandler
    
    // Environment
    @Environment(\.colorScheme) private var colorScheme
    private var backgroundColor: Color {
        #if os(iOS)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color(NSColor.controlBackgroundColor)
        #endif
    }
    
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
    }

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            // Messages view
            ChatMessagesView(
                chat: chat,
                chatViewModel: chatViewModel,
                newMessage: $newMessage,
                editSystemMessage: $editSystemMessage,
                isStreaming: $logicHandler.isStreaming,
                currentError: $logicHandler.currentError,
                userIsScrolling: $logicHandler.userIsScrolling,
                searchText: $searchText
            )
            .modifier(MeasureModifier(renderTime: $renderTime))
            
            // Input view
            ChatInputView(
                chat: chat,
                newMessage: $newMessage,
                editSystemMessage: $editSystemMessage,
                attachedImages: $attachedImages,
                isBottomContainerExpanded: $isBottomContainerExpanded,
                isInferenceInProgress: logicHandler.isStreaming || chat.waitingForResponse,
                imageUploadsAllowed: chat.apiService?.imageUploadsAllowed ?? false,
                imageGenerationSupported: chat.apiService?.imageGenerationSupported ?? false,
                onSendMessage: {
                    logicHandler.sendMessage(
                        messageText: newMessage,
                        attachedImages: attachedImages
                    )
                    newMessage = ""
                    attachedImages = []
                    chat.newMessage = ""
                    store.saveInCoreData()
                    
                    if chatViewModel.sortedMessages.count == 1 { // First message just sent
                        withAnimation {
                            isBottomContainerExpanded = false
                        }
                    }
                },
                onAddImage: {
                    #if os(iOS)
                    isPhotoPickerPresented = true
                    #else
                    logicHandler.selectAndAddImages { newAttachments in
                        withAnimation {
                            self.attachedImages.append(contentsOf: newAttachments)
                        }
                    }
                    #endif
                },
                onStopInference: {
                    logicHandler.stopInference()
                },
                onCancelSystemMessageEdit: {
                    cancelSystemMessageEdit()
                }
            )
        }
        #if os(iOS)
        .background(backgroundColor.ignoresSafeArea())
        #else
        .background(backgroundColor)
        #endif
        #if os(iOS)
        .photosPicker(isPresented: $isPhotoPickerPresented, selection: $selectedPhotoItems, matching: .images)
        .onChange(of: selectedPhotoItems) { newItems in
            _ = _Concurrency.Task<Void, Never>.detached(
                name: "PhotoPickerLoad",
                priority: .userInitiated
            ) {
                var newAttachments: [ImageAttachment] = []
                for item in newItems {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = NSImage(data: data) {
                        let attachment = ImageAttachment(image: image)
                        attachment.saveToEntity(context: viewContext, waitForCompletion: true)
                        newAttachments.append(attachment)
                    }
                }
                await MainActor.run {
                    self.attachedImages.append(contentsOf: newAttachments)
                    self.selectedPhotoItems = []
                }
            }
        }
        #endif
        .navigationTitle(
            chat.name != "" ? chat.name : chat.persona?.name ?? "macai LLM chat"
        )
        .onAppear(perform: {
            self.lastOpenedChatId = chat.id.uuidString
            print("lastOpenedChatId: \(lastOpenedChatId)")
            Self._printChanges()
            if newMessage.isEmpty {
                newMessage = chat.newMessage ?? ""
            }
            DispatchQueue.main.asyncAfter(deadline: .now()) {
                let startTime = CFAbsoluteTimeGetCurrent()
                _ = self.body
                renderTime = CFAbsoluteTimeGetCurrent() - startTime
            }
        })
        .onDisappear {
            persistDraftImmediately()
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
            logicHandler.handleRetryMessage(newMessage: &newMessage)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("StopInference"))) { _ in
            logicHandler.stopInference()
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
        .toolbar {
            if !searchText.isEmpty && !chatViewModel.searchOccurrences.isEmpty {
                SearchNavigationView(chatViewModel: chatViewModel)
            }
        }
        .onChange(of: searchText) { newSearchText in
            chatViewModel.updateSearchOccurrences(searchText: newSearchText)
        }
        .onChange(of: newMessage) { updatedMessage in
            guard !editSystemMessage else { return }
            scheduleDraftSave(updatedMessage)
        }
        .onChange(of: editSystemMessage) { isEditing in
            if !isEditing, newMessage.isEmpty {
                newMessage = chat.newMessage ?? ""
            }
        }
        #if os(macOS)
        .onExitCommand {
            if editSystemMessage {
                cancelSystemMessageEdit()
            }
        }
        #endif
    }

    private func scheduleDraftSave(_ message: String) {
        draftSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [chat, store] in
            chat.newMessage = message
            store.saveInCoreData()
        }
        draftSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: workItem)
    }

    private func persistDraftImmediately() {
        guard !editSystemMessage else { return }
        draftSaveWorkItem?.cancel()
        chat.newMessage = newMessage
        store.saveInCoreData()
    }

    private func cancelSystemMessageEdit() {
        guard editSystemMessage else { return }
        newMessage = chat.newMessage ?? ""
        editSystemMessage = false
    }
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
