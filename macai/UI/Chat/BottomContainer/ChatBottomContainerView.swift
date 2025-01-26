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
    var onSendMessage: () -> Void
    @State private var isPersonaSelectorExpanded: Bool
    var onExpandedStateChange: ((Bool) -> Void)?  // Add this line

    init(
        chat: ChatEntity,
        newMessage: Binding<String>,
        onSendMessage: @escaping () -> Void,
        onExpandedStateChange: ((Bool) -> Void)? = nil
    ) {
        self.chat = chat
        self._newMessage = newMessage
        self.onSendMessage = onSendMessage
        self._isPersonaSelectorExpanded = State(initialValue: chat.messages.count == 0)
        self.onExpandedStateChange = onExpandedStateChange
    }

    var body: some View {
        ZStack(alignment: .top) {
            HStack {
                Spacer()
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isPersonaSelectorExpanded.toggle()
                        onExpandedStateChange?(isPersonaSelectorExpanded)
                    }
                }) {
                    HStack {
                        Text(chat.persona?.name ?? "Select Assistant")
                            .font(.caption)
                        Image(systemName: isPersonaSelectorExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal)
                .padding(.top, -16)
            }

            VStack(spacing: 0) {
                VStack {
                    if isPersonaSelectorExpanded {
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
                    .padding()
                }
                .border(width: 1, edges: [.top], color: Color(NSColor.windowBackgroundColor).opacity(0.8))
            }
        }

    }
}
