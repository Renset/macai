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
    let isInferenceInProgress: Bool
    
    let imageUploadsAllowed: Bool
    let imageGenerationSupported: Bool
    let onSendMessage: () -> Void
    let onAddImage: () -> Void
    let onStopInference: () -> Void
    
    @StateObject private var store = ChatStore(persistenceController: PersistenceController.shared)
    
    var body: some View {
        ChatBottomContainerView(
            chat: chat,
            newMessage: $newMessage,
            isExpanded: $isBottomContainerExpanded,
            attachedImages: $attachedImages,
            isInferenceInProgress: isInferenceInProgress,
            imageUploadsAllowed: imageUploadsAllowed,
            imageGenerationSupported: imageGenerationSupported,
            onSendMessage: {
                if editSystemMessage {
                    chat.systemMessage = newMessage
                    newMessage = ""
                    editSystemMessage = false
                    store.saveInCoreData()
                }
                else if !isInferenceInProgress,
                        !newMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    onSendMessage()
                }
            },
            onAddImage: onAddImage,
            onStopInference: onStopInference
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
        isInferenceInProgress: false,
        imageUploadsAllowed: true,
        imageGenerationSupported: true,
        onSendMessage: {},
        onAddImage: {},
        onStopInference: {}
    )
}
