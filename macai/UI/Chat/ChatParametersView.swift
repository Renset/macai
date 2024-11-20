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
        sortDescriptors: [NSSortDescriptor(keyPath: \PersonaEntity.name, ascending: true)],
        animation: .default
    )
    private var personas: FetchedResults<PersonaEntity>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \APIServiceEntity.addedDate, ascending: false)],
        animation: .default
    )
    private var apiServices: FetchedResults<APIServiceEntity>

    var body: some View {
        Accordion(
            icon: chat.apiService?.type != nil ? "logo_" + (chat.apiService?.type ?? "") : nil,
            title: chat.apiService?.name != nil
                ? ((chat.apiService!.name ?? "") + " — " + (chat.persona?.name ?? "No Persona")) : "",
            isExpanded: chat.messages.count == 0,
            isButtonHidden: chat.messages.count == 0
        ) {
            HStack {
                VStack(
                    alignment: .leading,
                    content: {
                        APIServiceAndPersonaSelectionView

                        VStack(alignment: .leading) {
                            Text("System message: \(chat.systemMessage)").textSelection(.enabled)
                            if chat.messages.count == 0 && !editSystemMessage && isHovered {
                                Button(action: {
                                    newMessage = chat.systemMessage
                                    editSystemMessage = true
                                }) {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .buttonStyle(BorderlessButtonStyle())
                                .foregroundColor(.gray)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                )
                .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var APIServiceAndPersonaSelectionView: some View {
        VStack(alignment: .leading) {
            HStack {
                Picker("API Service", selection: $chat.apiService) {
                    ForEach(apiServices, id: \.objectID) { apiService in
                        Text(apiService.name ?? "Unnamed API Service")
                            .tag(apiService)
                    }
                }
                .frame(maxWidth: 200)
                .onChange(of: chat.apiService) { newAPIService in
                    if let newAPIService = newAPIService {
                        if newAPIService.defaultPersona != nil {
                            chat.persona = newAPIService.defaultPersona
                            if let newSystemMessage = chat.persona?.systemMessage, newSystemMessage != "" {
                                chat.systemMessage = newSystemMessage
                            }
                        }
                        chat.gptModel = newAPIService.model ?? AppConstants.chatGptDefaultModel
                        chat.objectWillChange.send()
                        try? viewContext.save()
                        chatViewModel.recreateMessageManager()
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            PersonaSelectorView(chat: chat)
        }
        .background(Color(NSColor.textBackgroundColor))
        .padding(.bottom, 8)
        .cornerRadius(8)
    }
}

//#Preview {
//    ChatParametersView()
//}
