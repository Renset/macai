//
//  ChatListView.swift
//  macai
//
//  Created by Renat on 17.11.2024.
//

import CoreData
import SwiftUI

struct ChatListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var attentionStore: ChatAttentionStore
    @State private var scrollOffset: CGFloat = 0
    @State private var previousOffset: CGFloat = 0
    @State private var debouncedSearchText: String = ""
    @State private var debounceTimer: Timer?

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
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(filteredChats, id: \.objectID) { chat in
                        ChatListRow(
                            chat: chat,
                            showsAttentionIndicator: attentionStore.contains(chat.id),
                            selectedChat: $selectedChat,
                            viewContext: viewContext,
                            searchText: debouncedSearchText
                        )
                        .id(chat.objectID)
                    }
                }
                .padding(12)
            }
        }
        .onChange(of: searchText) { newValue in
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
    }
}
