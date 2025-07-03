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
    // MARK: - Properties
    let viewContext: NSManagedObjectContext
    @State var chat: ChatEntity
    @AppStorage("lastOpenedChatId") var lastOpenedChatId = ""
    
    // View state
    @State private var messageField = ""
    @State private var newMessage: String = ""
    @State private var editSystemMessage: Bool = false
    @State private var attachedImages: [ImageAttachment] = []
    @State private var isBottomContainerExpanded = false
    @State private var renderTime: Double = 0
    
    // View models and logic
    @StateObject private var chatViewModel: ChatViewModel
    @StateObject private var store = ChatStore(persistenceController: PersistenceController.shared)
    @StateObject private var logicHandler: ChatLogicHandler
    
    // Environment
    @Environment(\.colorScheme) private var colorScheme
    var backgroundColor = Color(NSColor.controlBackgroundColor)
    
    // MARK: - Initialization
    init(viewContext: NSManagedObjectContext, chat: ChatEntity) {
        self.viewContext = viewContext
        self._chat = State(initialValue: chat)

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
                isStreaming: $logicHandler.isStreaming,
                currentError: $logicHandler.currentError,
                userIsScrolling: $logicHandler.userIsScrolling
            )
            .modifier(MeasureModifier(renderTime: $renderTime))
            
            // Input view
            ChatInputView(
                chat: chat,
                newMessage: $newMessage,
                editSystemMessage: $editSystemMessage,
                attachedImages: $attachedImages,
                isBottomContainerExpanded: $isBottomContainerExpanded,
                imageUploadsAllowed: chat.apiService?.imageUploadsAllowed ?? false,
                onSendMessage: {
                    logicHandler.sendMessage(messageText: newMessage, attachedImages: attachedImages)
                    newMessage = ""
                    attachedImages = []
                    
                    if chat.messages.count == 1 { // First message just sent
                        withAnimation {
                            isBottomContainerExpanded = false
                        }
                    }
                },
                onAddImage: {
                    logicHandler.selectAndAddImages { newAttachments in
                        withAnimation {
                            self.attachedImages.append(contentsOf: newAttachments)
                        }
                    }
                }
            )
        }
        .background(backgroundColor)
        .navigationTitle(
            chat.name != "" ? chat.name : chat.persona?.name ?? "macai LLM chat"
        )
        .onAppear(perform: {
            self.lastOpenedChatId = chat.id.uuidString
            print("lastOpenedChatId: \(lastOpenedChatId)")
            Self._printChanges()
            DispatchQueue.main.asyncAfter(deadline: .now()) {
                let startTime = CFAbsoluteTimeGetCurrent()
                _ = self.body
                renderTime = CFAbsoluteTimeGetCurrent() - startTime
            }
        })
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("IgnoreError"))) { _ in
            logicHandler.ignoreError()
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
