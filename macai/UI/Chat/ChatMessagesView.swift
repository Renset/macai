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

    private static let bottomAnchorID = "bottomAnchor"
    /// How close (in points) the viewport bottom must be to the content bottom
    /// to still count as "at the bottom". Generous enough to survive rounding
    /// and bounce, small enough that a deliberate scroll releases the pin.
    private static let bottomTolerance: CGFloat = 40

    var backgroundColor = Color(NSColor.controlBackgroundColor)

    private var shouldShowWaitingBubble: Bool {
        chat.waitingForResponse && (chat.lastMessage?.own ?? true)
    }

    var body: some View {
        ScrollView {
            ScrollViewReader { scrollView in
                VStack(spacing: 0) {
                    messagesList
                        .padding(24)

                    // Invisible sentinel: the true bottom of the scrollable content.
                    // It sits below the list padding, so scrolling to it lands exactly
                    // at the end — a sentinel inside the padded stack stops 24 pt short.
                    Color.clear
                        .frame(height: 1)
                        .id(Self.bottomAnchorID)
                }
                .onChange(of: chatViewModel.sortedMessages.count) { _, _ in
                    // A message was just sent (or an error arrived): bring the
                    // conversation tail into view even if the user had scrolled up.
                    if shouldShowWaitingBubble || currentError != nil {
                        withAnimation {
                            scrollView.scrollTo(Self.bottomAnchorID, anchor: .bottom)
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
        // Open at the bottom of the conversation…
        .defaultScrollAnchor(.bottom)
        // …and keep the bottom pinned while content grows (streaming tokens,
        // async code highlighting, image loading). The pin is released as soon
        // as the user scrolls away and re-engaged when they scroll back down;
        // the scroll view adjusts the offset within the same layout pass, so
        // there is no post-hoc "jump to bottom" flicker.
        .defaultScrollAnchor(userIsScrolling ? nil : .bottom, for: .sizeChanges)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.containerSize.height
                >= geometry.contentSize.height + geometry.contentInsets.bottom - Self.bottomTolerance
        } action: { _, isAtBottom in
            userIsScrolling = !isAtBottom
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

    private var messagesList: some View {
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
    }
}
