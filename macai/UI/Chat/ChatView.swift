//
//  ChatView.swift
//  macai
//
//  Created by Renat Notfullin on 18.03.2023.
//

import CoreData
import SwiftUI

struct ChatView: View {
    let viewContext: NSManagedObjectContext
    @State var chat: ChatEntity
    @State private var waitingForResponse = false
    @AppStorage("gptToken") var gptToken = ""
    @AppStorage("gptModel") var gptModel = AppConstants.chatGptDefaultModel
    @AppStorage("chatContext") var chatContext = AppConstants.chatGptContextSize
    @AppStorage("lastOpenedChatId") var lastOpenedChatId = ""
    @State var messageCount: Int = 0
    @State private var messageField = ""
    @State private var lastMessageError = false
    @State private var newMessage: String = ""
    @State private var editSystemMessage: Bool = false
    @State private var isStreaming: Bool = false
    @State private var isHovered = false
    @State private var currentStreamingMessage: String = ""
    @StateObject private var store = ChatStore(persistenceController: PersistenceController.shared)
    @AppStorage("useChatGptForNames") var useChatGptForNames: Bool = false
    @AppStorage("useStream") var useStream: Bool = true
    @AppStorage("apiUrl") var apiUrl: String = AppConstants.apiUrlChatCompletions
    @ObservedObject var chatViewModel: ChatViewModel
    @State private var renderTime: Double = 0

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

    @State private var selectedPersona: PersonaEntity?
    @State private var selectedApiService: APIServiceEntity?

    #if os(macOS)
        var backgroundColor = Color(NSColor.controlBackgroundColor)
    #else
        var backgroundColor = Color(UIColor.systemBackground)
    #endif

