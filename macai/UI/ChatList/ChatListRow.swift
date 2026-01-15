//
//  ChatListRow.swift
//  macai
//
//  Created by Renat on 17.11.2024.
//

import CoreData
import Foundation
import SwiftUI

struct ChatListRow: View, Equatable {
    static func == (lhs: ChatListRow, rhs: ChatListRow) -> Bool {
        lhs.chatObjectID == rhs.chatObjectID &&
        lhs.updatedDate == rhs.updatedDate &&
        lhs.chatName == rhs.chatName &&
        lhs.lastMessageBody == rhs.lastMessageBody &&
        lhs.isPinned == rhs.isPinned &&
        lhs.showsAttentionIndicator == rhs.showsAttentionIndicator &&
        (lhs.selectedChat?.objectID == rhs.selectedChat?.objectID) &&
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
    @Binding var selectedChat: ChatEntity?
    let viewContext: NSManagedObjectContext
    let searchText: String
    @StateObject private var chatViewModel: ChatViewModel

    init(
        chat: ChatEntity,
        showsAttentionIndicator: Bool,
        selectedChat: Binding<ChatEntity?>,
        viewContext: NSManagedObjectContext,
        searchText: String
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
        self._selectedChat = selectedChat
        self.viewContext = viewContext
        self.searchText = searchText
        self._chatViewModel = StateObject(wrappedValue: ChatViewModel(chat: chat, viewContext: viewContext))
    }

    var isActive: Binding<Bool> {
        Binding<Bool>(
            get: {
                selectedChat == chat
            },
            set: { newValue in
                if newValue {
                    selectedChat = chat
                }
                else {
                    selectedChat = nil
                }
            }
        )
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
            searchText: searchText
        )
        .contextMenu {
            Button(action: { 
                togglePinChat(chat)
            }) {
                Label(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash" : "pin")
            }
            
            Button(action: { renameChat(chat) }) {
                Label("Rename", systemImage: "pencil")
            }
            if chat.apiService?.generateChatNames ?? false {
                Button(action: {
                    chatViewModel.regenerateChatName()
                }) {
                    Label("Regenerate Name", systemImage: "arrow.clockwise")
                }
            }
            Button(action: { clearChat(chat) }) {
                Label("Clear Chat", systemImage: "eraser")
            }
            Divider()
            Button(action: { deleteChat(chat) }) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    func deleteChat(_ chat: ChatEntity) {
        guard !chat.isDeleted else { return }
        let alert = NSAlert()
        alert.messageText = "Delete chat \(chat.name)?"
        alert.informativeText = "Are you sure you want to delete this chat?"
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        alert.beginSheetModal(for: NSApp.keyWindow!) { response in
            if response == .alertFirstButtonReturn {
                // Clear selectedChat to prevent accessing deleted item
                if selectedChat?.objectID == chat.objectID {
                    selectedChat = nil
                }
                viewContext.delete(chat)
                DispatchQueue.main.async {
                    do {
                        try viewContext.save()
                    }
                    catch {
                        print("Error deleting chat: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    func renameChat(_ chat: ChatEntity) {
        let alert = NSAlert()
        alert.messageText = "Rename chat"
        alert.informativeText = "Enter new name for this chat"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .informational
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        textField.stringValue = chat.name
        alert.accessoryView = textField
        alert.beginSheetModal(for: NSApp.keyWindow!) { response in
            if response == .alertFirstButtonReturn {
                chat.name = textField.stringValue
                do {
                    try viewContext.save()
                }

                catch {
                    print("Error renaming chat: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func clearChat(_ chat: ChatEntity) {
        let alert = NSAlert()
        alert.messageText = "Clear chat \(chat.name)?"
        alert.informativeText = "Are you sure you want to delete all messages from this chat? Chat parameters will not be deleted. This action cannot be undone."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        alert.beginSheetModal(for: NSApp.keyWindow!) { response in
            if response == .alertFirstButtonReturn {
                chat.clearMessages()
                do {
                    try viewContext.save()
                } catch {
                    print("Error clearing chat: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func togglePinChat(_ chat: ChatEntity) {
        chat.isPinned.toggle()
        do {
            try viewContext.save()
        } catch {
            print("Error toggling pin status: \(error.localizedDescription)")
        }
    }
}
