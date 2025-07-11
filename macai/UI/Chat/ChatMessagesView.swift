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
    @State private var scrollDebounceWorkItem: DispatchWorkItem?
    @State private var codeBlocksRendered = false
    @State private var pendingCodeBlocks = 0
    @State private var isManuallyScrolling = false
    @State private var hasTriggeredLoadMore = false
    
    var backgroundColor = Color(NSColor.controlBackgroundColor)
    
    var body: some View {
        ScrollView {
            ScrollViewReader { scrollView in
                LazyVStack(spacing: 0, pinnedViews: []) {
                    if chatViewModel.isLoadingMoreMessages {
                        HStack {
                            Spacer()
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Loading older messages...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                        .id("loading_indicator")
                    }
                    
                    // Load more trigger (invisible)
                    if chatViewModel.visibleMessages.count < chat.messagesArray.count && !hasTriggeredLoadMore {
                        Color.clear
                            .frame(height: 1)
                            .onAppear {
                                if !chatViewModel.isLoadingMoreMessages {
                                    hasTriggeredLoadMore = true
                                    chatViewModel.loadMoreMessages()
                                    
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                        hasTriggeredLoadMore = false
                                    }
                                }
                            }
                            .id("load_more_trigger")
                    }
                    
                    SystemMessageBubbleView(
                        message: chat.systemMessage,
                        color: chat.persona?.color,
                        newMessage: .constant(""),
                        editSystemMessage: .constant(false)
                    )
                    .id("system_message")

                    if chat.messages.count > 0 {
                        ForEach(chatViewModel.visibleMessages, id: \.self) { messageEntity in
                            let bubbleContent = ChatBubbleContent(
                                message: messageEntity.body,
                                own: messageEntity.own,
                                waitingForResponse: messageEntity.waitingForResponse,
                                errorMessage: nil,
                                systemMessage: false,
                                isStreaming: isStreaming,
                                isLatestMessage: messageEntity.id == chatViewModel.visibleMessages.last?.id
                            )
                            ChatBubbleView(content: bubbleContent, message: messageEntity)
                                .id(messageEntity.id)
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

                        ChatBubbleView(content: bubbleContent)
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

                        ChatBubbleView(content: bubbleContent)
                            .id(-2)
                    }
                }
                .padding(24)
                .onAppear {
                    pendingCodeBlocks = chatViewModel.visibleMessages.reduce(0) { count, message in
                        count + (message.body.components(separatedBy: "```").count - 1) / 2
                    }

                    if let lastMessage = chatViewModel.visibleMessages.last {
                        scrollView.scrollTo(lastMessage.id, anchor: .bottom)
                    }

                    if pendingCodeBlocks == 0 {
                        codeBlocksRendered = true
                    }
                }
                .onSwipe { event in
                    switch event.direction {
                    case .up:
                        userIsScrolling = true
                        isManuallyScrolling = true
                        
                        // Reset manual scrolling flag after a delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            isManuallyScrolling = false
                        }
                    case .down:
                        // User scrolling down, allow auto-scroll to resume
                        isManuallyScrolling = false
                    case .none, .left, .right:
                        break
                    }
                }
                .onChange(of: chatViewModel.visibleMessages.last?.body) { _ in
                    if isStreaming && !userIsScrolling && !isManuallyScrolling {
                        scrollDebounceWorkItem?.cancel()

                        let workItem = DispatchWorkItem {
                            if let lastMessage = chatViewModel.visibleMessages.last {
                                withAnimation(.easeOut(duration: 0.1)) {
                                    scrollView.scrollTo(lastMessage.id, anchor: .bottom)
                                }
                            }
                        }

                        scrollDebounceWorkItem = workItem
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
                    }
                }
                .onReceive([chat.messages.count].publisher) { newCount in
                    DispatchQueue.main.async {
                        if !userIsScrolling && !isManuallyScrolling {
                            if chat.waitingForResponse || currentError != nil {
                                withAnimation {
                                    scrollView.scrollTo(-1)
                                }
                            }
                            else if newCount > 0 {
                                let visibleMessages = chatViewModel.visibleMessages
                                if let lastMessage = visibleMessages.last {
                                    scrollView.scrollTo(lastMessage.id, anchor: .bottom)
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
                            if !isManuallyScrolling, let lastMessage = chatViewModel.visibleMessages.last {
                                scrollView.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .id("chatContainer")
        }
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