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
    @State private var newMessage: String = ""
    @State private var editSystemMessage: Bool = false
    @State private var isStreaming: Bool = false
    @State private var isHovered = false
    @State private var currentStreamingMessage: String = ""
    @StateObject private var store = ChatStore(persistenceController: PersistenceController.shared)
    @AppStorage("useChatGptForNames") var useChatGptForNames: Bool = false
    @AppStorage("useStream") var useStream: Bool = true
    @AppStorage("apiUrl") var apiUrl: String = AppConstants.apiUrlChatCompletions
    @StateObject private var chatViewModel: ChatViewModel
    @State private var renderTime: Double = 0
    @State private var selectedPersona: PersonaEntity?
    @State private var selectedApiService: APIServiceEntity?
    var backgroundColor = Color(NSColor.controlBackgroundColor)
    @State private var currentError: ErrorMessage?
    @Environment(\.colorScheme) private var colorScheme
    @State private var isBottomContainerExpanded = false

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \APIServiceEntity.addedDate, ascending: false)],
        animation: .default
    )
    private var apiServices: FetchedResults<APIServiceEntity>

    init(viewContext: NSManagedObjectContext, chat: ChatEntity) {
        self.viewContext = viewContext
        self._chat = State(initialValue: chat)

        self._chatViewModel = StateObject(
            wrappedValue: ChatViewModel(chat: chat, viewContext: viewContext)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                ScrollViewReader { scrollView in
                    VStack {
                        SystemMessageBubbleView(
                            message: chat.systemMessage,
                            color: chat.persona?.color,
                            newMessage: $newMessage,
                            editSystemMessage: $editSystemMessage
                        )
                        .id("system_message")

                        if chat.messages.count > 0 {
                            ForEach(chatViewModel.sortedMessages, id: \.self) { messageEntity in
                                let bubbleContent = ChatBubbleContent(
                                    message: messageEntity.body,
                                    own: messageEntity.own,
                                    waitingForResponse: messageEntity.waitingForResponse,
                                    errorMessage: nil,
                                    systemMessage: false,
                                    isStreaming: isStreaming
                                )
                                ChatBubbleView(content: bubbleContent, message: messageEntity)
                                    .id(messageEntity.id)
                            }
                        }

                        if chat.waitingForResponse {
                            let bubbleContent = ChatBubbleContent(
                                message: "",
                                own: false,
                                waitingForResponse: true,
                                errorMessage: nil,
                                systemMessage: false,
                                isStreaming: isStreaming
                            )

                            ChatBubbleView(content: bubbleContent)
                                .id(-1)
                        }
                        else if let error = currentError {
                            let bubbleContent = ChatBubbleContent(
                                message: "",
                                own: false,
                                waitingForResponse: false,
                                errorMessage: error,
                                systemMessage: false,
                                isStreaming: isStreaming
                            )

                            ChatBubbleView(content: bubbleContent)
                                .id(-2)
                        }
                    }
                    .padding(24)
                    .onReceive([chat.messages.count].publisher) { newCount in
                        if waitingForResponse || currentError != nil {
                            withAnimation {
                                scrollView.scrollTo(-1)
                            }
                        }
                        else if newCount > self.messageCount {
                            self.messageCount = newCount

                            let sortedMessages = chatViewModel.sortedMessages
                            if let lastMessage = sortedMessages.last {
                                scrollView.scrollTo(lastMessage.id)
                            }
                        }
                    }
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            if let lastMessage = chatViewModel.sortedMessages.last {
                                withAnimation(.easeOut(duration: 0.1)) {
                                    scrollView.scrollTo(lastMessage.id, anchor: .bottom)
                                }
                            }
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RetryMessage"))) { _ in
                        if currentError != nil {
                            sendMessage(ignoreMessageInput: true)
                        }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("IgnoreError"))) { _ in
                        currentError = nil
                    }
                }
                .id("chatContainer")
            }
            .modifier(MeasureModifier(renderTime: $renderTime))
            .padding(.bottom, 6)
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [
                        .clear,
                        backgroundColor.opacity(0.25),
                        backgroundColor.opacity(0.5),
                        backgroundColor.opacity(0.9),
                        backgroundColor,
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 40)
                .padding(.trailing, 16)
                .allowsHitTesting(false)
            }

            ChatBottomContainerView(
                chat: chat,
                newMessage: $newMessage,
                isExpanded: $isBottomContainerExpanded,
                onSendMessage: {
                    if editSystemMessage {
                        chat.systemMessage = newMessage
                        newMessage = ""
                        editSystemMessage = false
                        store.saveInCoreData()
                    }
                    else if newMessage != "" && newMessage != " " {
                        self.sendMessage()
                    }
                }
            )

        }
        .background(backgroundColor)
        .navigationTitle(
            chat.name != "" ? chat.name : chat.persona?.name ?? "macai LLM chat"
        )
        .onAppear(perform: {
            self.lastOpenedChatId = chat.id.uuidString
            print("lastOpenedChatId: \(lastOpenedChatId)")
            Self._printChanges()
            DispatchQueue.main.asyncAfter(deadline: .now()) {
                let startTime = CFAbsoluteTimeGetCurrent()
                _ = self.body
                renderTime = CFAbsoluteTimeGetCurrent() - startTime
            }
        })
    }
}

extension ChatView {
    func sendMessage(ignoreMessageInput: Bool = false) {
        resetError()
    
        let messageBody = newMessage
        let isFirstMessage = chat.messages.count == 0
    
        if !ignoreMessageInput {
            saveNewMessageInStore(with: messageBody)
            
            if isFirstMessage {
                withAnimation {
                    isBottomContainerExpanded = false
                }
            }
        }
        
        if chat.apiService?.useStreamResponse ?? false {
            self.isStreaming = true
            chatViewModel.sendMessageStream(
                messageBody,
                contextSize: Int(chat.apiService?.contextSize ?? Int16(AppConstants.chatGptContextSize))
            ) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        handleResponseFinished()
                        chatViewModel.generateChatNameIfNeeded()
                        break
                    case .failure(let error):
                        print("Error sending message: \(error)")
                        currentError = ErrorMessage(type: error as! APIError, timestamp: Date())
                        handleResponseFinished()
                    }
                }
            }
        }
        else {
            self.waitingForResponse = true
            chatViewModel.sendMessage(
                messageBody,
                contextSize: Int(chat.apiService?.contextSize ?? Int16(AppConstants.chatGptContextSize))
            ) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        chatViewModel.generateChatNameIfNeeded()
                        handleResponseFinished()
                        break
                    case .failure(let error):
                        print("Error sending message: \(error)")
                        currentError = ErrorMessage(type: error as! APIError, timestamp: Date())
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
        currentError = nil
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
