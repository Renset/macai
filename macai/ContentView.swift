//
//  ContentView.swift
//  macai
//
//  Created by Renat Notfullin on 11.03.2023.
//

import AppKit
import Combine
import CoreData
import Foundation
import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        entity: ChatEntity.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \ChatEntity.createdDate, ascending: false)],
        animation: .default
    )
    private var chats: FetchedResults<ChatEntity>
    @State var selectedChat: ChatEntity?
    @AppStorage("gptToken") var gptToken = ""

    @State private var windowRef: NSWindow?

    let warmColors: [Color] = [.orange, .yellow, .white]
    let coldColors: [Color] = [.blue, .indigo, .cyan]
    let warmShadowColor: Color = Color(red: 0.9, green: 0.5, blue: 0.0)
    let particleCount = 50

    var body: some View {
        NavigationView {
            List {
                ForEach(chats, id: \.id) { chat in
                    let isActive = Binding(
                        get: { selectedChat == chat },
                        set: { newValue in
                            if newValue {
                                selectedChat = chat
                            }
                        }
                    )

                    let messagePreview = chat.messages.max(by: { $0.id < $1.id })
                    let messageTimestamp = messagePreview?.timestamp ?? Date()
                    let messageBody = messagePreview?.body ?? ""

                    MessageCell(
                        chat: chats[getIndex(for: chat)],
                        timestamp: messageTimestamp,
                        message: .constant(messageBody),
                        isActive: isActive
                    )
                    .contextMenu {
                        Button(action: {
                            deleteChat(chat)
                        }) {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .tag(chat.id)
                }
            }
            .listStyle(SidebarListStyle())
            .navigationTitle("Chats")

            WelcomeScreen(
                chatsCount: chats.count,
                gptTokenIsPresent: gptToken != "",
                openPreferencesView: openPreferencesView,
                newChat: newChat
            )

        }
        .navigationTitle("Chats")
        .toolbar {
            // Button to hide and display Navigation List
            ToolbarItem(placement: .navigation) {
                Button(action: {
                    NSApp.keyWindow?.firstResponder?.tryToPerform(
                        #selector(NSSplitViewController.toggleSidebar(_:)),
                        with: nil
                    )
                }) {
                    Image(systemName: "sidebar.left")
                }
            }

            // Button to add new chat
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    newChat()
                }) {
                    Image(systemName: "plus")
                }
            }

            // Button to change settings of the app
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    // Open Preferences View
                    openPreferencesView()
                }) {
                    Image(systemName: "gear")
                }
            }

        }
        .onChange(of: scenePhase) { phase in
            print("Scene phase changed: \(phase)")
            if phase == .inactive {
                print("Saving state...")
            }
        }
    }

    func newChat() {
        let uuid = UUID()
        let newChat = ChatEntity(context: viewContext)
        newChat.id = uuid
        newChat.newChat = true
        newChat.temperature = 0.8
        newChat.top_p = 1.0
        newChat.behavior = "default"
        newChat.newMessage = ""
        newChat.createdDate = Date()
        newChat.updatedDate = Date()

        do {
            try viewContext.save()
            selectedChat = newChat
        }
        catch {
            print("Error saving new chat: \(error.localizedDescription)")
            viewContext.rollback()
        }

    }

    func openPreferencesView() {

        // handle previously opened window here somehow if needed
        if let curWindow = windowRef {
            curWindow.makeKeyAndOrderFront(nil)
            return
        }
        let w = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 450, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.center()
        w.contentView = NSHostingView(rootView: PreferencesView())
        w.makeKeyAndOrderFront(nil)
        w.isReleasedWhenClosed = false  // <--- important
        windowRef = w
    }

    private func getIndex(for chat: ChatEntity) -> Int {
        if let index = chats.firstIndex(where: { $0.id == chat.id }) {
            return index
        }
        else {
            fatalError("Chat not found in array")
        }
    }

    // Delete chat from the list and confirm deletion
    func deleteChat(_ chat: ChatEntity) {
        let alert = NSAlert()
        alert.messageText = "Delete chat?"
        alert.informativeText = "Are you sure you want to delete this chat?"
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        alert.beginSheetModal(for: NSApp.keyWindow!) { response in
            if response == .alertFirstButtonReturn {
                selectedChat = nil
                DispatchQueue.main.async {
                    viewContext.delete(chat)
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
}
