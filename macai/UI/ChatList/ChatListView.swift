//
//  ChatListView.swift
//  macai
//
//  Created by Renat on 17.11.2024.
//

import SwiftUI

struct ChatListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        entity: ChatEntity.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \ChatEntity.updatedDate, ascending: false)],
        animation: .default
    )
    private var chats: FetchedResults<ChatEntity>
    @Binding var selectedChat: ChatEntity?
    
    var body: some View {
        List {
            ForEach(chats, id: \.id) { chat in
                ChatListRow(
                    chat: chats[getIndex(for: chat)],
                    selectedChat: $selectedChat,
                    viewContext: viewContext
                )
                .tag(chat.id)
            }
        }
    }
    
    private func getIndex(for chat: ChatEntity) -> Int {
        if let index = chats.firstIndex(where: { $0.id == chat.id }) {
            return index
        } else {
            fatalError("Chat not found in array")
        }
    }
}
