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
    @Binding var attachedFiles: [DocumentAttachment]
    @Binding var isBottomContainerExpanded: Bool
    let isInferenceInProgress: Bool
    
    let imageUploadsAllowed: Bool
    let pdfUploadsAllowed: Bool
    let imageGenerationSupported: Bool
    let onSendMessage: () -> Void
    let onAddImage: () -> Void
    let onAddFile: () -> Void
    let onStopInference: () -> Void
    let onCancelSystemMessageEdit: () -> Void
    
    @StateObject private var store = ChatStore(persistenceController: PersistenceController.shared)
    
    var body: some View {
        ChatBottomContainerView(
            chat: chat,
            newMessage: $newMessage,
            isExpanded: $isBottomContainerExpanded,
            attachedImages: $attachedImages,
            attachedFiles: $attachedFiles,
            isInferenceInProgress: isInferenceInProgress,
            isEditingSystemMessage: editSystemMessage,
            imageUploadsAllowed: imageUploadsAllowed,
            pdfUploadsAllowed: pdfUploadsAllowed,
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
            onAddFile: onAddFile,
            onStopInference: onStopInference,
            onCancelEdit: onCancelSystemMessageEdit
        )
    }
}

#Preview {
    ChatInputView(
        chat: ChatEntity(),
        newMessage: .constant("Test message"),
        editSystemMessage: .constant(false),
        attachedImages: .constant([]),
        attachedFiles: .constant([]),
        isBottomContainerExpanded: .constant(false),
        isInferenceInProgress: false,
        imageUploadsAllowed: true,
        pdfUploadsAllowed: true,
        imageGenerationSupported: true,
        onSendMessage: {},
        onAddImage: {},
        onAddFile: {},
        onStopInference: {},
        onCancelSystemMessageEdit: {}
    )
}
