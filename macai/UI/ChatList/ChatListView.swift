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

    @FetchRequest(
        entity: ChatEntity.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \ChatEntity.updatedDate, ascending: false)],
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

            List {
                ForEach(filteredChats, id: \.id) { chat in
                    ChatListRow(
                        chat: chat,
                        selectedChat: $selectedChat,
                        viewContext: viewContext,
                        searchText: searchText
                    )
                    .tag(chat.id)
                }
            }
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)

            TextField("Search chats...", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(.body))
                .onExitCommand {
                    searchText = ""
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
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .padding(.horizontal)
        .padding(.vertical, 8)

    }
}
