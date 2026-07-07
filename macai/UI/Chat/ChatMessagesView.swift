//
//  ChatMessagesView.swift
//  macai
//
//  Created by Renat Notfullin on 20.01.2025.
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
    let reasoningDurations: [NSManagedObjectID: TimeInterval]
    let activeReasoningMessageID: NSManagedObjectID?
    @State private var scrollDebounceWorkItem: DispatchWorkItem?
    @State private var initialLoadSettleWorkItem: DispatchWorkItem?
    @State private var isInitialLoad = true

    private static let bottomAnchorID = "bottomAnchor"

    var backgroundColor = Color(NSColor.controlBackgroundColor)

    private var shouldShowWaitingBubble: Bool {
        chat.waitingForResponse && (chat.lastMessage?.own ?? true)
    }
    
    var body: some View {
        ScrollView {
            ScrollViewReader { scrollView in
                VStack(spacing: 0) {
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
                            let storedDuration = messageEntity.reasoningDuration > 0 ? messageEntity.reasoningDuration : nil
                            let bubbleContent = ChatBubbleContent(
                                message: messageEntity.body,
                                own: messageEntity.own,
                                waitingForResponse: messageEntity.waitingForResponse,
                                errorMessage: nil,
                                systemMessage: false,
                                isStreaming: isStreaming,
                                isLatestMessage: messageEntity.objectID == chatViewModel.sortedMessages.last?.objectID,
                                reasoningDuration: reasoningDurations[messageEntity.objectID] ?? storedDuration,
                                isActiveReasoning: messageEntity.objectID == activeReasoningMessageID
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
                            isLatestMessage: false,
                            reasoningDuration: nil,
                            isActiveReasoning: false
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
                            isLatestMessage: true,
                            reasoningDuration: nil,
                            isActiveReasoning: false
                        )

                        ChatBubbleView(content: bubbleContent, searchText: $searchText)
                            .id(-2)
                    }

                }
                .padding(24)

                // Invisible sentinel: the true bottom of the scrollable content.
                // It sits below the list padding, so anchoring to it lands exactly
                // at the end — a sentinel inside the padded stack stops 24 pt short.
                Color.clear
                    .frame(height: 1)
                    .id(Self.bottomAnchorID)
                }
                .background(
                    GeometryReader { geometry in
                        Color.clear.preference(key: ContentHeightPreferenceKey.self, value: geometry.size.height)
                    }
                )
                .onPreferenceChange(ContentHeightPreferenceKey.self) { _ in
                    // Async rendering (code highlighting, images) keeps changing the
                    // content height after the first layout pass. While the chat is
                    // still settling after being opened, re-pin to the bottom on
                    // every height change so we never stop short of the last message.
                    guard isInitialLoad, !userIsScrolling else { return }
                    // Pin on the next runloop turn so the scroll target is computed
                    // from the freshly committed layout, not mid-update metrics.
                    DispatchQueue.main.async {
                        guard isInitialLoad, !userIsScrolling else { return }
                        scrollView.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                    }
                    scheduleInitialLoadSettle()
                }
                .onAppear {
                    isInitialLoad = true
                    scheduleInitialLoadSettle()
                }
                .onChange(of: userIsScrolling) { _, isScrolling in
                    // The user took over; stop forcing the view to the bottom.
                    if isScrolling {
                        endInitialLoad()
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
                .onChange(of: chat.lastMessage?.body) { _, _ in
                    if isStreaming && !userIsScrolling {
                        scrollDebounceWorkItem?.cancel()

                        let workItem = DispatchWorkItem {
                            withAnimation(.easeOut(duration: 1)) {
                                scrollView.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                            }
                        }

                        scrollDebounceWorkItem = workItem
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
                    }
                }
                .onChange(of: chatViewModel.sortedMessages.count) { _, _ in
                    if shouldShowWaitingBubble || currentError != nil {
                        withAnimation {
                            scrollView.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("NonStreamingMessageCompleted"))) { notification in
                    if let notificationChat = notification.object as? ChatEntity, notificationChat == chat {
                        DispatchQueue.main.async {
                            if !isStreaming && !userIsScrolling {
                                withAnimation(.easeOut(duration: 0.5)) {
                                    scrollView.scrollTo(Self.bottomAnchorID, anchor: .bottom)
                                }
                            }
                        }
                    }
                }
                .onChange(of: chatViewModel.currentSearchOccurrence) { _, newOccurrence in
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

    /// Ends the "initial load" phase once the content height has been stable
    /// for a short quiet period, i.e. async rendering has finished.
    private func scheduleInitialLoadSettle() {
        initialLoadSettleWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            isInitialLoad = false
        }
        initialLoadSettleWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.25, execute: workItem)
    }

    private func endInitialLoad() {
        initialLoadSettleWorkItem?.cancel()
        initialLoadSettleWorkItem = nil
        isInitialLoad = false
    }
}

private struct ContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
