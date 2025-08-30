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
    @State private var window: NSWindow?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        entity: ChatEntity.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \ChatEntity.updatedDate, ascending: false)]
    )
    private var chats: FetchedResults<ChatEntity>

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \APIServiceEntity.addedDate, ascending: false)])
    private var apiServices: FetchedResults<APIServiceEntity>

    @State var selectedChat: ChatEntity?
    @AppStorage("gptToken") var gptToken = ""
    @AppStorage("gptModel") var gptModel = AppConstants.chatGptDefaultModel
    @AppStorage("systemMessage") var systemMessage = AppConstants.chatGptSystemMessage
    @AppStorage("lastOpenedChatId") var lastOpenedChatId = ""
    @AppStorage("apiUrl") var apiUrl = AppConstants.apiUrlChatCompletions
    @AppStorage("defaultApiService") private var defaultApiServiceID: String?
    @StateObject private var previewStateManager = PreviewStateManager()

    @State private var windowRef: NSWindow?
    @State private var openedChatId: String? = nil
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var searchText = ""
    @State private var isSearchPresented = false

    var body: some View {
        NavigationSplitView {
            ChatListView(selectedChat: $selectedChat, searchText: $searchText)
                .navigationSplitViewColumnWidth(
                    min: 180,
                    ideal: 220,
                    max: 400
                )
        } detail: {
            HSplitView {
                if selectedChat != nil {
                    ChatView(viewContext: viewContext, chat: selectedChat!, searchText: $searchText)
                        .frame(minWidth: 400)
                        .id(openedChatId)
                }
                else {
                    WelcomeScreen(
                        chatsCount: chats.count,
                        apiServiceIsPresent: apiServices.count > 0,
                        customUrl: apiUrl != AppConstants.apiUrlChatCompletions,
                        openPreferencesView: openPreferencesView,
                        newChat: newChat
                    )
                }

                if previewStateManager.isPreviewVisible {
                    PreviewPane(stateManager: previewStateManager)
                }
            }
            .searchable(text: $searchText, isPresented: $isSearchPresented, placement: .toolbar, prompt: "Search in chat…")
            .onSubmit(of: .search) {
                // Handle Enter key in search field - go to next occurrence
                NotificationCenter.default.post(
                    name: NSNotification.Name("FindNext"),
                    object: nil
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ActivateSearch"))) { _ in
                // Remove focus from any text fields
                NSApp.keyWindow?.makeFirstResponder(nil)
                isSearchPresented = true
            }
            .onAppear {
                // Add global key monitor for Shift+Enter when search is active
                NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    if event.keyCode == 36 && event.modifierFlags.contains(.shift) && isSearchPresented && !searchText.isEmpty {
                        // Check if search field is focused by checking if any search-related view is first responder
                        if let firstResponder = NSApp.keyWindow?.firstResponder as? NSView,
                           String(describing: type(of: firstResponder)).contains("Search") {
                            NotificationCenter.default.post(
                                name: NSNotification.Name("FindPrevious"),
                                object: nil
                            )
                            return nil
                        }
                    }
                    return event
                }
            }
        }
        .onAppear(perform: {
            if let lastOpenedChatId = UUID(uuidString: lastOpenedChatId) {
                if let lastOpenedChat = chats.first(where: { $0.id == lastOpenedChatId }) {
                    selectedChat = lastOpenedChat
                }
            }
        })
        .background(WindowAccessor(window: $window))
        .onAppear {
            NotificationCenter.default.addObserver(
                forName: AppConstants.newChatNotification,
                object: nil,
                queue: .main
            ) { notification in
                let windowId = window?.windowNumber
                if let sourceWindowId = notification.userInfo?["windowId"] as? Int,
                    sourceWindowId == windowId
                {
                    newChat()
                }
            }
        }
        .navigationTitle("Chats")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Image("logo_\(selectedChat?.apiService?.type ?? "")")
                    .resizable()
                    .renderingMode(.template)
                    .interpolation(.high)
                    .frame(width: 16, height: 16)

                if let selectedChat = selectedChat {
                    Menu {
                        ForEach(apiServices, id: \.objectID) { apiService in
                            Button(action: {
                                selectedChat.apiService = apiService
                                handleServiceChange(selectedChat, apiService)
                            }) {
                                HStack {
                                    Text(apiService.name ?? "Unnamed API Service")
                                    if selectedChat.apiService == apiService {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }

                        Divider()

                        Text("Current Model: \(selectedChat.gptModel)")
                            .foregroundColor(.secondary)
                    } label: {
                        Text(selectedChat.apiService?.name ?? "Select API Service")
                    }
                }

                Button(action: {
                    isSearchPresented.toggle()
                }) {
                    Image(systemName: "magnifyingglass")
                }
                
                Button(action: {
                    newChat()
                }) {
                    Image(systemName: "square.and.pencil")
                }

                if #available(macOS 14.0, *) {
                    SettingsLink {
                        Image(systemName: "gear")
                    }
                }
                else {
                    Button(action: {
                        openPreferencesView()
                    }) {
                        Image(systemName: "gear")
                    }
                }
            }
        }

        .onChange(of: scenePhase) { phase in
            print("Scene phase changed: \(phase)")
            if phase == .inactive {
                print("Saving state...")
            }
        }
        .onChange(of: selectedChat) { newValue in
            if self.openedChatId != newValue?.id.uuidString {
                self.openedChatId = newValue?.id.uuidString
                previewStateManager.hidePreview()
            }
        }
        .environmentObject(previewStateManager)
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
        newChat.systemMessage = systemMessage
        newChat.gptModel = gptModel

        if let defaultServiceIDString = defaultApiServiceID,
            let url = URL(string: defaultServiceIDString),
            let objectID = viewContext.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: url)
        {

            do {
                let defaultService = try viewContext.existingObject(with: objectID) as? APIServiceEntity
                newChat.apiService = defaultService
                newChat.persona = defaultService?.defaultPersona
                // TODO: Refactor the following code along with ChatView.swift
                newChat.gptModel = defaultService?.model ?? AppConstants.chatGptDefaultModel
                newChat.systemMessage = newChat.persona?.systemMessage ?? AppConstants.chatGptSystemMessage
            }
            catch {
                print("Default API service not found: \(error)")
            }
        }

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
        if #available(macOS 13.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    private func getIndex(for chat: ChatEntity) -> Int {
        if let index = chats.firstIndex(where: { $0.id == chat.id }) {
            return index
        }
        else {
            fatalError("Chat not found in array")
        }
    }

    private func handleServiceChange(_ chat: ChatEntity, _ newService: APIServiceEntity) {
        if chat.messages.count == 0 {
            if let newDefaultPersona = newService.defaultPersona {
                chat.persona = newDefaultPersona
                if let newSystemMessage = chat.persona?.systemMessage,
                    !newSystemMessage.isEmpty
                {
                    chat.systemMessage = newSystemMessage
                }
            }
        }
        
        chat.apiService = newService
        chat.gptModel = newService.model ?? AppConstants.chatGptDefaultModel
        chat.objectWillChange.send()
        try? viewContext.save()

        NotificationCenter.default.post(
            name: NSNotification.Name("RecreateMessageManager"),
            object: nil,
            userInfo: ["chatId": chat.id]
        )
    }

}

struct PreviewPane: View {
    @ObservedObject var stateManager: PreviewStateManager
    @State private var isResizing = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("HTML Preview")
                    .font(.headline)
                Spacer()
                Button(action: { stateManager.hidePreview() }) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .frame(minWidth: 300)

            Divider()

            HTMLPreviewView(htmlContent: stateManager.previewContent)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    if !isResizing {
                        isResizing = true
                    }
                    let newWidth = max(300, stateManager.previewPaneWidth - gesture.translation.width)
                    stateManager.previewPaneWidth = min(800, newWidth)
                }
                .onEnded { _ in
                    isResizing = false
                }
        )
    }
}

struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            self.window = view.window
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
