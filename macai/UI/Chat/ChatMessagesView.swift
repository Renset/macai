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
    @Binding var isStreaming: Bool
    @Binding var currentError: ErrorMessage?
    @Binding var userIsScrolling: Bool
    @Binding var searchText: String
    @State private var scrollDebounceWorkItem: DispatchWorkItem?
    @State private var codeBlocksRendered = false
    @State private var pendingCodeBlocks = 0
    
    var backgroundColor = Color(NSColor.controlBackgroundColor)
    
    var body: some View {
        ScrollView {
            ScrollViewReader { scrollView in
                VStack {
                    SystemMessageBubbleView(
                        message: chat.systemMessage,
                        color: chat.persona?.color,
                        newMessage: .constant(""),
                        editSystemMessage: .constant(false),
                        searchText: $searchText
                    )
                    .id("system_message")

                    if chat.messages.count > 0 {
                        ForEach(chatViewModel.sortedMessages, id: \.objectID) { messageEntity in
                            let bubbleContent = ChatBubbleContent(
                                message: messageEntity.body,
                                own: messageEntity.own,
                                waitingForResponse: messageEntity.waitingForResponse,
                                errorMessage: nil,
                                systemMessage: false,
                                isStreaming: isStreaming,
                                isLatestMessage: messageEntity.id == chatViewModel.sortedMessages.last?.id
                            )
                            ChatBubbleView(content: bubbleContent, message: messageEntity, searchText: $searchText, currentSearchOccurrence: chatViewModel.currentSearchOccurrence)
                                .id(messageEntity.objectID)
                        }
                    }

                    if chat.waitingForResponse {
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

                    if pendingCodeBlocks == 0 {
                        codeBlocksRendered = true
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
                .onReceive([chat.messages.count].publisher) { newCount in
                    DispatchQueue.main.async {
                        if chat.waitingForResponse || currentError != nil {
                            withAnimation {
                                scrollView.scrollTo(-1)
                            }
                        }
                        else if newCount > 0 {
                            let sortedMessages = chatViewModel.sortedMessages
                            if let lastMessage = sortedMessages.last {
                                scrollView.scrollTo(lastMessage.objectID, anchor: .bottom)
                            }
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CodeBlockRendered"))) { _ in
                    if pendingCodeBlocks > 0 {
                        pendingCodeBlocks -= 1
                        if pendingCodeBlocks == 0 {
                            codeBlocksRendered = true
                            if let lastMessage = chatViewModel.sortedMessages.last {
                                scrollView.scrollTo(lastMessage.objectID, anchor: .bottom)
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
