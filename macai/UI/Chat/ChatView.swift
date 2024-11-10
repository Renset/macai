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
    @StateObject private var chatViewModel: ChatViewModel
    @State private var renderTime: Double = 0

    @State private var selectedPersona: PersonaEntity?
    @State private var selectedApiService: APIServiceEntity?

    var backgroundColor = Color(NSColor.controlBackgroundColor)

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
                    ChatParametersView(
                        viewContext: viewContext,
                        chat: chat,
                        newMessage: $newMessage,
                        editSystemMessage: $editSystemMessage,
                        isHovered: isHovered,
                        chatViewModel: chatViewModel
                    )
                    .padding(.vertical)

                    if chat.messages.count > 0 {
                        VStack {
                            ForEach(chatViewModel.sortedMessages, id: \.self) { messageEntity in
                                let bubbleContent = ChatBubbleContent(
                                    message: messageEntity.body,
                                    own: messageEntity.own,
                                    waitingForResponse: messageEntity.waitingForResponse,
                                    error: false,
                                    initialMessage: false,
                                    isStreaming: isStreaming
                                )

                                ChatBubbleView(content: bubbleContent)
                                    .id(messageEntity.id)
                            }
                        }
                        .onReceive([chat.messages.count].publisher) { newCount in
                            if waitingForResponse || lastMessageError {
                                withAnimation {
                                    scrollView.scrollTo(-1)
                                }
                            }
                            else if newCount > self.messageCount {
                                self.messageCount = newCount

                                let sortedMessages = chatViewModel.sortedMessages
                                if let lastMessage = sortedMessages.last {
                                    scrollView.scrollTo(lastMessage.id)
                                    //                                    withAnimation {
                                    //                                        print("scrolling to message...")
                                    //
                                    //                                    }
                                }
                            }
                        }
                        .onAppear {
                            print("scrolling to message...")
                            scrollView.scrollTo("chatContainer", anchor: .bottom)
                        }
                    }

                    if chat.waitingForResponse {
                        let bubbleContent = ChatBubbleContent(
                            message: "",
                            own: false,
                            waitingForResponse: true,
                            error: false,
                            initialMessage: false,
                            isStreaming: isStreaming
                        )

                        ChatBubbleView(content: bubbleContent)
                            .id(-1)
                    }
                    else if lastMessageError {
                        HStack {
                            VStack {
                                let bubbleContent = ChatBubbleContent(
                                    message: "",
                                    own: false,
                                    waitingForResponse: false,
                                    error: true,
                                    initialMessage: false,
                                    isStreaming: isStreaming
                                )

                                ChatBubbleView(content: bubbleContent)
                                    .id(-2)

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

struct MessageRow: View {
    let messageEntity: MessageEntity
    let isStreaming: Bool

    var body: some View {
        let bubbleContent = ChatBubbleContent(
            message: messageEntity.body,
            own: messageEntity.own,
            waitingForResponse: messageEntity.waitingForResponse,
            error: false,
            initialMessage: false,
            isStreaming: isStreaming
        )

        ChatBubbleView(content: bubbleContent)
            .id(messageEntity.id)
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
