//
//  MessageCell.swift
//  macai
//
//  Created by Renat Notfullin on 25.03.2023.
//

import SwiftUI

struct MessageCell: View, Equatable {
    static func == (lhs: MessageCell, rhs: MessageCell) -> Bool {
        lhs.chat.id == rhs.chat.id &&
        lhs.timestamp == rhs.timestamp &&
        lhs.message == rhs.message &&
        lhs.showsAttentionIndicator == rhs.showsAttentionIndicator &&
        lhs.$isActive.wrappedValue == rhs.$isActive.wrappedValue &&
        lhs.chat.isPinned == rhs.chat.isPinned &&
        lhs.searchText == rhs.searchText
    }

    @ObservedObject var chat: ChatEntity
    @State var timestamp: Date
    var message: String
    let showsAttentionIndicator: Bool
    @Binding var isActive: Bool
    let viewContext: NSManagedObjectContext
    let searchText: String
    @State private var isHovered = false
    @Environment(\.colorScheme) var colorScheme


    
    private var filteredMessage: String {
        if !message.starts(with: "<think>") {
            return message
        }
        let messageWithoutNewlines = message.replacingOccurrences(of: "\n", with: " ")
        let messageWithoutThinking = messageWithoutNewlines.replacingOccurrences(
            of: "<think>.*?</think>",
            with: "",
            options: .regularExpression
        )
        return messageWithoutThinking.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Button {
            isActive = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if let personaName = chat.persona?.name {
                        HighlightedText(personaName, highlight: searchText, elementType: "chatlist")
                            .font(.caption)
                            .lineLimit(1)
                    }
                    else {
                        HighlightedText("No assistant selected", highlight: searchText, elementType: "chatlist")
                            .font(.caption)
                            .lineLimit(1)
                    }

                    if chat.name != "" {
                        HighlightedText(chat.name, highlight: searchText, elementType: "chatlist")
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    if filteredMessage != "" {
                        if message.starts(with: "<image-uuid>") {
                            Text("🖼️ Image")
                                .lineLimit(1)
                                .truncationMode(.tail)
                        } else {
                            HighlightedText(filteredMessage, highlight: searchText, elementType: "chatlist")
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
                .padding(8)
                Spacer()
                
                HStack(spacing: 6) {
                    if showsAttentionIndicator && !isActive {
                        ChatAttentionDot()
                    }

                    if chat.isPinned {
                        Image(systemName: "pin.fill")
                            .foregroundColor(self.isActive ? .white : .gray)
                            .font(.caption)
                    }
                }
                .padding(.trailing, 8)
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(self.isActive ? .white : .primary)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        self.isActive
                            ? Color.accentColor
                            : self.isHovered
                                ? (colorScheme == .dark ? Color(hex: "#666666")! : Color(hex: "#CCCCCC")!) : Color.clear
                    )
            )
            .onHover { hovering in
                isHovered = hovering
            }
        }
        .buttonStyle(.borderless)
        .background(Color.clear)
    }
}

struct MessageCell_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            MessageCell(
                chat: createPreviewChat(name: "Regular Chat"),
                timestamp: Date(),
                message: "Hello, how are you?",
                showsAttentionIndicator: false,
                isActive: .constant(false),
                viewContext: PersistenceController.preview.container.viewContext,
                searchText: ""
            )

            MessageCell(
                chat: createPreviewChat(name: "Selected Chat"),
                timestamp: Date(),
                message: "This is a selected chat preview",
                showsAttentionIndicator: false,
                isActive: .constant(true),
                viewContext: PersistenceController.preview.container.viewContext,
                searchText: ""
            )

            MessageCell(
                chat: createPreviewChat(name: "Long Message"),
                timestamp: Date(),
                message:
                    "This is a very long message that should be truncated when displayed in the preview cell of our chat application",
                showsAttentionIndicator: true,
                isActive: .constant(false),
                viewContext: PersistenceController.preview.container.viewContext,
                searchText: ""
            )
        }
        .previewLayout(.fixed(width: 300, height: 100))
    }

    static func createPreviewChat(name: String) -> ChatEntity {
        let context = PersistenceController.preview.container.viewContext
        let chat = ChatEntity(context: context)
        chat.id = UUID()
        chat.name = name
        chat.createdDate = Date()
        chat.updatedDate = Date()
        chat.systemMessage = AppConstants.chatGptSystemMessage
        chat.gptModel = AppConstants.defaultPrimaryModel
        chat.lastSequence = 0
        return chat
    }
}

private struct ChatAttentionDot: View {
    var body: some View {
        Circle()
            .fill(Color.accentColor)
            .frame(width: 6, height: 6)
            .shadow(color: Color.accentColor.opacity(0.3), radius: 1, x: 0, y: 0)
            .accessibilityLabel("New response")
    }
}
