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
                if chat.name.localizedCaseInsensitiveContains(debouncedSearchText) {
                    return true
                }
                
                if let personaName = chat.persona?.name,
                   personaName.localizedCaseInsensitiveContains(debouncedSearchText) {
                    return true
                }
                
                for message in chat.messagesArray {
                    if message.body.localizedCaseInsensitiveContains(debouncedSearchText) {
                        return true
                    }
                }
                
                return false
            }.sorted { first, second in
                if first.isPinned != second.isPinned {
                    return first.isPinned && !second.isPinned
                }
                return first.updatedDate > second.updatedDate
            }
        }
    }

    var body: some View {
        List {
            ForEach(filteredChats, id: \.id) { chat in
                ChatListRow(
                    chat: chat,
                    selectedChat: $selectedChat,
                    viewContext: viewContext,
                    searchText: debouncedSearchText
                )
                .id(chat.id)
            }
        }
        .listStyle(.sidebar)
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
