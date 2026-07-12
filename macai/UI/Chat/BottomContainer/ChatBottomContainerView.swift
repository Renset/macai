//
//  ChatBottomContainerView.swift
//  macai
//
//  Created by Renat on 19.01.2025.
//
import SwiftUI

struct ChatBottomContainerView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \PersonaEntity.order, ascending: true)],
        predicate: NSPredicate(format: "apiService != nil"),
        animation: .default
    )
    private var assistants: FetchedResults<PersonaEntity>
    @ObservedObject var chat: ChatEntity
    @Binding var newMessage: String
    @Binding var isExpanded: Bool
    @Binding var attachedImages: [ImageAttachment]
    @Binding var attachedFiles: [DocumentAttachment]
    let isInferenceInProgress: Bool
    let isEditingSystemMessage: Bool
    var imageUploadsAllowed: Bool
    var pdfUploadsAllowed: Bool
    var imageGenerationSupported: Bool
    var onSendMessage: () -> Void
    var onExpandToggle: () -> Void
    var onAddImage: () -> Void
    var onAddFile: () -> Void
    var onStopInference: () -> Void
    var onCancelEdit: () -> Void
    var onExpandedStateChange: ((Bool) -> Void)?  // Add this line
    @State private var isMentionPickerPresented = false

    private var mentionQuery: String {
        guard newMessage.first == "@" else { return "" }
        return String(newMessage.dropFirst())
    }

    private var filteredMentionAssistants: [PersonaEntity] {
        guard !mentionQuery.isEmpty else { return Array(assistants) }
        return assistants.filter {
            ($0.name ?? "").localizedCaseInsensitiveContains(mentionQuery)
        }
    }

    init(
        chat: ChatEntity,
        newMessage: Binding<String>,
        isExpanded: Binding<Bool>,
        attachedImages: Binding<[ImageAttachment]> = .constant([]),
        attachedFiles: Binding<[DocumentAttachment]> = .constant([]),
        isInferenceInProgress: Bool = false,
        isEditingSystemMessage: Bool = false,
        imageUploadsAllowed: Bool = false,
        pdfUploadsAllowed: Bool = false,
        imageGenerationSupported: Bool = false,
        onSendMessage: @escaping () -> Void,
        onExpandToggle: @escaping () -> Void = {},
        onAddImage: @escaping () -> Void = {},
        onAddFile: @escaping () -> Void = {},
        onStopInference: @escaping () -> Void = {},
        onCancelEdit: @escaping () -> Void = {},
        onExpandedStateChange: ((Bool) -> Void)? = nil
    ) {
        self.chat = chat
        self._newMessage = newMessage
        self._isExpanded = isExpanded
        self._attachedImages = attachedImages
        self._attachedFiles = attachedFiles
        self.isInferenceInProgress = isInferenceInProgress
        self.isEditingSystemMessage = isEditingSystemMessage
        self.imageUploadsAllowed = imageUploadsAllowed
        self.pdfUploadsAllowed = pdfUploadsAllowed
        self.imageGenerationSupported = imageGenerationSupported
        self.onSendMessage = onSendMessage
        self.onExpandToggle = onExpandToggle
        self.onAddImage = onAddImage
        self.onAddFile = onAddFile
        self.onStopInference = onStopInference
        self.onCancelEdit = onCancelEdit
        self.onExpandedStateChange = onExpandedStateChange

        if chat.messagesArray.isEmpty {
            DispatchQueue.main.async {
                isExpanded.wrappedValue = true
            }
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
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
                        attachedImages: $attachedImages,
                        attachedFiles: $attachedFiles,
                        isInferenceInProgress: isInferenceInProgress,
                        isEditingSystemMessage: isEditingSystemMessage,
                        imageUploadsAllowed: imageUploadsAllowed,
                        pdfUploadsAllowed: pdfUploadsAllowed,
                        imageGenerationSupported: imageGenerationSupported,
                        onEnter: handleEnter,
                        onAddImage: onAddImage,
                        onAddFile: onAddFile,
                        onStopInference: onStopInference,
                        onCancelEdit: onCancelEdit
                    )
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .padding()
                    .popover(isPresented: $isMentionPickerPresented, arrowEdge: .bottom) {
                        AssistantMentionPicker(
                            assistants: filteredMentionAssistants,
                            onSelect: selectMentionAssistant
                        )
                    }
                }
                .border(width: 1, edges: [.top], color: Color(NSColor.windowBackgroundColor).opacity(0.8))
            }

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
            .offset(y: -16)
        }
        .onChange(of: newMessage) { _, value in
            updateMentionPresentation(for: value)
        }

    }

    private func updateMentionPresentation(for value: String) {
        let query = value.dropFirst()
        isMentionPickerPresented = !isEditingSystemMessage
            && value.first == "@"
            && !query.contains(where: { $0.isWhitespace })
    }

    private func handleEnter() {
        if isMentionPickerPresented {
            if let assistant = filteredMentionAssistants.first {
                selectMentionAssistant(assistant)
            }
            return
        }
        onSendMessage()
    }

    private func selectMentionAssistant(_ assistant: PersonaEntity) {
        PersonaSelectorView.updatePersonaAndSystemMessage(assistant, for: chat)
        newMessage = ""
        isMentionPickerPresented = false
    }
}

private struct AssistantMentionPicker: View {
    let assistants: [PersonaEntity]
    let onSelect: (PersonaEntity) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if assistants.isEmpty {
                ContentUnavailableView(
                    "No Assistants Found",
                    systemImage: "person.crop.circle.badge.questionmark"
                )
                .frame(width: 300, height: 120)
            } else {
                Text("Choose Assistant")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 6)

                ForEach(assistants.prefix(8), id: \.objectID) { assistant in
                    Button {
                        onSelect(assistant)
                    } label: {
                        HStack {
                            Circle()
                                .fill(Color(hex: assistant.color ?? AppConstants.defaultPersonaColor) ?? .accentColor)
                                .frame(width: 10, height: 10)
                            Text(assistant.name ?? "Untitled Assistant")
                            Spacer()
                            Text(assistant.apiService?.name ?? "")
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                }
            }
        }
        .padding(.vertical, 4)
        .frame(width: 320)
    }
}
