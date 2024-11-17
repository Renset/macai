//
//  ChatListRow.swift
//  macai
//
//  Created by Renat on 17.11.2024.
//

import SwiftUI

struct ChatListRow: View {
    let chat: ChatEntity
    @Binding var selectedChat: ChatEntity?
    let viewContext: NSManagedObjectContext
    
    var isActive: Binding<Bool> {
        Binding<Bool>(
            get: { !chat.isDeleted && self.selectedChat?.id == chat.id },
            set: { newValue in
                if newValue {
                    selectedChat = chat
                } else if selectedChat?.id == chat.id {
                    selectedChat = nil
                }
            }
        )
    }
    
    var body: some View {
        MessageCell(
            chat: chat,
            timestamp: chat.lastMessage?.timestamp ?? Date(),
            message: chat.lastMessage?.body ?? "",
            isActive: isActive,
            viewContext: viewContext
        )
        .contextMenu {
            Button(action: { renameChat(chat) }) {
                Label("Rename", systemImage: "pencil")
            }
            Divider()
            Button(action: { deleteChat(chat) }) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    func deleteChat(_ chat: ChatEntity) {
        let alert = NSAlert()
        alert.messageText = "Delete chat?"
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
}
