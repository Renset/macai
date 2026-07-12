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
    @State private var selectedMentionIndex = 0

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

    private var mentionCandidates: [PersonaEntity] {
        filteredMentionAssistants
    }

    private var mentionPickerLeadingOffset: CGFloat {
        imageUploadsAllowed || pdfUploadsAllowed ? 48 : 8
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
                        onCancelEdit: onCancelEdit,
                        onMoveUp: isMentionPickerPresented ? moveMentionSelectionUp : nil,
                        onMoveDown: isMentionPickerPresented ? moveMentionSelectionDown : nil,
                        onDismissSuggestions: isMentionPickerPresented ? dismissMentionPicker : nil
                    )
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .padding()
                    .overlay(alignment: .topLeading) {
                        if isMentionPickerPresented {
                            AssistantMentionPicker(
                                assistants: mentionCandidates,
                                selectedIndex: selectedMentionIndex,
                                onSelect: selectMentionAssistant
                            )
                                .alignmentGuide(.top) { dimensions in
                                    dimensions[.bottom] + 6
                                }
                                .offset(x: mentionPickerLeadingOffset)
                                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottomLeading)))
                        }
                    }
                    .zIndex(1)
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
        .animation(.easeOut(duration: 0.12), value: isMentionPickerPresented)

    }

    private func updateMentionPresentation(for value: String) {
        let query = value.dropFirst()
        isMentionPickerPresented = !isEditingSystemMessage
            && value.first == "@"
            && !query.contains(where: { $0.isWhitespace })
        selectedMentionIndex = 0
    }

    private func handleEnter() {
        if isMentionPickerPresented {
            if mentionCandidates.indices.contains(selectedMentionIndex) {
                let assistant = mentionCandidates[selectedMentionIndex]
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

    private func moveMentionSelectionUp() {
        guard isMentionPickerPresented, !mentionCandidates.isEmpty else { return }
        selectedMentionIndex = selectedMentionIndex == 0
            ? mentionCandidates.count - 1
            : selectedMentionIndex - 1
    }

    private func moveMentionSelectionDown() {
        guard isMentionPickerPresented, !mentionCandidates.isEmpty else { return }
        selectedMentionIndex = (selectedMentionIndex + 1) % mentionCandidates.count
    }

    private func dismissMentionPicker() {
        guard isMentionPickerPresented else {
            if isEditingSystemMessage { onCancelEdit() }
            return
        }
        isMentionPickerPresented = false
    }
}

private struct AssistantMentionPicker: View {
    let assistants: [PersonaEntity]
    let selectedIndex: Int
    let onSelect: (PersonaEntity) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if assistants.isEmpty {
                ContentUnavailableView(
                    "No Assistants Found",
                    systemImage: "person.crop.circle.badge.questionmark"
                )
                .frame(width: 232, height: 84)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(Array(assistants.enumerated()), id: \.element.objectID) { index, assistant in
                                AssistantMentionRow(
                                    assistant: assistant,
                                    isSelected: index == selectedIndex
                                ) {
                                    onSelect(assistant)
                                }
                                .id(assistant.objectID)
                            }
                        }
                        .padding(3)
                    }
                    .frame(maxHeight: 264)
                    .onChange(of: selectedIndex) { _, index in
                        guard assistants.indices.contains(index) else { return }
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(assistants[index].objectID, anchor: .center)
                        }
                    }
                }
            }
        }
        .padding(6)
        .frame(width: 280)
        .background(.regularMaterial, in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
    }
}

private struct AssistantMentionRow: View {
    let assistant: PersonaEntity
    let isSelected: Bool
    let action: () -> Void

    private var details: String {
        let service = assistant.apiService
        let model = assistant.model?.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveModel = model?.isEmpty == false
            ? (model ?? "")
            : AppConstants.defaultModel(for: service?.type)
        let serviceName = service?.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return serviceName.isEmpty ? effectiveModel : "\(effectiveModel) • \(serviceName)"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color(hex: assistant.color ?? AppConstants.defaultPersonaColor) ?? .accentColor)
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 1) {
                    Text(assistant.name ?? "Untitled Assistant")
                        .lineLimit(1)
                    Text(details)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if isSelected {
                    Image(systemName: "return")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(.rect)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(
                Color.accentColor.opacity(isSelected ? 0.16 : 0),
                in: .rect(cornerRadius: 6)
            )
        }
        .buttonStyle(.plain)
    }
}
