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
        lhs.chat?.id == rhs.chat?.id &&
        lhs.chat?.updatedDate == rhs.chat?.updatedDate &&
        lhs.chat?.name == rhs.chat?.name &&
        lhs.chat?.lastMessage?.body == rhs.chat?.lastMessage?.body &&
        lhs.chat?.isPinned == rhs.chat?.isPinned &&
        (lhs.selectedChat?.id == rhs.selectedChat?.id)
    }
    let chat: ChatEntity?
    let chatID: UUID  // Store the ID separately
    @Binding var selectedChat: ChatEntity?
    let viewContext: NSManagedObjectContext
    @StateObject private var chatViewModel: ChatViewModel

    init(
        chat: ChatEntity?,
        selectedChat: Binding<ChatEntity?>,
        viewContext: NSManagedObjectContext
    ) {
        self.chat = chat
        self.chatID = chat?.id ?? UUID()
        self._selectedChat = selectedChat
        self.viewContext = viewContext
        self._chatViewModel = StateObject(wrappedValue: ChatViewModel(chat: chat!, viewContext: viewContext))
    }

    var isActive: Binding<Bool> {
        Binding<Bool>(
            get: {
                selectedChat?.id == chatID
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
            chat: chat!,
            timestamp: chat?.lastMessage?.timestamp ?? Date(),
            message: chat?.lastMessage?.body ?? "",
            isActive: isActive,
            viewContext: viewContext
        )
        .contextMenu {
            Button(action: { 
                togglePinChat(chat!) 
            }) {
                Label(chat!.isPinned ? "Unpin" : "Pin", systemImage: chat!.isPinned ? "pin.slash" : "pin")
            }
            
            Button(action: { renameChat(chat!) }) {
                Label("Rename", systemImage: "pencil")
            }
            if chat!.apiService?.generateChatNames ?? false {
                Button(action: {
                    chatViewModel.regenerateChatName()
                }) {
                    Label("Regenerate Name", systemImage: "arrow.clockwise")
                }
            }
            Button(action: { clearChat(chat!) }) {
                Label("Clear Chat", systemImage: "eraser")
            }
            Divider()
            Button(action: { deleteChat(chat!) }) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    func deleteChat(_ chat: ChatEntity) {
        let alert = NSAlert()
        alert.messageText = "Delete chat \(chat.name)?"
        alert.informativeText = "Are you sure you want to delete this chat?"
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        alert.beginSheetModal(for: NSApp.keyWindow!) { response in
            if response == .alertFirstButtonReturn {
                // Clear selectedChat to prevent accessing deleted item
                if selectedChat?.id == chat.id {
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
