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
    var onCancelGeneration: (() -> Void)?
    @Binding var isExpanded: Bool
    @Binding var isGenerating: Bool
    var onExpandedStateChange: ((Bool) -> Void)?  // Add this line

    init(
        chat: ChatEntity,
        newMessage: Binding<String>,
        isExpanded: Binding<Bool>,
        isGenerating: Binding<Bool>,
        onSendMessage: @escaping () -> Void,
        onCancelGeneration: (() -> Void)? = nil
    ) {
        self.chat = chat
        self._newMessage = newMessage
        self.onSendMessage = onSendMessage
        self.onCancelGeneration = onCancelGeneration
        self._isExpanded = isExpanded
        self._isGenerating = isGenerating

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
                    HStack {
                        MessageInputView(
                            text: $newMessage,
                            onEnter: onSendMessage,
                            isFocused: .focused
                        )
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .multilineTextAlignment(.leading)
                        .lineLimit(nil)

                        if isGenerating, let cancelAction = onCancelGeneration {
                            Button(action: cancelAction) {
                                Image(systemName: "stop.circle.fill")
                                    .foregroundColor(.red)
                                    .font(.system(size: 24))
                            }
                            .buttonStyle(PlainButtonStyle())
                            .transition(.opacity)
                        }
                    }
                    .padding()
                }
                .border(width: 1, edges: [.top], color: Color(NSColor.windowBackgroundColor).opacity(0.8))
            }
        }

    }
}
