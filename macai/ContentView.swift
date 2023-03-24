//
//  ContentView.swift
//  macai
//
//  Created by Renat Notfullin on 11.03.2023.
//


import Combine
import SwiftUI
import Foundation
import AppKit
import CoreData

extension String {
    func split(usingRegex pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }
        let nsString = self as NSString
        let matches = regex.matches(in: self, options: [], range: NSMakeRange(0, nsString.length))
        let ranges = matches.map { $0.range }
        var parts: [String] = []
        var start = 0
        for range in ranges {
            let part = nsString.substring(with: NSMakeRange(start, range.location - start))
            parts.append(part)
            start = range.location + range.length
        }
        let lastPart = nsString.substring(from: start)
        parts.append(lastPart)
        return parts
    }
}

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(entity: ChatEntity.entity(), sortDescriptors: [NSSortDescriptor(keyPath: \ChatEntity.createdDate, ascending: false)], animation: .default)
    private var chats: FetchedResults<ChatEntity>
    //@State var selection: Set<UUID> = []
    @State var selectedChat: ChatEntity?
    @AppStorage("gptToken") var gptToken = ""
   
    
    @State private var windowRef: NSWindow?
    
    let warmColors: [Color] = [.orange, .yellow, .white]
    let coldColors: [Color] = [.blue, .indigo, .cyan]
    let warmShadowColor: Color =  Color(red: 0.9, green: 0.5, blue: 0.0)
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
                        chat: chats[getIndex(for: chat)], timestamp: messageTimestamp,
                        message: .constant(messageBody), isActive: isActive // use .consant to pass binding value so it'll be updated in child view
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
            
            
            GeometryReader { geometry in
                
                ZStack {
                    // if new user, show beautiful welcome particles
                    if chats.count == 0 {
                        SceneKitParticlesView()
                            .edgesIgnoringSafeArea(.all)
                    }
                    
                    // if gptToken is not set, show button to open settings
                    if gptToken == "" {
                        
                        
                        
                        VStack {
                            RotatingIcon()
                            
                            VStack {
                                Text("Welcome to macai!").font(.title)
                                Text("To get started, please set ChatGPT API token in settings")
                                Button("Open Settings") {
                                    OpenPreferencesView()
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                        
                        
                        
                    } else {
                        //
                        VStack {
                            RotatingIcon()
                            
                            if chats.count == 0 {
                                Text("No chats were created yet. Create new one?")
                                Button("Create new chat") {
                                    newChat()
                                }
                            } else {
                                Text("Select chat to get started, or create new one")
                            }
                            
                            
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                    }
                    
                }
                
            }
            
        }
        .navigationTitle("Chats")
        .toolbar {
            // Button to hide and display Navigation List
            ToolbarItem(placement: .navigation) {
                Button(action: {
                    NSApp.keyWindow?.firstResponder?.tryToPerform(
                        #selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
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
                    OpenPreferencesView()
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
        } catch {
            print("Error saving new chat: \(error.localizedDescription)")
            viewContext.rollback()
        }
        

        
    }
    
    func OpenPreferencesView() {
        
        // handle previously opened window here somehow if needed
        if let curWindow = windowRef {
            curWindow.makeKeyAndOrderFront(nil)
            return
        }
        let w = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 450, height: 400),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        w.center()
        w.contentView = NSHostingView(rootView: PreferencesView())
        w.makeKeyAndOrderFront(nil)
        w.isReleasedWhenClosed = false  // <--- important
        windowRef = w
    }
    
    private func getIndex(for chat: ChatEntity) -> Int {
        if let index = chats.firstIndex(where: { $0.id == chat.id }) {
            return index
        } else {
            fatalError("Chat not found in array")
        }
    }

    // Delete chat from the list and confirm deletion
    func deleteChat(_ chat: ChatEntity) {
            // if selected chat will be deleted, remove selection
            //if selection == [chat.id] {
                //selection = []
            //}

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
                    } catch {
                        print("Error deleting chat: \(error.localizedDescription)")
                    }
                }


            }
        }
        
        
    }
}

struct RotatingIcon: View {
    @GestureState private var dragOffset = CGSize.zero
    
    var body: some View {
        let dragGesture = DragGesture(minimumDistance: 0)
            .updating($dragOffset) { value, state, transaction in
                state = value.translation
            }
        
        Image("WelcomeIcon")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 256, maxHeight: 256)
            .shadow(color: Color(red: 1, green: 0.853, blue: 0.281), radius: 15, x: -10, y: 10)
            .shadow(color: Color(red: 1, green: 0.593, blue: 0.261), radius: 15, x: 10, y: 15)
            .shadow(color: Color(red: 0.9, green: 0.5, blue: 0.0), radius: 38, x: 0, y: 20)
            .rotation3DEffect(
                Angle(degrees: Double(dragOffset.width / 20)),
                axis: (x: 0, y: 1, z: 0),
                anchor: .center,
                anchorZ: 0.0,
                perspective: 0.2
            )
            .rotation3DEffect(
                Angle(degrees: Double(-dragOffset.height / 20)),
                axis: (x: 1, y: 0, z: 0),
                anchor: .center,
                anchorZ: 0.0,
                perspective: 0.2
            )
            .gesture(dragGesture)
    }
}




//struct ContentView_Previews: PreviewProvider {
//    static var previews: some View {
//        let mockMessage1 = Message(id: 1, name: "User", body: "Hello, how are you?", timestamp: Date(), own: true)
//        let mockMessage2 = Message(id: 2, name: "ChatGPT", body: "I'm doing well, thank you! How can I help you today?", timestamp: Date(), own: false)
//
//        let mockChat = Chat(id: UUID(), messagePreview: mockMessage2, messages: [mockMessage1, mockMessage2], newChat: false)
//
//        let chats = [mockChat]
//
//        ContentView(chats: .constant([mockChat]))
//    }
//}