    var body: some View {
        let chatViewModel = ChatViewModel(chat: chat, viewContext: viewContext)

        VStack(spacing: 0) {
            ScrollView {
                ScrollViewReader { scrollView in
                    VStack(spacing: 12) {
                        Accordion(title: chat.apiService?.model ?? "", isExpanded: chat.messages.count == 0) {
                            HStack {
                                VStack(
                                    alignment: .leading,
                                    content: {
                                        if chat.messages.count == 0 {
                                            APIServiceAndPersonaSelectionView
                                        }
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
                                )
                                .frame(maxWidth: .infinity)
                                .padding(-4)
                                Spacer()
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .onHover { hovering in
                            isHovered = hovering
                        }

                        if chat.messages.count > 0 {
                            VStack {
                                ForEach(chatViewModel.sortedMessages, id: \.self) { messageEntity in
                                    ChatBubbleView(
                                        message: messageEntity.body,
                                        index: Int(messageEntity.id),
                                        own: messageEntity.own,
                                        waitingForResponse: false,
                                        isStreaming: $isStreaming
                                    ).id(Int64(messageEntity.id))
                                }
                            }
                        }

                        if chat.waitingForResponse {
                            ChatBubbleView(
                                message: "",
                                index: 0,
                                own: false,
                                waitingForResponse: true,
                                isStreaming: $isStreaming
                            ).id(-1)
                        }
                        else if lastMessageError {
                            HStack {
                                VStack {
                                    ChatBubbleView(
                                        message: "",
                                        index: 0,
                                        own: false,
                                        waitingForResponse: false,
                                        error: true,
                                        isStreaming: $isStreaming
                                    )
                                    HStack {
                                        Button(action: { lastMessageError = false }) {
                                            Text("Ignore")
                                            Image(systemName: "multiply")
                                        }
                                        Button(action: {
                                            sendMessage(ignoreMessageInput: true)
                                        }
                                        ) {
                                            Text("Retry")
                                            Image(systemName: "arrow.clockwise")
                                        }
                                        Spacer()
                                    }

                                }
                                .frame(width: 250)
                                .padding(.bottom, 10)
                                .id(-1)
                                Spacer()
                            }
                        }

                    }
                    .id("chatContainer")
                    .padding()
                    // Add a listener to the messages array to listen for changes
                    .onReceive([chat.messages.count].publisher) { newCount in
                        // Add animation block to animate in new message
                        if waitingForResponse || lastMessageError {
                            withAnimation {
                                scrollView.scrollTo(-1)
                            }
                        }
                        else if newCount as! Int > self.messageCount {
                            self.messageCount = newCount as! Int

                            let sortedMessages = chatViewModel.sortedMessages
                            if let lastMessage = sortedMessages.last {
                                withAnimation {
                                    print("scrolling to message...")
                                    scrollView.scrollTo(lastMessage.id)
                                }
                            }
                        }
                    }
                    .onAppear {
                        print("scrolling to message...")
                        scrollView.scrollTo("chatContainer", anchor: .bottom)
                    }
                }
            }
            .modifier(MeasureModifier(renderTime: $renderTime))

            // Input field, with multiline support and send button
            HStack {
                MessageInputView(
                    text: $newMessage,
                    onEnter: {
                        if editSystemMessage {
                            chat.systemMessage = newMessage
                            newMessage = ""
                            editSystemMessage = false
                            store.saveInCoreData()
                        }
                        else if newMessage != "" && newMessage != " " {
                            self.sendMessage()
                        }
                    },
                    isFocused: .focused
                )
                .onDisappear(perform: {
                    chat.newMessage = newMessage
                    store.saveInCoreData()
                })
                .onAppear(perform: {
                    DispatchQueue.main.async {
                        newMessage = chat.newMessage ?? ""
                    }
                })

                .textFieldStyle(RoundedBorderTextFieldStyle())
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .padding()
            }
            .border(width: 1, edges: [.top], color: Color(NSColor.windowBackgroundColor).opacity(0.8))

        }
        .background(backgroundColor)
        .navigationTitle(
            chat.name != "" ? chat.name : apiUrl == AppConstants.apiUrlChatCompletions ? "ChatGPT" : "macai LLM chat"
        )
        .onAppear(perform: {
            self.lastOpenedChatId = chat.id.uuidString
            print("lastOpenedChatId: \(lastOpenedChatId)")
            Self._printChanges()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                let startTime = CFAbsoluteTimeGetCurrent()
                _ = self.body
                renderTime = CFAbsoluteTimeGetCurrent() - startTime
            }
        })
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
                .onChange(of: chat.apiService) { newAPIService in
                    if let newAPIService = newAPIService {
                        if newAPIService.defaultPersona != nil {
                            chat.persona = newAPIService.defaultPersona
                            if let newSystemMessage = chat.persona?.systemMessage, newSystemMessage != "" {
                                chat.systemMessage = newSystemMessage
                            }
                            chat.gptModel = newAPIService.model ?? AppConstants.chatGptDefaultModel
                        }
                    }
                }

                Circle()
                    .fill(Color(hex: chat.persona?.color ?? "#CCCCCC") ?? .white)
                    .frame(width: 12, height: 12)

                Picker("AI Persona", selection: $chat.persona) {
                    ForEach(personas, id: \.objectID) { persona in
                        HStack {
                            Text(persona.name ?? "Unnamed Persona")
                        }
                        .tag(persona as PersonaEntity?)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .onChange(of: chat.persona) { newPersona in
                    if let newPersona = newPersona {
                        chat.systemMessage = newPersona.systemMessage ?? ""
                        viewContext.saveWithRetry(attempts: 1)

                    }
                }
                .frame(maxWidth: 300)

                Spacer()
            }
        }
        .background(Color(NSColor.textBackgroundColor))
        .padding(.bottom, 8)
        .cornerRadius(8)
    }
}

extension ChatView {
    func sendMessage(ignoreMessageInput: Bool = false) {
        resetError()

        let messageBody = newMessage

        if !ignoreMessageInput {
            saveNewMessageInStore(with: messageBody)
        }

        if chat.apiService?.useStreamResponse ?? false {
            self.isStreaming = true
            chatViewModel.sendMessageStream(messageBody, contextSize: Int(chatContext)) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        handleResponseFinished()
                        chatViewModel.generateChatNameIfNeeded()
                        break
                    case .failure(let error):
                        print("Error sending message: \(error)")
                        lastMessageError = true
                        handleResponseFinished()
                    }
                }
            }
        }
        else {
            self.waitingForResponse = true
            chatViewModel.sendMessage(messageBody, contextSize: Int(chatContext)) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        chatViewModel.generateChatNameIfNeeded()
                        handleResponseFinished()
                        break
                    case .failure(let error):
                        print("Error sending message: \(error)")
                        lastMessageError = true
                        handleResponseFinished()
                    }
                }
            }
        }
    }

    private func saveNewMessageInStore(with messageBody: String) {
        let sendingMessage = MessageEntity(context: viewContext)
        sendingMessage.id = Int64(chat.messages.count + 1)
        sendingMessage.name = ""
        sendingMessage.body = messageBody
        sendingMessage.timestamp = Date()
        sendingMessage.own = true
        sendingMessage.waitingForResponse = false
        sendingMessage.chat = chat

        chat.addToMessages(sendingMessage)
        store.saveInCoreData()
        newMessage = ""
    }

    private func handleResponseFinished() {
        self.isStreaming = false
        chat.waitingForResponse = false
    }

    private func resetError() {
        lastMessageError = false
    }
}

struct MeasureModifier: ViewModifier {
    @Binding var renderTime: Double

    func body(content: Content) -> some View {
        content
            .onAppear {
                let start = DispatchTime.now()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    let end = DispatchTime.now()
                    let nanoTime = end.uptimeNanoseconds - start.uptimeNanoseconds
                    let timeInterval = Double(nanoTime) / 1_000_000  // Convert to milliseconds
                    renderTime = timeInterval
                    print("Render time: \(timeInterval) ms")
                }
            }
    }
}

//struct ChatView_Previews: PreviewProvider {
//    static var previews: some View {
//        let mockMessage1 = Message(id: 1, name: "User", body: "Hello, how are you?", timestamp: Date(), own: true)
//        let mockMessage2 = Message(id: 2, name: "ChatGPT", body: "I'm doing well, thank you! How can I help you today?", timestamp: Date(), own: false)
//
//        let mockChat = Chat(id: UUID(), messagePreview: mockMessage2, messages: [mockMessage1, mockMessage2], newChat: false, newMessage: "Test new message")
//
//        ChatView(chat: .constant(mockChat), message: ".constant(mockChat.newMessage)")
//    }
//}
