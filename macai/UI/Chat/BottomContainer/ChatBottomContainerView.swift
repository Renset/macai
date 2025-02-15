//
//  ChatBottomContainerView.swift
//  macai
//
//  Created by Renat on 19.01.2025.
//
import SwiftUI

struct ChatBottomContainerView: View {
    @ObservedObject var chat: ChatEntity
    @Binding var newMessage: String
    @Binding var isExpanded: Bool
    @Binding var editSystemMessage: Bool
    @Binding var isStreaming: Bool
    var onSendMessage: () -> Void
    var onExpandedStateChange: ((Bool) -> Void)?

    init(
        chat: ChatEntity,
        newMessage: Binding<String>,
        isExpanded: Binding<Bool>,
        editSystemMessage: Binding<Bool>,
        isStreaming: Binding<Bool>,
        onSendMessage: @escaping () -> Void
    ) {
        self.chat = chat
        self._newMessage = newMessage
        self._isExpanded = isExpanded
        self._editSystemMessage = editSystemMessage
        self._isStreaming = isStreaming
        self.onSendMessage = onSendMessage

        if chat.messages.count == 0 {
            DispatchQueue.main.async {
                isExpanded.wrappedValue = true
            }
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            HStack {
                Spacer()
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                        onExpandedStateChange?(isExpanded)
                    }
                }) {
                    HStack {
                        Text(chat.persona?.name ?? "Select Assistant")
                            .font(.caption)
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal)
                .padding(.top, -16)
            }

            VStack(spacing: 0) {
                VStack {
                    if isExpanded {
                        PersonaSelectorView(chat: chat)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }

                HStack {
                    MessageInputView(
                        text: $newMessage,
                        onEnter: onSendMessage,
                        isFocused: .focused
                    )
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .padding(.leading)
                    .padding(.top)
                    .padding(.bottom)
                    .padding(.trailing, 6)

                    ContextActionButton(
                        action: onSendMessage,
                        isWaitingForResponse: chat.waitingForResponse || isStreaming,
                        isEditingSystemMessage: editSystemMessage,
                        hasInputText: !newMessage.isEmpty,
                        hasMessages: chat.messages.count > 0
                    )
                    .padding(.trailing)
                }
                .border(width: 1, edges: [.top], color: Color(NSColor.windowBackgroundColor).opacity(0.8))
            }
        }

    }
}
