//
//  MessageCell.swift
//  macai
//
//  Created by Renat Notfullin on 25.03.2023.
//

import SwiftUI

struct MessageCell: View {
    @ObservedObject var chat: ChatEntity
    @State var timestamp: Date
    var message: String
    @Binding var isActive: Bool
    let viewContext: NSManagedObjectContext
    @State private var isHovered = false

    var body: some View {
        Button {
            isActive = true
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    //                Text(timestamp, style: .date)
                    //                    .font(.caption)

                    HStack {
                        if let personaName = chat.persona?.name {
                            Text(personaName)
                                .font(.caption)
                        }
                        else {
                            Text("No persona selected")
                                .font(.caption)
                        }
                    }

                    if chat.name != "" {
                        Text(chat.name)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    if message != "" {
                        Text(message)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                }
                .padding(8)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .foregroundColor(self.isActive ? .white : .primary)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(self.isActive ? Color.accentColor : self.isHovered ? Color(hex: "#CCCCCC")! : Color.clear)
            )
            .onHover { hovering in
                isHovered = hovering
            }

        }
        .buttonStyle(.borderless)
        .background(Color.clear)
    }
}

struct MessageCell_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            MessageCell(
                chat: createPreviewChat(name: "Regular Chat"),
                timestamp: Date(),
                message: "Hello, how are you?",
                isActive: .constant(false),
                viewContext: PersistenceController.preview.container.viewContext
            )

            MessageCell(
                chat: createPreviewChat(name: "Selected Chat"),
                timestamp: Date(),
                message: "This is a selected chat preview",
                isActive: .constant(true),
                viewContext: PersistenceController.preview.container.viewContext
            )

            MessageCell(
                chat: createPreviewChat(name: "Long Message"),
                timestamp: Date(),
                message:
                    "This is a very long message that should be truncated when displayed in the preview cell of our chat application",
                isActive: .constant(false),
                viewContext: PersistenceController.preview.container.viewContext
            )
        }
        .previewLayout(.fixed(width: 300, height: 100))
    }

    static func createPreviewChat(name: String) -> ChatEntity {
        let context = PersistenceController.preview.container.viewContext
        let chat = ChatEntity(context: context)
        chat.id = UUID()
        chat.name = name
        chat.createdDate = Date()
        chat.updatedDate = Date()
        chat.systemMessage = AppConstants.chatGptSystemMessage
        chat.gptModel = AppConstants.chatGptDefaultModel
        return chat
    }
}
