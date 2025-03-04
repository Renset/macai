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
    @State private var searchText = ""
    @State private var showSearch = false
    @State private var scrollOffset: CGFloat = 0
    @State private var previousOffset: CGFloat = 0
    @FocusState private var isSearchFocused: Bool

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

    private var filteredChats: [ChatEntity] {
        guard !searchText.isEmpty else { return Array(chats) }

        let searchQuery = searchText.lowercased()
        return chats.filter { chat in
            let name = chat.name.lowercased()
            if name.contains(searchQuery) {
                return true
            }

            if chat.systemMessage.lowercased().contains(searchQuery) {
                return true
            }

            if let personaName = chat.persona?.name?.lowercased(),
                personaName.contains(searchQuery)
            {
                return true
            }

            if let messages = chat.messages.array as? [MessageEntity],
                messages.contains(where: { $0.body.lowercased().contains(searchQuery) })
            {
                return true
            }

            return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.bottom, 8)

            List {
                ForEach(filteredChats, id: \.objectID) { chat in
                    ChatListRow(
                        chat: chat,
                        selectedChat: $selectedChat,
                        viewContext: viewContext,
                        searchText: searchText
                    )
                }
            }
            .listStyle(.sidebar)
        }
        .background(
            Button("") {
                isSearchFocused = true
            }
            .keyboardShortcut("f", modifiers: .command)
            .opacity(0)
        )
        .onChange(of: selectedChat) { _ in
            isSearchFocused = false
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)

            TextField("Search chats...", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(.body))
                .focused($isSearchFocused)
                .onExitCommand {
                    searchText = ""
                    isSearchFocused = false
                }

            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(8)
        .padding(.top, 0)
        .background(isSearchFocused ? Color(NSColor.controlBackgroundColor).opacity(0.4) : Color.clear)
        .cornerRadius(8)
        .padding(.horizontal)
    }
}
