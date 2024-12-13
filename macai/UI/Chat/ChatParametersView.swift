//
//  ChatParametersView.swift
//  macai
//
//  Created by Renat Notfullin on 08.11.2024.
//

import SwiftUI

struct ChatParametersView: View {
    let viewContext: NSManagedObjectContext
    @State var chat: ChatEntity
    @Binding var newMessage: String
    @Binding var editSystemMessage: Bool
    @State var isHovered: Bool
    @ObservedObject var chatViewModel: ChatViewModel

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \APIServiceEntity.addedDate, ascending: false)],
        animation: .default
    )
    private var apiServices: FetchedResults<APIServiceEntity>

    var body: some View {
        Accordion(
            icon: chat.apiService?.type != nil ? "logo_" + (chat.apiService?.type ?? "") : nil,
            title: accordionTitle,
            isExpanded: chat.messages.count == 0,
            isButtonHidden: false
        ) {
            VStack(alignment: .center, spacing: 12) {
                HStack {
                    APIServiceSelector(
                        chat: chat,
                        apiServices: apiServices,
                        onServiceChanged: handleServiceChange
                    )
                }

                PersonaSelectorView(chat: chat)

                SystemMessageView(
                    message: chat.systemMessage,
                    isEditable: !editSystemMessage && isHovered,
                    onEdit: handleSystemMessageEdit
                )
                .onHover { hovering in
                    isHovered = hovering
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var accordionTitle: String {
        let modelName = chat.gptModel
        let personaName = chat.persona?.name ?? "No assistant selected"
        return "\(modelName) — \(personaName)"
    }

    private func handleServiceChange(_ newService: APIServiceEntity) {
        if let newDefaultPersona = newService.defaultPersona {
            chat.persona = newDefaultPersona
            if let newSystemMessage = chat.persona?.systemMessage,
                !newSystemMessage.isEmpty
            {
                chat.systemMessage = newSystemMessage
            }
        }
        chat.gptModel = newService.model ?? AppConstants.chatGptDefaultModel
        chat.objectWillChange.send()
        try? viewContext.save()
        chatViewModel.recreateMessageManager()
    }

    private func handleSystemMessageEdit() {
        newMessage = chat.systemMessage
        editSystemMessage = true
    }
}

private struct APIServiceSelector: View {
    @ObservedObject var chat: ChatEntity
    let apiServices: FetchedResults<APIServiceEntity>
    let onServiceChanged: (APIServiceEntity) -> Void

    var body: some View {
        HStack {
            Image("logo_\(chat.apiService?.type ?? "")")
                .resizable()
                .renderingMode(.template)
                .interpolation(.high)
                .antialiased(true)
                .frame(width: 16, height: 16)

            if apiServices.count > 1 {
                Picker("API Service", selection: $chat.apiService) {
                    ForEach(apiServices, id: \.objectID) { apiService in
                        Text(apiService.name ?? "Unnamed API Service")
                            .tag(apiService as APIServiceEntity?)
                    }
                }
                .frame(maxWidth: 200)
                .onChange(of: chat.apiService) { newService in
                    if let newService = newService {
                        onServiceChanged(newService)
                    }
                }
                .pickerStyle(.menu)
            } else {
                Text("API Service: \(chat.apiService?.name ?? "Unnamed API Service")")
            }

        }
        .padding(.horizontal, 20)
    }
}

private struct SystemMessageView: View {
    let message: String
    let isEditable: Bool
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            Text("System message: \(message)")
                .textSelection(.enabled)

            if isEditable {
                HStack {
                    Button(action: onEdit) {
                        Label("Edit", systemImage: "pencil")
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .foregroundColor(.gray)

                    Spacer()
                }
                .frame(height: 12)

            }
            else {
                Color.clear.frame(height: 12)
            }
        }
        .padding(.horizontal, 20)
    }
}

//#Preview {
//    ChatParametersView()
//}
