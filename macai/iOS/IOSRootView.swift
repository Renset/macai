//
//  IOSRootView.swift
//  macai
//
//  iOS shell for macai using shared views.
//

import CoreData
import SwiftUI

#if os(iOS)
struct IOSRootView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @FetchRequest(
        entity: ChatEntity.entity(),
        sortDescriptors: [
            NSSortDescriptor(keyPath: \ChatEntity.isPinned, ascending: false),
            NSSortDescriptor(keyPath: \ChatEntity.updatedDate, ascending: false)
        ]
    )
    private var chats: FetchedResults<ChatEntity>

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \APIServiceEntity.addedDate, ascending: false)])
    private var apiServices: FetchedResults<APIServiceEntity>

    @State private var selectedChat: ChatEntity?
    @State private var searchText = ""
    @State private var isSettingsPresented = false
    @State private var isChatPresented = false
    @StateObject private var attentionStore = ChatAttentionStore.shared

    @AppStorage("gptModel") var gptModel = AppConstants.defaultPrimaryModel
    @AppStorage("systemMessage") var systemMessage = AppConstants.chatGptSystemMessage
    @AppStorage("lastOpenedChatId") var lastOpenedChatId = ""
    @AppStorage("defaultApiService") private var defaultApiServiceID: String?

    var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                NavigationStack {
                    chatListColumn
                        .navigationDestination(isPresented: $isChatPresented) {
                            if let selectedChat {
                                ChatView(viewContext: viewContext, chat: selectedChat, searchText: $searchText)
                            } else {
                                WelcomeScreen(
                                    chatsCount: chats.count,
                                    apiServiceIsPresent: apiServices.count > 0,
                                    customUrl: false,
                                    openPreferencesView: { isSettingsPresented = true },
                                    newChat: { newChat() }
                                )
                            }
                        }
                }
            } else {
                NavigationSplitView {
                    chatListColumn
                        .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 400)
                } detail: {
                    if let selectedChat {
                        ChatView(viewContext: viewContext, chat: selectedChat, searchText: $searchText)
                    } else {
                        WelcomeScreen(
                            chatsCount: chats.count,
                            apiServiceIsPresent: apiServices.count > 0,
                            customUrl: false,
                            openPreferencesView: { isSettingsPresented = true },
                            newChat: { newChat() }
                        )
                    }
                }
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
        .onTapGesture {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .sheet(isPresented: $isSettingsPresented) {
            PreferencesView()
                .environment(\.managedObjectContext, viewContext)
        }
        .onAppear {
            if let lastOpenedChatId = UUID(uuidString: lastOpenedChatId),
               let lastOpenedChat = chats.first(where: { $0.id == lastOpenedChatId }) {
                selectedChat = lastOpenedChat
            }
        }
        .onChange(of: chats.count) { _ in
            if selectedChat == nil, let firstChat = chats.first {
                selectedChat = firstChat
            }
        }
        .onChange(of: selectedChat) { newValue in
            if horizontalSizeClass == .compact {
                isChatPresented = newValue != nil
            }
        }
        .onChange(of: isChatPresented) { presented in
            if horizontalSizeClass == .compact, !presented {
                selectedChat = nil
            }
        }
    }

    private var chatListColumn: some View {
        ZStack {
            ChatListView(selectedChat: $selectedChat, searchText: $searchText)
                .environmentObject(attentionStore)

            if horizontalSizeClass == .compact,
               chats.isEmpty,
               selectedChat == nil
            {
                WelcomeScreen(
                    chatsCount: chats.count,
                    apiServiceIsPresent: apiServices.count > 0,
                    customUrl: false,
                    openPreferencesView: { isSettingsPresented = true },
                    newChat: { newChat() }
                )
                .background(Color(.systemBackground))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Chats")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            chatListSearchBar
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { isSettingsPresented = true }) {
                    Label("Settings", systemImage: "gear")
                        .labelStyle(.titleAndIcon)
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { newChat() }) {
                    Label("New Chat", systemImage: "square.and.pencil")
                        .labelStyle(.titleAndIcon)
                }
            }
        }
    }

    private var chatListSearchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search in chat…", text: $searchText)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .submitLabel(.search)

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .background(Color(.systemBackground).ignoresSafeArea(edges: .bottom))
    }

    private func newChat() {
        newChat(using: nil)
    }

    private func newChat(using preferredService: APIServiceEntity?) {
        let uuid = UUID()
        let newChat = ChatEntity(context: viewContext)

        newChat.id = uuid
        newChat.newChat = true
        newChat.temperature = 1
        newChat.top_p = 1.0
        newChat.behavior = "default"
        newChat.newMessage = ""
        newChat.createdDate = Date()
        newChat.updatedDate = Date()
        newChat.systemMessage = systemMessage
        newChat.gptModel = gptModel
        newChat.lastSequence = 0

        if let service = preferredService {
            newChat.apiService = service
            newChat.persona = service.defaultPersona
            newChat.gptModel = service.model ?? AppConstants.defaultModel(for: service.type)
            newChat.systemMessage = service.defaultPersona?.systemMessage ?? AppConstants.chatGptSystemMessage
        } else if let defaultServiceIDString = defaultApiServiceID,
                  let url = URL(string: defaultServiceIDString),
                  let objectID = viewContext.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: url) {
            do {
                let defaultService = try viewContext.existingObject(with: objectID) as? APIServiceEntity
                newChat.apiService = defaultService
                newChat.persona = defaultService?.defaultPersona
                newChat.gptModel = defaultService?.model ?? AppConstants.defaultModel(for: defaultService?.type)
                newChat.systemMessage = newChat.persona?.systemMessage ?? AppConstants.chatGptSystemMessage
            } catch {
                print("Default API service not found: \(error)")
            }
        }

        do {
            try viewContext.save()
            selectedChat = newChat
        } catch {
            print("Error saving new chat: \(error.localizedDescription)")
            viewContext.rollback()
        }
    }
}
#endif
