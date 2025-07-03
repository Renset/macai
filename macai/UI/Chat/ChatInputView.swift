//
//  ChatInputView.swift
//  macai
//
//  Created by AI Assistant on 20.01.2025.
//

import SwiftUI
import UniformTypeIdentifiers

struct ChatInputView: View {
    @ObservedObject var chat: ChatEntity
    @Binding var newMessage: String
    @Binding var editSystemMessage: Bool
    @Binding var attachedImages: [ImageAttachment]
    @Binding var isBottomContainerExpanded: Bool
    
    let imageUploadsAllowed: Bool
    let onSendMessage: () -> Void
    let onAddImage: () -> Void
    
    @StateObject private var store = ChatStore(persistenceController: PersistenceController.shared)
    
    var body: some View {
        ChatBottomContainerView(
            chat: chat,
            newMessage: $newMessage,
            isExpanded: $isBottomContainerExpanded,
            attachedImages: $attachedImages,
            imageUploadsAllowed: imageUploadsAllowed,
            onSendMessage: {
                if editSystemMessage {
                    chat.systemMessage = newMessage
                    newMessage = ""
                    editSystemMessage = false
                    store.saveInCoreData()
                }
                else if !newMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    onSendMessage()
                }
            },
            onAddImage: onAddImage
        )
    }
}

#Preview {
    ChatInputView(
        chat: ChatEntity(),
        newMessage: .constant("Test message"),
        editSystemMessage: .constant(false),
        attachedImages: .constant([]),
        isBottomContainerExpanded: .constant(false),
        imageUploadsAllowed: true,
        onSendMessage: {},
        onAddImage: {}
    )
}