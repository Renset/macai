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
        if searchText.isEmpty {
            return Array(chats)
        } else {
            return chats.filter { chat in
                if chat.name.localizedCaseInsensitiveContains(searchText) {
                    return true
                }
                
                if let personaName = chat.persona?.name,
                   personaName.localizedCaseInsensitiveContains(searchText) {
                    return true
                }
                
                for message in chat.messagesArray {
                    if message.body.localizedCaseInsensitiveContains(searchText) {
                        return true
                    }
                }
                
                return false
            }
        }
    }

    var body: some View {
        List {
            ForEach(filteredChats, id: \.objectID) { chat in
                ChatListRow(
                    chat: chat,
                    selectedChat: $selectedChat,
                    viewContext: viewContext
                )
            }
        }
        .listStyle(.sidebar)
    }
}
