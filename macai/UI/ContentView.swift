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
    private static var handledStartChatRequestIds = Set<String>()
    private static var handledResponseIds = Set<String>()

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
    @AppStorage("gptModel") var gptModel = AppConstants.defaultPrimaryModel
    @AppStorage("systemMessage") var systemMessage = AppConstants.chatGptSystemMessage
    @AppStorage("lastOpenedChatId") var lastOpenedChatId = ""
    @AppStorage("apiUrl") var apiUrl = AppConstants.apiUrlOpenAIResponses
    @AppStorage(SettingsIndicatorKeys.generalSeen) private var generalSettingsSeen: Bool = false
    @StateObject private var previewStateManager = PreviewStateManager()
    @StateObject private var attentionStore = ChatAttentionStore.shared

    @State private var windowRef: NSWindow?
    @State private var openedChatId: String? = nil
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var lastChatCount = 0
    @State private var searchText = ""
    @State private var isSearchPresented = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ChatListView(selectedChat: $selectedChat, searchText: $searchText)
                .environmentObject(attentionStore)
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
                        customUrl: apiUrl != AppConstants.apiUrlOpenAIResponses,
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

                    // Cmd+Shift+Delete -> Clear currently selected chat
                    // keyCode 51 corresponds to the Delete (backspace) key on macOS keyboards
                    if event.keyCode == 51 && event.modifierFlags.contains(.command) && event.modifierFlags.contains(.shift) {
                        if selectedChat != nil {
                            clearSelectedChat()
                            return nil
                        }
                    }

                    return event
                }
            }
        }
        .onAppear(perform: {
            updateSidebarVisibilityForChatCount(previousCount: lastChatCount, newCount: chats.count)
            lastChatCount = chats.count
            if let lastOpenedChatId = UUID(uuidString: lastOpenedChatId) {
                if let lastOpenedChat = chats.first(where: { $0.id == lastOpenedChatId }) {
                    selectedChat = lastOpenedChat
                }
            }
        })
        .onChange(of: chats.count) { newCount in
            updateSidebarVisibilityForChatCount(previousCount: lastChatCount, newCount: newCount)
            lastChatCount = newCount
        }
        .background(WindowAccessor(window: $window))
        .onAppear {
            NotificationCenter.default.addObserver(
                forName: AppConstants.newChatNotification,
                object: nil,
                queue: .main
            ) { notification in
                let currentWindowId = window?.windowNumber
                let sourceWindowId = notification.userInfo?["windowId"] as? Int

                let shouldHandle: Bool
                if let sourceWindowId, sourceWindowId > 0 {
                    shouldHandle = sourceWindowId == currentWindowId
                }
                else {
                    shouldHandle = true
                }

                guard shouldHandle else { return }

                if let requestId = notification.userInfo?["requestId"] as? String {
                    if ContentView.handledStartChatRequestIds.contains(requestId) {
                        return
                    }
                    ContentView.handledStartChatRequestIds.insert(requestId)
                }

                if let uriString = notification.userInfo?["apiServiceURI"] as? String,
                   let service = apiService(fromURI: uriString)
                {
                    newChat(using: service)
                }
                else {
                    newChat()
                }
            }

            // Clear badge for selected chat when app becomes active
            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                if let selectedId = selectedChat?.id {
                    attentionStore.clear(selectedId)
                }
            }
        }
        .navigationTitle("Chats")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let selectedChatType = selectedChat?.apiService?.type {
                    Image("logo_\(selectedChatType)")
                        .resizable()
                        .renderingMode(.template)
                        .interpolation(.high)
                        .frame(width: 16, height: 16)
                        .padding(.horizontal, 12)
                }

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
                    newChat()
                }) {
                    Image(systemName: "square.and.pencil")
                }

                if #available(macOS 14.0, *) {
                    SettingsLink {
                        settingsGearIcon
                    }
                }
                else {
                    Button(action: {
                        openPreferencesView()
                    }) {
                        settingsGearIcon
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
            if let selectedId = newValue?.id {
                attentionStore.clear(selectedId)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ChatResponseCompleted"))) { notification in
            if let responseId = notification.userInfo?["responseId"] as? String {
                if ContentView.handledResponseIds.contains(responseId) {
                    return
                }
                ContentView.handledResponseIds.insert(responseId)
            }

            guard let chatId = notification.userInfo?["chatId"] as? UUID else { return }
            let isKeyWindow = window?.isKeyWindow ?? false
            let isActiveChat = selectedChat?.id == chatId
            let appIsActive = scenePhase == .active && NSApp.isActive

            if appIsActive && !isKeyWindow {
                return
            }

            if !isActiveChat || !appIsActive {
                attentionStore.mark(chatId)

                let chatName = chatDisplayName(
                    for: chatId,
                    fallback: notification.userInfo?["chatName"] as? String
                )
                let message = notification.userInfo?["message"] as? String ?? ""
                let body = notificationBody(from: message)
                NotificationPresenter.shared.scheduleNotification(
                    identifier: "chat-response-\(chatId.uuidString)-\(Date().timeIntervalSince1970)",
                    title: chatName,
                    body: body
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ClearChat"))) { _ in
            if selectedChat != nil {
                clearSelectedChat()
            }
        }
        .environmentObject(previewStateManager)
    }

    private var settingsGearIcon: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "gear")
            if SettingsIndicatorState.needsAttention(generalSeen: generalSettingsSeen) {
                SettingsIndicatorDot()
                    .offset(x: 1, y: -1)
            }
        }
    }

    func newChat() {
        newChat(using: nil)
    }

    private func newChat(using preferredService: APIServiceEntity?) {
        let uuid = UUID()
        let newChat = ChatEntity(context: viewContext)

        newChat.id = uuid
        newChat.newChat = true
        newChat.temperature = 1
        newChat.top_p = 1.0
        newChat.behavior = "default"
        newChat.draftMessage = ""
        newChat.createdDate = Date()
        newChat.updatedDate = Date()
        newChat.systemMessage = systemMessage
        newChat.gptModel = gptModel
        newChat.lastSequence = 0

        if let service = preferredService {
            newChat.apiService = service
            newChat.persona = service.defaultPersona
            newChat.gptModel = service.model ?? AppConstants.defaultModel(for: service.type)
            newChat.systemMessage = service.defaultPersona?.systemMessage ?? AppConstants.chatGptSystemMessage
        }
        else if let defaultService = resolveDefaultAPIService() {
            newChat.apiService = defaultService
            newChat.persona = defaultService.defaultPersona
            // TODO: Refactor the following code along with ChatView.swift
            newChat.gptModel = defaultService.model ?? AppConstants.defaultModel(for: defaultService.type)
            newChat.systemMessage = newChat.persona?.systemMessage ?? AppConstants.chatGptSystemMessage
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

    private func apiService(fromURI uriString: String) -> APIServiceEntity? {
        guard let url = URL(string: uriString),
              let objectID = viewContext.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: url)
        else {
            return nil
        }

        do {
            return try viewContext.existingObject(with: objectID) as? APIServiceEntity
        }
        catch {
            print("Failed to locate API service for URI \(uriString): \(error)")
            return nil
        }
    }

    private func resolveDefaultAPIService() -> APIServiceEntity? {
        if let service = apiServices.first(where: { $0.isDefault }) {
            return service
        }

        if let defaultServiceIDString = UserDefaults.standard.string(forKey: "defaultApiService"),
           let url = URL(string: defaultServiceIDString),
           let objectID = viewContext.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: url),
           let service = try? viewContext.existingObject(with: objectID) as? APIServiceEntity
        {
            service.isDefault = true
            viewContext.saveWithRetry(attempts: 1)
            UserDefaults.standard.removeObject(forKey: "defaultApiService")
            return service
        }

        return nil
    }

    func openPreferencesView() {
        if #available(macOS 13.0, *) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        else {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }

    func clearSelectedChat() {
        guard let chat = selectedChat else { return }
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

    private func getIndex(for chat: ChatEntity) -> Int {
        if let index = chats.firstIndex(where: { $0.id == chat.id }) {
            return index
        }
        else {
            fatalError("Chat not found in array")
        }
    }

    private func handleServiceChange(_ chat: ChatEntity, _ newService: APIServiceEntity) {
        if chat.messagesArray.isEmpty {
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
        chat.gptModel = newService.model ?? AppConstants.defaultModel(for: newService.type)
        chat.objectWillChange.send()
        try? viewContext.save()

        NotificationCenter.default.post(
            name: NSNotification.Name("RecreateMessageManager"),
            object: nil,
            userInfo: ["chatId": chat.id]
        )
    }

    private func updateSidebarVisibilityForChatCount(previousCount: Int, newCount: Int) {
        if newCount == 0 {
            columnVisibility = .detailOnly
            return
        }

        if previousCount == 0 && newCount > 0 {
            columnVisibility = .all
        }
    }
}

private extension ContentView {
    func chatDisplayName(for chatId: UUID, fallback: String?) -> String {
        if let chat = chats.first(where: { $0.id == chatId }) {
            if !chat.name.isEmpty {
                return chat.name
            }
            if let persona = chat.persona?.name, !persona.isEmpty {
                return persona
            }
        }
        if let fallback, !fallback.isEmpty {
            return fallback
        }
        return "Chat"
    }

    func notificationBody(from message: String) -> String {
        if message.isEmpty {
            return "Response finished"
        }

        let messageWithoutNewlines = message.replacingOccurrences(of: "\n", with: " ")
        let messageWithoutThinking = messageWithoutNewlines.replacingOccurrences(
            of: "<think>.*?</think>",
            with: "",
            options: .regularExpression
        )
        let trimmed = messageWithoutThinking.trimmingCharacters(in: .whitespacesAndNewlines)
        let maxLength = 160
        if trimmed.count > maxLength {
            let index = trimmed.index(trimmed.startIndex, offsetBy: maxLength)
            return String(trimmed[..<index]) + "…"
        }
        return trimmed
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
