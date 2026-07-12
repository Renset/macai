//
//  ChatListView.swift
//  macai
//
//  Created by Renat on 17.11.2024.
//

import AppKit
import CoreData
import SwiftUI

struct ChatListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var attentionStore: ChatAttentionStore
    @State private var debouncedSearchText: String = ""
    @State private var debounceTimer: Timer?
    @State private var selectedChatIDs = Set<NSManagedObjectID>()
    @StateObject private var nameGenerator = ChatNameGenerationCoordinator()

    @FetchRequest(
        entity: ChatEntity.entity(),
        sortDescriptors: [
            NSSortDescriptor(keyPath: \ChatEntity.isPinned, ascending: false),
            NSSortDescriptor(keyPath: \ChatEntity.updatedDate, ascending: false)
        ],
        animation: .default
    )
    private var chats: FetchedResults<ChatEntity>

    @Binding var selectedChat: ChatEntity?
    @Binding var searchText: String
    @Binding var isSelectionMode: Bool

    private var filteredChats: [ChatEntity] {
        if debouncedSearchText.isEmpty {
            return Array(chats)
        } else {
            return chats.filter { chat in
                // Check chat name first (most likely match)
                if chat.name.localizedCaseInsensitiveContains(debouncedSearchText) {
                    return true
                }
                
                // Check persona name
                if let personaName = chat.persona?.name,
                   personaName.localizedCaseInsensitiveContains(debouncedSearchText) {
                    return true
                }
                
                // Use a Core Data fetch with predicate for message search
                // This is more efficient than iterating through messagesArray
                // because Core Data can use indexes and limit results
                guard let context = chat.managedObjectContext else {
                    return false
                }
                
                let fetchRequest = NSFetchRequest<MessageEntity>(entityName: "MessageEntity")
                fetchRequest.predicate = NSPredicate(
                    format: "chat == %@ AND body CONTAINS[cd] %@",
                    chat, debouncedSearchText
                )
                
                let count = (try? context.count(for: fetchRequest)) ?? 0
                return count > 0
            }.sorted { first, second in
                if first.isPinned != second.isPinned {
                    return first.isPinned && !second.isPinned
                }
                return first.updatedDate > second.updatedDate
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if isSelectionMode {
                selectionHeader
            }

            ScrollViewReader { _ in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(filteredChats, id: \.objectID) { chat in
                            ChatListRow(
                                chat: chat,
                                showsAttentionIndicator: attentionStore.contains(chat.id),
                                isActive: !isSelectionMode && selectedChat?.objectID == chat.objectID,
                                isSelectionMode: isSelectionMode,
                                isBulkSelected: selectedChatIDs.contains(chat.objectID),
                                searchText: debouncedSearchText,
                                onActivate: { activate(chat) },
                                onAction: { handle($0, for: chat) }
                            )
                            .id(chat.objectID)
                        }
                    }
                    .padding(12)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isSelectionMode {
                bulkActionBar
            }
        }
        .onChange(of: searchText) { _, newValue in
            debounceTimer?.invalidate()
            
            debounceTimer = Timer.scheduledTimer(withTimeInterval: AppConstants.searchDebounceTime, repeats: false) { _ in
                debouncedSearchText = newValue
            }
        }
        .onAppear {
            debouncedSearchText = searchText
        }
        .onDisappear {
            debounceTimer?.invalidate()
        }
        .onChange(of: isSelectionMode) { _, isSelecting in
            if !isSelecting {
                selectedChatIDs.removeAll()
            }
        }
        .onChange(of: chats.map(\.objectID)) { _, availableIDs in
            selectedChatIDs.formIntersection(Set(availableIDs))
            if chats.isEmpty {
                isSelectionMode = false
            }
        }
        .onChange(of: nameGenerator.failureMessage) { _, message in
            guard let message else { return }
            presentError(message)
            nameGenerator.failureMessage = nil
        }
    }

    private var selectedChats: [ChatEntity] {
        chats.filter { selectedChatIDs.contains($0.objectID) }
    }

    private var allVisibleChatsSelected: Bool {
        !filteredChats.isEmpty && filteredChats.allSatisfy { selectedChatIDs.contains($0.objectID) }
    }

    private var selectionHeader: some View {
        HStack {
            Text("\(selectedChatIDs.count) selected")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(allVisibleChatsSelected ? "Deselect All" : "Select All") {
                if allVisibleChatsSelected {
                    selectedChatIDs.subtract(filteredChats.map(\.objectID))
                }
                else {
                    selectedChatIDs.formUnion(filteredChats.map(\.objectID))
                }
            }
            .buttonStyle(.plain)
            .font(.caption)
            .disabled(filteredChats.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var bulkActionBar: some View {
        HStack(spacing: 4) {
            bulkButton(
                title: selectedChats.allSatisfy(\.isPinned) ? "Unpin Chats" : "Pin Chats",
                systemImage: selectedChats.allSatisfy(\.isPinned) ? "pin.slash" : "pin"
            ) {
                setPinned(selectedChats, to: !selectedChats.allSatisfy(\.isPinned))
            }

            if nameGenerator.isRunning {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .help("Generating chat names")
            }
            else {
                bulkButton(title: "Generate Names", systemImage: "wand.and.stars") {
                    nameGenerator.generateNames(for: selectedChats, in: viewContext)
                }
            }

            Menu {
                Button("As Markdown…") { exportSelected(as: .markdown) }
                Button("As Plain Text…") { exportSelected(as: .plainText) }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("Export Chats")

            bulkButton(title: "Clear Chats", systemImage: "eraser") {
                confirmClear(selectedChats)
            }

            bulkButton(title: "Delete Chats", systemImage: "trash", role: .destructive) {
                confirmDelete(selectedChats)
            }
        }
        .padding(8)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .disabled(selectedChatIDs.isEmpty)
    }

    private func bulkButton(
        title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderless)
        .help(title)
    }

    private func activate(_ chat: ChatEntity) {
        if isSelectionMode {
            toggleSelection(of: chat)
        }
        else {
            selectedChat = chat
        }
    }

    private func toggleSelection(of chat: ChatEntity) {
        if !selectedChatIDs.insert(chat.objectID).inserted {
            selectedChatIDs.remove(chat.objectID)
        }
    }

    private func handle(_ action: ChatListRowAction, for chat: ChatEntity) {
        switch action {
        case .beginSelection:
            isSelectionMode = true
            selectedChatIDs.insert(chat.objectID)
        case .togglePin:
            setPinned([chat], to: !chat.isPinned)
        case .rename:
            rename(chat)
        case .regenerateName:
            nameGenerator.generateNames(for: [chat], in: viewContext)
        case .clear:
            confirmClear([chat])
        case .export(let format):
            ChatExporter.exportWithSavePanel(chat: chat, format: format)
        case .delete:
            confirmDelete([chat])
        }
    }

    private func setPinned(_ targetChats: [ChatEntity], to isPinned: Bool) {
        guard !targetChats.isEmpty else { return }
        targetChats.forEach { $0.isPinned = isPinned }
        saveChanges(action: isPinned ? "pin chats" : "unpin chats")
    }

    private func confirmClear(_ targetChats: [ChatEntity]) {
        guard !targetChats.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = targetChats.count == 1
            ? "Clear \(targetChats[0].name.isEmpty ? "this chat" : targetChats[0].name)?"
            : "Clear \(targetChats.count) chats?"
        alert.informativeText = "All messages will be deleted. Chat settings will be kept. This action cannot be undone."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        alert.presentAsSheetOrModal { response in
            guard response == .alertFirstButtonReturn else { return }
            targetChats.filter { !$0.isDeleted }.forEach { $0.clearMessages() }
            saveChanges(action: "clear chats")
        }
    }

    private func confirmDelete(_ targetChats: [ChatEntity]) {
        guard !targetChats.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = targetChats.count == 1
            ? "Delete \(targetChats[0].name.isEmpty ? "this chat" : targetChats[0].name)?"
            : "Delete \(targetChats.count) chats?"
        alert.informativeText = "This action cannot be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        alert.presentAsSheetOrModal { response in
            guard response == .alertFirstButtonReturn else { return }
            let targetIDs = Set(targetChats.map(\.objectID))
            if let selectedChat, targetIDs.contains(selectedChat.objectID) {
                self.selectedChat = nil
            }
            targetChats.filter { !$0.isDeleted }.forEach(viewContext.delete)
            if saveChanges(action: "delete chats") {
                selectedChatIDs.subtract(targetIDs)
                if selectedChatIDs.isEmpty {
                    isSelectionMode = false
                }
            }
        }
    }

    private func rename(_ chat: ChatEntity) {
        let alert = NSAlert()
        alert.messageText = "Rename chat"
        alert.informativeText = "Enter a new name for this chat."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        textField.stringValue = chat.name
        alert.accessoryView = textField
        alert.presentAsSheetOrModal { response in
            guard response == .alertFirstButtonReturn else { return }
            chat.name = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            saveChanges(action: "rename chat")
        }
    }

    private func exportSelected(as format: ChatExportFormat) {
        ChatExporter.exportWithSavePanel(chats: selectedChats, format: format)
    }

    @discardableResult
    private func saveChanges(action: String) -> Bool {
        do {
            try viewContext.save()
            return true
        }
        catch {
            presentError("Could not \(action): \(error.localizedDescription)")
            return false
        }
    }

    private func presentError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Chat Action Failed"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.presentAsSheetOrModal { _ in }
    }
}

@MainActor
private final class ChatNameGenerationCoordinator: ObservableObject {
    @Published var isRunning = false
    @Published var failureMessage: String?

    private var queue: [ChatEntity] = []
    private var currentViewModel: ChatViewModel?
    private var failureCount = 0

    func generateNames(for chats: [ChatEntity], in context: NSManagedObjectContext) {
        guard !isRunning else { return }
        queue = chats.filter { !$0.isDeleted && !$0.messagesArray.isEmpty }
        guard !queue.isEmpty else {
            failureMessage = "Selected chats do not contain messages to name."
            return
        }
        failureCount = 0
        isRunning = true
        generateNext(in: context)
    }

    private func generateNext(in context: NSManagedObjectContext) {
        guard !queue.isEmpty else {
            currentViewModel = nil
            isRunning = false
            if failureCount > 0 {
                failureMessage = "Could not generate names for \(failureCount) chat\(failureCount == 1 ? "" : "s")."
            }
            return
        }

        let chat = queue.removeFirst()
        guard !chat.isDeleted else {
            generateNext(in: context)
            return
        }
        let viewModel = ChatViewModel(chat: chat, viewContext: context, loadsMessages: false)
        currentViewModel = viewModel
        viewModel.regenerateChatName { [weak self] result in
            guard let self else { return }
            if case .failure = result {
                self.failureCount += 1
            }
            self.generateNext(in: context)
        }
    }
}
