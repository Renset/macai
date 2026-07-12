//
//  ChatListRow.swift
//  macai
//
//  Created by Renat on 17.11.2024.
//

import CoreData
import SwiftUI

enum ChatListRowAction {
    case beginSelection
    case togglePin
    case rename
    case regenerateName
    case clear
    case export(ChatExportFormat)
    case delete
}

struct ChatListRow: View, Equatable {
    static func == (lhs: ChatListRow, rhs: ChatListRow) -> Bool {
        lhs.chatObjectID == rhs.chatObjectID &&
        lhs.updatedDate == rhs.updatedDate &&
        lhs.chatName == rhs.chatName &&
        lhs.lastMessageBody == rhs.lastMessageBody &&
        lhs.isPinned == rhs.isPinned &&
        lhs.showsAttentionIndicator == rhs.showsAttentionIndicator &&
        lhs.isActive == rhs.isActive &&
        lhs.isSelectionMode == rhs.isSelectionMode &&
        lhs.isBulkSelected == rhs.isBulkSelected &&
        lhs.searchText == rhs.searchText
    }
    let chat: ChatEntity
    let chatObjectID: NSManagedObjectID
    let personaName: String?
    let chatName: String
    let isPinned: Bool
    let lastMessageBody: String
    let lastMessageTimestamp: Date
    let updatedDate: Date?
    let showsAttentionIndicator: Bool
    let isActive: Bool
    let isSelectionMode: Bool
    let isBulkSelected: Bool
    let searchText: String
    let onActivate: () -> Void
    let onAction: (ChatListRowAction) -> Void

    init(
        chat: ChatEntity,
        showsAttentionIndicator: Bool,
        isActive: Bool,
        isSelectionMode: Bool,
        isBulkSelected: Bool,
        searchText: String,
        onActivate: @escaping () -> Void,
        onAction: @escaping (ChatListRowAction) -> Void
    ) {
        self.chat = chat
        self.chatObjectID = chat.objectID
        self.personaName = chat.persona?.name
        self.chatName = chat.name
        self.isPinned = chat.isPinned
        self.lastMessageBody = chat.lastMessage?.body ?? ""
        self.lastMessageTimestamp = chat.lastMessage?.timestamp ?? .distantPast
        self.updatedDate = chat.updatedDate
        self.showsAttentionIndicator = showsAttentionIndicator
        self.isActive = isActive
        self.isSelectionMode = isSelectionMode
        self.isBulkSelected = isBulkSelected
        self.searchText = searchText
        self.onActivate = onActivate
        self.onAction = onAction
    }

    var body: some View {
        MessageCell(
            chatObjectID: chatObjectID,
            personaName: personaName,
            chatName: chatName,
            timestamp: lastMessageTimestamp,
            message: lastMessageBody,
            showsAttentionIndicator: showsAttentionIndicator,
            isPinned: isPinned,
            isActive: isActive,
            isSelectionMode: isSelectionMode,
            isBulkSelected: isBulkSelected,
            searchText: searchText,
            onActivate: onActivate
        )
        .contextMenu {
            Button(action: { onAction(.beginSelection) }) {
                Label("Select", systemImage: "checkmark.circle")
            }

            Divider()

            Button(action: { onAction(.togglePin) }) {
                Label(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash" : "pin")
            }
            
            Button(action: { onAction(.rename) }) {
                Label("Rename", systemImage: "pencil")
            }
            if chat.shouldGenerateChatNames {
                Button(action: { onAction(.regenerateName) }) {
                    Label("Regenerate Name", systemImage: "arrow.clockwise")
                }
            }
            Button(action: { onAction(.clear) }) {
                Label("Clear Chat", systemImage: "eraser")
            }
            Menu {
                Button("As Markdown…") {
                    onAction(.export(.markdown))
                }
                Button("As Plain Text…") {
                    onAction(.export(.plainText))
                }
            } label: {
                Label("Export Chat", systemImage: "square.and.arrow.up")
            }
            Divider()
            Button(action: { onAction(.delete) }) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
