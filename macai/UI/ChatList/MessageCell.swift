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

    var body: some View {
        NavigationLink(
            destination: ChatView(
                viewContext: viewContext,
                chat: chat,
                chatViewModel: ChatViewModel(chat: chat, viewContext: viewContext)
            ),
            isActive: $isActive
        ) {
            VStack(alignment: .leading) {

                //                Text(timestamp, style: .date)
                //                    .font(.caption)

                HStack {
                    if let personaName = chat.persona?.name {
                        Text(personaName)
                            .font(.caption)
                    }
                }

                if chat.name != "" {
                    Text(chat.name)
                        .font(.headline)
                        .animation(Animation.easeInOut(duration: 0.5))
                }

                // Show last message as truncated text
                if message != "" {
                    Text(message)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

            }
        }
    }
}

//struct MessageCell_Previews: PreviewProvider {
//    @Environment(\.managedObjectContext) private var viewContext
//    static var previews: some View {
//        let chat = ChatEntity(context: PersistenceController.shared.container.viewContext)
//
//        MessageCell(
//            chat: chat,
//            timestamp: Date(),
//            message: "Hello, how are you?",
//            isActive: .constant(false)
//        )
//        .previewLayout(.sizeThatFits)
//    }
//}
