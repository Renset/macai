//
//  ChatListRow.swift
//  macai
//
//  Created by Renat on 17.11.2024.
//

import CoreData
import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#endif

struct ChatListRow: View, Equatable {
    static func == (lhs: ChatListRow, rhs: ChatListRow) -> Bool {
        lhs.chat?.id == rhs.chat?.id &&
        lhs.chat?.updatedDate == rhs.chat?.updatedDate &&
        lhs.chat?.name == rhs.chat?.name &&
        lhs.chat?.lastMessage?.body == rhs.chat?.lastMessage?.body &&
        lhs.chat?.isPinned == rhs.chat?.isPinned &&
        lhs.showsAttentionIndicator == rhs.showsAttentionIndicator &&
        (lhs.selectedChat?.id == rhs.selectedChat?.id) &&
        lhs.searchText == rhs.searchText
    }
    let chat: ChatEntity?
    let chatID: UUID  // Store the ID separately
    let showsAttentionIndicator: Bool
    @Binding var selectedChat: ChatEntity?
    let viewContext: NSManagedObjectContext
    let searchText: String
    @StateObject private var chatViewModel: ChatViewModel
    @State private var isDeleteAlertPresented = false
    @State private var isClearAlertPresented = false
    @State private var isRenameAlertPresented = false
    @State private var renameText: String = ""

    init(
        chat: ChatEntity?,
        showsAttentionIndicator: Bool,
        selectedChat: Binding<ChatEntity?>,
        viewContext: NSManagedObjectContext,
        searchText: String
    ) {
        self.chat = chat
        self.chatID = chat?.id ?? UUID()
        self.showsAttentionIndicator = showsAttentionIndicator
        self._selectedChat = selectedChat
        self.viewContext = viewContext
        self.searchText = searchText
        self._chatViewModel = StateObject(wrappedValue: ChatViewModel(chat: chat!, viewContext: viewContext))
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
            chat: chat!,
            timestamp: chat?.lastMessage?.timestamp ?? Date(),
            message: chat?.lastMessage?.body ?? "",
            showsAttentionIndicator: showsAttentionIndicator,
            isActive: isActive,
            viewContext: viewContext,
            searchText: searchText
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
        #if os(iOS)
        .alert("Delete chat \(chat?.name ?? "")?", isPresented: $isDeleteAlertPresented) {
            Button("Delete", role: .destructive) {
                if let chat {
                    performDelete(chat)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this chat?")
        }
        .alert("Clear chat \(chat?.name ?? "")?", isPresented: $isClearAlertPresented) {
            Button("Clear", role: .destructive) {
                if let chat {
                    performClear(chat)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete all messages from this chat? Chat parameters will not be deleted.")
        }
        .alert("Rename chat", isPresented: $isRenameAlertPresented) {
            TextField("New name", text: $renameText)
            Button("Rename") {
                if let chat {
                    performRename(chat, newName: renameText)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter new name for this chat")
        }
        #endif
    }

    func deleteChat(_ chat: ChatEntity) {
        #if os(iOS)
        isDeleteAlertPresented = true
        return
        #endif
        #if os(macOS)
        let alert = NSAlert()
        alert.messageText = "Delete chat \(chat.name)?"
        alert.informativeText = "Are you sure you want to delete this chat?"
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        alert.beginSheetModal(for: NSApp.keyWindow!) { response in
            if response == .alertFirstButtonReturn {
                performDelete(chat)
            }
        }
        #endif
    }

    func renameChat(_ chat: ChatEntity) {
        #if os(iOS)
        renameText = chat.name
        isRenameAlertPresented = true
        return
        #endif
        #if os(macOS)
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
                performRename(chat, newName: textField.stringValue)
            }
        }
        #endif
    }
    
    func clearChat(_ chat: ChatEntity) {
        #if os(iOS)
        isClearAlertPresented = true
        return
        #endif
        #if os(macOS)
        let alert = NSAlert()
        alert.messageText = "Clear chat \(chat.name)?"
        alert.informativeText = "Are you sure you want to delete all messages from this chat? Chat parameters will not be deleted. This action cannot be undone."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        alert.beginSheetModal(for: NSApp.keyWindow!) { response in
            if response == .alertFirstButtonReturn {
                performClear(chat)
            }
        }
        #endif
    }
    
    func togglePinChat(_ chat: ChatEntity) {
        chat.isPinned.toggle()
        do {
            try viewContext.save()
        } catch {
            print("Error toggling pin status: \(error.localizedDescription)")
        }
    }

    private func performDelete(_ chat: ChatEntity) {
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

    private func performRename(_ chat: ChatEntity, newName: String) {
        chat.name = newName
        do {
            try viewContext.save()
        }
        catch {
            print("Error renaming chat: \(error.localizedDescription)")
        }
    }

    private func performClear(_ chat: ChatEntity) {
        chat.clearMessages()
        do {
            try viewContext.save()
        } catch {
            print("Error clearing chat: \(error.localizedDescription)")
        }
    }
}
