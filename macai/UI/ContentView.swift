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
    @Environment(\.openSettings) private var openSettings

    @FetchRequest(
        entity: ChatEntity.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \ChatEntity.updatedDate, ascending: false)]
    )
    private var chats: FetchedResults<ChatEntity>

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \APIServiceEntity.addedDate, ascending: false)])
    private var apiServices: FetchedResults<APIServiceEntity>

    @State var selectedChat: ChatEntity?
    @AppStorage("lastOpenedChatId") var lastOpenedChatId = ""
    @AppStorage("apiUrl") var apiUrl = AppConstants.apiUrlOpenAIResponses
    @AppStorage(SettingsIndicatorKeys.generalSeen) private var generalSettingsSeen: Bool = false
    @AppStorage(AppConstants.assistantSettingsMigrationNoticePendingKey)
    private var isAssistantMigrationNoticePending = false
    @State private var isAssistantMigrationNoticePresented = false
    @State private var didEvaluateAssistantMigrationNotice = false
    @StateObject private var previewStateManager = PreviewStateManager()
    @StateObject private var attentionStore = ChatAttentionStore.shared

    @State private var windowRef: NSWindow?
    @State private var openedChatId: String? = nil
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var lastChatCount = 0
    @State private var searchText = ""
    @State private var isSearchPresented = false
    @State private var isAssistantPickerPresented = false
    @State private var isChatSelectionMode = false
    @State private var keyDownMonitor: Any?
    @AppStorage("assistantPanelVisible") private var assistantPanelVisible = false
    @AppStorage("chatSettingsPanelWidth") private var chatSettingsPanelWidth: Double = 320
    @State private var panelDragStartWidth: Double?
    private static let chatSettingsPanelMinWidth: Double = 220
    private static let chatSettingsPanelMaxWidth: Double = 560
    private var isSidebarVisible: Bool { columnVisibility != .detailOnly }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            primaryColumn
        } detail: {
            detailColumn
        }
        .onAppear(perform: {
            updateSidebarVisibilityForChatCount(previousCount: lastChatCount, newCount: chats.count)
            lastChatCount = chats.count
            if !didEvaluateAssistantMigrationNotice {
                didEvaluateAssistantMigrationNotice = true
                isAssistantMigrationNoticePresented = isAssistantMigrationNoticePending
            }
            if let lastOpenedChatId = UUID(uuidString: lastOpenedChatId) {
                if let lastOpenedChat = chats.first(where: { $0.id == lastOpenedChatId }) {
                    selectedChat = lastOpenedChat
                }
            }
        })
        .onChange(of: chats.count) { _, newCount in
            updateSidebarVisibilityForChatCount(previousCount: lastChatCount, newCount: newCount)
            lastChatCount = newCount
        }
        .background(WindowAccessor(window: $window))
        .onChange(of: window) { _, _ in
            scheduleToolbarReorder()
        }
        .onChange(of: columnVisibility) { _, _ in
            // Toolbar contents rebuild when the sidebar toggles; re-assert order.
            scheduleToolbarReorder()
        }
        .onChange(of: isSearchPresented) { _, isPresented in
            if isPresented {
                // The system search item is inserted asynchronously when the
                // modifier appears, so re-apply the toolbar order afterwards.
                scheduleToolbarReorder()
            }
            else {
                // A collapsed search should leave the chat unfiltered and show
                // only the magnifying-glass button again.
                searchText = ""
            }
        }
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
        .alert("Review your v3 settings", isPresented: $isAssistantMigrationNoticePresented) {
            Button("Open Settings") {
                isAssistantMigrationNoticePending = false
                UserDefaults.standard.set(1, forKey: AppConstants.selectedPreferencesTabKey)
                openPreferencesView()
            }
            Button("Later", role: .cancel) {}
        } message: {
            Text(
                "API Services now only define how macai connects to an API. "
                    + "Models, system instructions, and chat behavior have moved to AI Assistants. "
                    + "Your existing settings were migrated automatically, but we recommend reviewing both your "
                    + "API Services and AI Assistants."
            )
        }
        .toolbar {
            if !isSidebarVisible {
                ToolbarItem(placement: .navigation) {
                    Button(action: {
                        newChat()
                    }) {
                        Label("New Chat", systemImage: "square.and.pencil")
                    }
                    .labelStyle(.iconOnly)
                }
            }

            if !isSearchPresented {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        isSearchPresented = true
                    }) {
                        Label("Find in Chat", systemImage: "magnifyingglass")
                    }
                    .labelStyle(.iconOnly)
                    .help("Find in Chat (⌘F)")
                }
            }

            // A single persistent toggle: toolbar items contributed by inspector
            // content linger after dismissal (stale duplicate button), so the
            // button stays in the main toolbar in both states.
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    assistantPanelVisible.toggle()
                }) {
                    // The label doubles as the NSToolbar identity used by
                    // moveChatSettingsToggleAfterSearch — keep them in sync.
                    Label(ContentView.chatSettingsToolbarLabel, systemImage: "sidebar.trailing")
                }
                .labelStyle(.iconOnly)
                .help(assistantPanelVisible ? "Hide chat settings" : "Show chat settings")
            }
        }
        .onChange(of: scenePhase) { _, phase in
            print("Scene phase changed: \(phase)")
            if phase == .inactive {
                print("Saving state...")
            }
        }
        .onChange(of: selectedChat) { _, newValue in
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
        .onReceive(NotificationCenter.default.publisher(for: AppConstants.exportChatNotification)) { notification in
            guard let chat = selectedChat else { return }
            let rawFormat = notification.userInfo?["format"] as? String
            let format = rawFormat.flatMap(ChatExportFormat.init(rawValue:)) ?? .markdown
            ChatExporter.exportWithSavePanel(chat: chat, format: format)
        }
        .onReceive(NotificationCenter.default.publisher(for: AppConstants.selectAssistantNotification)) { notification in
            let sourceWindowId = notification.userInfo?["windowId"] as? Int
            guard sourceWindowId == nil || sourceWindowId == 0 || sourceWindowId == window?.windowNumber else { return }
            isAssistantPickerPresented = true
        }
        .sheet(isPresented: $isAssistantPickerPresented) {
            AssistantQuickPicker { assistant in
                newChat(using: assistant)
            }
            .environment(\.managedObjectContext, viewContext)
        }
        .focusedSceneValue(\.chatIsSelected, selectedChat != nil)
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
        guard let assistant = resolveAssistant(for: preferredService) else {
            UserDefaults.standard.set(2, forKey: AppConstants.selectedPreferencesTabKey)
            openPreferencesView()
            return
        }
        newChat(using: assistant)
    }

    private func newChat(using assistant: PersonaEntity) {
        guard let service = assistant.apiService else { return }
        let newChat = ChatEntity(context: viewContext)
        newChat.id = UUID()
        newChat.newChat = true
        newChat.temperature = 1
        newChat.top_p = 1.0
        newChat.behavior = "default"
        newChat.draftMessage = ""
        newChat.createdDate = Date()
        newChat.updatedDate = Date()
        newChat.systemMessage = assistant.systemMessage ?? AppConstants.chatGptSystemMessage
        let model = assistant.model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        newChat.gptModel = model.isEmpty ? AppConstants.defaultModel(for: service.type) : model
        newChat.lastSequence = 0
        newChat.persona = assistant
        newChat.apiService = service

        do {
            try viewContext.save()
            selectedChat = newChat
        } catch {
            viewContext.rollback()
            print("Error saving new chat: \(error.localizedDescription)")
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

    private func resolveAssistant(for preferredService: APIServiceEntity?) -> PersonaEntity? {
        try? PersonaEntity.preferredAssistant(in: viewContext, for: preferredService)
    }

    func openPreferencesView() {
        openSettings()
    }

    func clearSelectedChat() {
        guard let chat = selectedChat else { return }
        let alert = NSAlert()
        alert.messageText = "Clear chat \(chat.name)?"
        alert.informativeText = "Are you sure you want to delete all messages from this chat? Chat parameters will not be deleted. This action cannot be undone."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        alert.presentAsSheetOrModal { response in
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

    private var primaryColumn: some View {
        ChatListView(
            selectedChat: $selectedChat,
            searchText: $searchText,
            isSelectionMode: $isChatSelectionMode
        )
            .environmentObject(attentionStore)
            .navigationSplitViewColumnWidth(
                min: 180,
                ideal: 220,
                max: 400
            )
            .toolbar {
                if isSidebarVisible {
                    ToolbarItem(placement: .navigation) {
                        Button(action: {
                            newChat()
                        }) {
                            Label("New Chat", systemImage: "square.and.pencil")
                        }
                        .labelStyle(.iconOnly)
                        .help("New Chat")
                    }

                    ToolbarItem(placement: .navigation) {
                        Button {
                            isChatSelectionMode.toggle()
                        } label: {
                            if isChatSelectionMode {
                                Text("Done")
                            }
                            else {
                                Label("Select Chats", systemImage: "checkmark.circle")
                                    .labelStyle(.iconOnly)
                            }
                        }
                        .help(isChatSelectionMode ? "Finish Selecting" : "Select Chats")
                        .disabled(chats.isEmpty)
                    }
                }
            }
    }

    @ViewBuilder
    private var detailColumn: some View {
        HStack(spacing: 0) {
            chatContent

            if assistantPanelVisible {
                chatSettingsPanel
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: assistantPanelVisible)
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ActivateSearch"))) { _ in
            // Remove focus from any text fields
            NSApp.keyWindow?.makeFirstResponder(nil)
            isSearchPresented = true
        }
        .onAppear {
            // Install the key monitor once; re-appearing must not stack duplicates.
            guard keyDownMonitor == nil else { return }
            keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
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

    @ViewBuilder
    private var chatContent: some View {
        // The searchable modifier lives on an invisible background anchor, not
        // on the chat itself: wrapping chatContentBase in a conditional would
        // change its view identity on every search toggle and recreate the
        // whole ChatView (message reload, scroll reset, broken Stop while
        // streaming). Toggling the anchor only recreates a Color.clear.
        chatContentBase
            .background {
                if isSearchPresented {
                    Color.clear
                        .searchable(
                            text: $searchText,
                            isPresented: $isSearchPresented,
                            placement: .toolbar,
                            prompt: "Search"
                        )
                        .onSubmit(of: .search) {
                            if !searchText.isEmpty {
                                NotificationCenter.default.post(
                                    name: NSNotification.Name("FindNext"),
                                    object: nil
                                )
                            }
                        }
                }
            }
    }

    @ViewBuilder
    private var chatContentBase: some View {
        HSplitView {
            if let selectedChat {
                // GeometryReader is load-bearing: it is the only container
                // whose reported minimum width is truly 0, cutting off the
                // large natural minimums of the chat content (text views,
                // input bar) so they never inflate the window's minimum
                // size. The outer frame then sets the real floor.
                GeometryReader { _ in
                    ChatView(
                        viewContext: viewContext,
                        chat: selectedChat,
                        searchText: $searchText,
                        isSearchPresented: $isSearchPresented
                    )
                }
                .frame(minWidth: 150, maxWidth: .infinity)
                .id(openedChatId)
            } else {
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
    }

    /// SwiftUI always renders the `.searchable` toolbar field as the
    /// trailing-most item, but the Chat Settings toggle belongs at the trailing
    /// edge, right above the panel it controls (Xcode-style). SwiftUI offers no
    /// ordering control here, so reorder the NSToolbar directly: move our
    /// toggle (the only custom item after the split-view separator) behind the
    /// search field.
    /// The toolbar is populated asynchronously after the window appears and
    /// after SwiftUI toolbar updates; retry a few times. The reorder itself is
    /// idempotent (no-op once the toggle sits behind the search field).
    private func scheduleToolbarReorder() {
        for delay in [0.2, 1.0, 2.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                moveChatSettingsToggleAfterSearch()
            }
        }
    }

    /// Reacts to SwiftUI inserting/removing toolbar items (e.g. the search
    /// field appearing when search is activated) and re-asserts the order
    /// within the same runloop turn — before the next frame is drawn — so the
    /// wrong order is never visible. The timer-based retries above remain as a
    /// startup fallback only.
    private func installToolbarObserverIfNeeded(_ toolbar: NSToolbar) {
        guard ContentView.observedToolbars.contains(ObjectIdentifier(toolbar)) == false else { return }
        ContentView.observedToolbars.insert(ObjectIdentifier(toolbar))

        let reorder: (Notification) -> Void = { [weak toolbar] _ in
            DispatchQueue.main.async {
                guard let toolbar else { return }
                Self.moveChatSettingsToggleAfterSearch(in: toolbar)
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSToolbar.willAddItemNotification, object: toolbar, queue: .main, using: reorder
        )
        NotificationCenter.default.addObserver(
            forName: NSToolbar.didRemoveItemNotification, object: toolbar, queue: .main, using: reorder
        )
    }

    private static var observedToolbars = Set<ObjectIdentifier>()

    private func moveChatSettingsToggleAfterSearch() {
        guard let toolbar = window?.toolbar else { return }
        installToolbarObserverIfNeeded(toolbar)
        Self.moveChatSettingsToggleAfterSearch(in: toolbar)
    }

    static let chatSettingsToolbarLabel = "Chat Settings"

    private static func moveChatSettingsToggleAfterSearch(in toolbar: NSToolbar) {
        // Identified by label: SwiftUI assigns random UUID identifiers to its
        // toolbar items, and position heuristics break when the search field
        // or the magnifier button get re-inserted at the end.
        guard let buttonIndex = toolbar.items.lastIndex(where: { $0.label == chatSettingsToolbarLabel }) else {
            return
        }
        guard buttonIndex != toolbar.items.count - 1 else { return }

        let buttonID = toolbar.items[buttonIndex].itemIdentifier
        toolbar.removeItem(at: buttonIndex)
        toolbar.insertItem(withItemIdentifier: buttonID, at: toolbar.items.count)
    }

    /// Custom trailing panel: the native `.inspector` freezes the window's
    /// minimum size at its current width on macOS 26 (verified empirically in
    /// every configuration), and an HSplitView pane cannot animate. A plain
    /// HStack with a draggable edge gives inspector-like behavior with none of
    /// the window-sizing side effects.
    private var chatSettingsPanel: some View {
        HStack(spacing: 0) {
            panelResizeHandle

            Group {
                if let selectedChat {
                    ChatSettingsView(
                        chat: selectedChat,
                        onServiceChange: { service in
                            handleServiceChange(selectedChat, service)
                        }
                    )
                } else {
                    VStack {
                        Text("Select a chat to see its settings.")
                            .foregroundStyle(.secondary)
                            .padding()
                        Spacer()
                    }
                }
            }
            // min lets the window squeeze the panel; max caps it at the width
            // the user chose by dragging the handle.
            .frame(
                minWidth: Self.chatSettingsPanelMinWidth,
                idealWidth: chatSettingsPanelWidth,
                maxWidth: chatSettingsPanelWidth
            )
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var panelResizeHandle: some View {
        Rectangle()
            .fill(Color(NSColor.separatorColor))
            .frame(width: 1)
            .overlay(
                // Invisible widened hit area for comfortable dragging.
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                let start = panelDragStartWidth ?? chatSettingsPanelWidth
                                panelDragStartWidth = start
                                let proposed = start - value.translation.width
                                chatSettingsPanelWidth = min(
                                    max(proposed, Self.chatSettingsPanelMinWidth),
                                    Self.chatSettingsPanelMaxWidth
                                )
                            }
                            .onEnded { _ in
                                panelDragStartWidth = nil
                            }
                    )
                    .onHover { hovering in
                        if hovering {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
            )
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
        // Per-chat setting: only this chat switches service; the assistant
        // (and every other chat using it) is untouched.
        let currentModel = chat.effectiveModel.trimmingCharacters(in: .whitespacesAndNewlines)
        chat.apiService = newService
        chat.apiServiceOverridden = true

        // Keep the chat's model only when we know the new service offers it;
        // otherwise fall back to the service default.
        let knownModels = newService.id.flatMap { ModelsCache.shared.models(for: $0) } ?? []
        if currentModel.isEmpty || !knownModels.contains(currentModel) {
            chat.gptModel = AppConstants.defaultModel(for: newService.type)
        } else {
            chat.gptModel = currentModel
        }
        chat.modelOverridden = true

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

private struct AssistantQuickPicker: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \PersonaEntity.order, ascending: true)],
        predicate: NSPredicate(format: "apiService != nil"),
        animation: .default
    )
    private var assistants: FetchedResults<PersonaEntity>
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection: NSManagedObjectID?
    @FocusState private var searchIsFocused: Bool
    let onSelect: (PersonaEntity) -> Void

    private var filteredAssistants: [PersonaEntity] {
        guard !query.isEmpty else { return Array(assistants) }
        return assistants.filter { ($0.name ?? "").localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 12) {
            TextField("Search assistants", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($searchIsFocused)

            List(filteredAssistants, selection: $selection) { assistant in
                HStack {
                    Circle()
                        .fill(Color(hex: assistant.color ?? AppConstants.defaultPersonaColor) ?? .accentColor)
                        .frame(width: 10, height: 10)
                    Text(assistant.name ?? "Untitled Assistant")
                    Spacer()
                    Text(assistant.apiService?.name ?? "")
                        .foregroundStyle(.secondary)
                }
                .tag(assistant.objectID)
                .contentShape(.rect)
                .onTapGesture(count: 2) { choose(assistant) }
            }
            .frame(minHeight: 220)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create Chat") { chooseSelected() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedAssistant == nil)
            }
        }
        .padding(16)
        .frame(width: 440)
        .onAppear {
            selection = filteredAssistants.first?.objectID
            searchIsFocused = true
        }
        .onChange(of: query) { _, _ in
            selection = filteredAssistants.first?.objectID
        }
    }

    private var selectedAssistant: PersonaEntity? {
        filteredAssistants.first { $0.objectID == selection }
    }

    private func chooseSelected() {
        guard let selectedAssistant else { return }
        choose(selectedAssistant)
    }

    private func choose(_ assistant: PersonaEntity) {
        onSelect(assistant)
        dismiss()
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
