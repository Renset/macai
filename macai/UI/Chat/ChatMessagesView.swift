//
//  ChatMessagesView.swift
//  macai
//
//  Created by AI Assistant on 20.01.2025.
//

import CoreData
import SwiftUI

struct ChatMessagesView: View {
    @ObservedObject var chat: ChatEntity
    @ObservedObject var chatViewModel: ChatViewModel
    @Binding var newMessage: String
    @Binding var editSystemMessage: Bool
    @Binding var isStreaming: Bool
    @Binding var currentError: ErrorMessage?
    @Binding var userIsScrolling: Bool
    @Binding var searchText: String
    @State private var scrollDebounceWorkItem: DispatchWorkItem?
    @State private var codeBlocksRendered = false
    @State private var pendingCodeBlocks = 0
    @State private var isInitialLoad = true
    
    private var backgroundColor: Color {
        #if os(iOS)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color(NSColor.controlBackgroundColor)
        #endif
    }

    private var shouldShowWaitingBubble: Bool {
        chat.waitingForResponse && (chat.lastMessage?.own ?? true)
    }
    
    var body: some View {
        ScrollView {
            ScrollViewReader { scrollView in
                VStack {
                    SystemMessageBubbleView(
                        message: chat.systemMessage,
                        color: chat.persona?.color,
                        newMessage: $newMessage,
                        editSystemMessage: $editSystemMessage,
                        searchText: $searchText
                    )
                    .id("system_message")

                    if !chatViewModel.sortedMessages.isEmpty {
                        ForEach(chatViewModel.sortedMessages, id: \.objectID) { messageEntity in
                            let bubbleContent = ChatBubbleContent(
                                message: messageEntity.body,
                                own: messageEntity.own,
                                waitingForResponse: messageEntity.waitingForResponse,
                                errorMessage: nil,
                                systemMessage: false,
                                isStreaming: isStreaming,
                                isLatestMessage: messageEntity.objectID == chatViewModel.sortedMessages.last?.objectID
                            )
                            ChatBubbleView(content: bubbleContent, message: messageEntity, searchText: $searchText, currentSearchOccurrence: chatViewModel.currentSearchOccurrence)
                                .id(messageEntity.objectID)
                        }
                    }

                    if shouldShowWaitingBubble {
                        let bubbleContent = ChatBubbleContent(
                            message: "",
                            own: false,
                            waitingForResponse: true,
                            errorMessage: nil,
                            systemMessage: false,
                            isStreaming: isStreaming,
                            isLatestMessage: false
                        )

                        ChatBubbleView(content: bubbleContent, searchText: $searchText)
                            .id(-1)
                    }
                    else if let error = currentError {
                        let bubbleContent = ChatBubbleContent(
                            message: "",
                            own: false,
                            waitingForResponse: false,
                            errorMessage: error,
                            systemMessage: false,
                            isStreaming: isStreaming,
                            isLatestMessage: true
                        )

                        ChatBubbleView(content: bubbleContent, searchText: $searchText)
                            .id(-2)
                    }
                }
                .padding(24)
                .onAppear {
                    pendingCodeBlocks = chatViewModel.sortedMessages.reduce(0) { count, message in
                        count + (message.body.components(separatedBy: "```").count - 1) / 2
                    }
                    isInitialLoad = true

                    if pendingCodeBlocks == 0 {
                        codeBlocksRendered = true
                        isInitialLoad = false
                    }
                }
                .onSwipe { event in
                    switch event.direction {
                    case .up:
                        userIsScrolling = true
                    case .none, .down, .left, .right:
                        break
                    }
                }
                .onChange(of: chat.lastMessage?.body) { _ in
                    if isStreaming && !userIsScrolling {
                        scrollDebounceWorkItem?.cancel()

                        let workItem = DispatchWorkItem {
                            if let lastMessage = chatViewModel.sortedMessages.last {
                                withAnimation(.easeOut(duration: 1)) {
                                    scrollView.scrollTo(lastMessage.objectID, anchor: .bottom)
                                }
                            }
                        }

                        scrollDebounceWorkItem = workItem
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
                    }
                }
                .onChange(of: chatViewModel.sortedMessages.count) { _ in
                    if shouldShowWaitingBubble || currentError != nil {
                        withAnimation {
                            scrollView.scrollTo(-1)
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NonStreamingMessageCompleted"))) { notification in
                    if let notificationChat = notification.object as? ChatEntity, notificationChat == chat {
                        DispatchQueue.main.async {
                            if !isStreaming && !userIsScrolling {
                                let sortedMessages = chatViewModel.sortedMessages
                                if let lastMessage = sortedMessages.last {
                                    withAnimation(.easeOut(duration: 0.5)) {
                                        scrollView.scrollTo(lastMessage.objectID, anchor: .bottom)
                                    }
                                }
                            }
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CodeBlockRendered"))) { _ in
                    if pendingCodeBlocks > 0 {
                        pendingCodeBlocks -= 1
                        if pendingCodeBlocks == 0 {
                            codeBlocksRendered = true
                            if isInitialLoad {
                                isInitialLoad = false
                                if let lastMessage = chatViewModel.sortedMessages.last {
                                    DispatchQueue.main.async {
                                        scrollView.scrollTo(lastMessage.objectID, anchor: .bottom)
                                    }
                                }
                            }
                        }
                    }
                }
                .onChange(of: chatViewModel.currentSearchOccurrence) { newOccurrence in
                    if let occurrence = newOccurrence {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            // Generate element ID for the occurrence
                            let messageIDString = occurrence.messageID.uriRepresentation().absoluteString
                            let elementID = "\(messageIDString)_element_\(occurrence.elementIndex)"
                            scrollView.scrollTo(elementID, anchor: .center)
                        }
                    }
                }
            }
            .id("chatContainer")
        }
        .defaultScrollAnchor(.bottom)
        .padding(.bottom, 6)
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [
                    .clear,
                    backgroundColor.opacity(0.25),
                    backgroundColor.opacity(0.5),
                    backgroundColor.opacity(0.9),
                    backgroundColor,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 40)
            .padding(.trailing, 16)
            .allowsHitTesting(false)
        }
    }
}
