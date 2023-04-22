//
//  ChatView.swift
//  macai
//
//  Created by Renat Notfullin on 18.03.2023.
//

import CoreData
import SwiftUI

class ChatEntity: NSManagedObject, Identifiable {
    @NSManaged public var id: UUID
    @NSManaged public var messages: Set<MessageEntity>
    @NSManaged public var requestMessages: [[String: String]]
    @NSManaged public var newChat: Bool
    @NSManaged public var temperature: Double
    @NSManaged public var top_p: Double
    @NSManaged public var behavior: String?
    @NSManaged public var newMessage: String?
    @NSManaged public var createdDate: Date
    @NSManaged public var updatedDate: Date
    @NSManaged public var systemMessage: String
    @NSManaged public var gptModel: String
    
    func addToMessages(_ value: MessageEntity) {
        let items = self.mutableSetValue(forKey: "messages")
        items.add(value)
        value.chat = self

        self.objectWillChange.send()
    }

    func removeFromMessages(_ value: MessageEntity) {
        let items = self.mutableSetValue(forKey: "messages")
        items.remove(value)
        value.chat = nil
    }
    
    #warning("Temporary code for migrating old chats - remove after a while, when users have been updated. Issue link: https://github.com/Renset/macai/issues/7")
    @AppStorage("gptModel") var gptModelFromSettings = AppConstants.chatGptDefaultModel
    @AppStorage("systemMessage") var systemMessageFromSettings = AppConstants.chatGptSystemMessage
    @NSManaged public var systemMessageProcessed: Bool
    func extractSystemMessageAndModel() {
        guard !systemMessageProcessed && systemMessage == nil else {
            return
        }
        
        if let systemMessageIndex = requestMessages.firstIndex(where: { $0["role"] == "system" }) {
            systemMessage = requestMessages[systemMessageIndex]["content"]?.replacingOccurrences(of: "\n", with: " ") ?? systemMessageFromSettings
        } else {
            systemMessage = systemMessageFromSettings // Set your default value here
        }
        
        if (gptModel == nil) {
            gptModel = gptModelFromSettings
        }
        
        systemMessageProcessed = true
    }
}

class MessageEntity: NSManagedObject, Identifiable {
    @NSManaged public var id: Int64
    @NSManaged public var name: String
    @NSManaged public var body: String
    @NSManaged public var timestamp: Date
    @NSManaged public var own: Bool
    @NSManaged public var waitingForResponse: Bool
    @NSManaged public var chat: ChatEntity?
}

struct ChatView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State var chat: ChatEntity
    @State private var waitingForResponse = false
    @AppStorage("gptToken") var gptToken = ""
    @AppStorage("gptModel") var gptModel = AppConstants.chatGptDefaultModel
    @AppStorage("chatContext") var chatContext = AppConstants.chatGptContextSize
    @State var messageCount: Int = 0
    @State private var messageField = ""
    @State private var lastMessageError = false
    @State private var newMessage: String = ""
    @State private var editSystemMessage: Bool = false
    @StateObject private var store = ChatStore(persistenceController: PersistenceController.shared)

    let url = URL(string: AppConstants.apiUrlChatCompletions)

    #if os(macOS)
        var backgroundColor = Color(NSColor.controlBackgroundColor)
    #else
        var backgroundColor = Color(UIColor.systemBackground)
    #endif


    var body: some View {

        VStack(spacing: 0) {
            ScrollView {
                // Add the new scroll view reader as a child to the scrollview
                ScrollViewReader { scrollView in
                    VStack(spacing: 12) {
                        ChatBubbleView(message: "Model: \(chat.gptModel)", index: 0, own: true, waitingForResponse: false, initialMessage: true)
                        ChatBubbleView(message: "System message: \(chat.systemMessage)", index: 0, own: true, waitingForResponse: false, initialMessage: true)
                        
                        if (chat.messages.count == 0 && !editSystemMessage) {
                            HStack {
                                Spacer()
                                Button(action: {
                                    newMessage = chat.systemMessage
                                    editSystemMessage = true
                                }) {
                                    Text("Edit system message")
                                }
                            }
                        }

                        
                        if chat.messages.count > 0 {
                            ForEach(Array(chat.messages.sorted(by: { $0.id < $1.id })), id: \.self) { messageEntity in
                                ChatBubbleView(
                                    message: messageEntity.body,
                                    index: Int(messageEntity.id),
                                    own: messageEntity.own,
                                    waitingForResponse: false
                                ).id(Int64(messageEntity.id))
                            }
                        }

                        if waitingForResponse {
                            ChatBubbleView(message: "", index: 0, own: false, waitingForResponse: true).id(-1)
                        } else if lastMessageError {
                            HStack {
                                
                                VStack {
                                    ChatBubbleView(message: "", index: 0, own: false, waitingForResponse: false, error: true)
                                    HStack {
                                        Button(action: {lastMessageError = false}) {
                                            Text("Ignore")
                                            Image(systemName: "multiply")
                                        }
                                        Button(action: {sendMessage(ignoreMessageInput: true)}) {
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
                    .padding()
                    // Add a listener to the messages array to listen for changes
                    .onReceive([chat.messages.count].publisher) { newCount in
                        // Add animation block to animate in new message
                        if waitingForResponse || lastMessageError {
                            withAnimation {
                                scrollView.scrollTo(-1)
                            }
                        } else if newCount > self.messageCount {
                            self.messageCount = newCount

                            let sortedMessages = chat.messages.sorted(by: { $0.timestamp < $1.timestamp })
                            if let lastMessage = sortedMessages.last {

                                withAnimation {
                                    print("scrolling to message...")
                                    scrollView.scrollTo(lastMessage.id)
                                }
                            }
                        }

                    }
                }
            }

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
                        } else if newMessage != "" && newMessage != " " {
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
                .padding(.horizontal)
                .padding(.bottom)
            }

        }
        .background(backgroundColor)
        .navigationTitle("ChatGPT")
        //        .navigationBarTitleDisplayMode(.inline)
    }

    func sendMessage(ignoreMessageInput: Bool = false) {
        let messageBody = newMessage
        
        if (!ignoreMessageInput) {
            let sendingMessage = MessageEntity(context: viewContext)
            sendingMessage.id = Int64(chat.messages.count + 1)
            sendingMessage.name = ""
            sendingMessage.body = messageBody ?? ""
            sendingMessage.timestamp = Date()
            sendingMessage.own = true
            sendingMessage.waitingForResponse = false
            sendingMessage.chat = chat

            chat.addToMessages(sendingMessage)
            store.saveInCoreData()
            newMessage = ""
        }



        // Send message to OpenAI
        var request = URLRequest(url: url!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(gptToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if chat.newChat {
            chat.requestMessages = [
                [
                    "role": "system",
                    "content": chat.systemMessage,
                ]
            ]
            chat.newChat = false
        }

        chat.requestMessages.append(["role": "user", "content": messageBody ?? ""])

        let jsonDict: [String: Any] = [
            "model": gptModel,
            "messages": Array(chat.requestMessages.prefix(1) + chat.requestMessages.suffix(Int(chatContext) > chat.requestMessages.count - 1 ? chat.requestMessages.count - 1 : Int(chatContext)))
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: jsonDict, options: [])
        print(String(data: request.httpBody!, encoding: .utf8))
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = AppConstants.requestTimeout

        let session = URLSession(configuration: configuration)
        waitingForResponse = true

        let task = session.dataTask(with: request) { data, response, error in
            waitingForResponse = false
            if let error = error {
                print("Error: \(error)")
                lastMessageError = true
                return
            }

            guard let data = data else {
                print("No data returned from API")
                lastMessageError = true
                return
            }

            if let responseString = String(data: data, encoding: .utf8) {
                print("Response: \(responseString)")
                do {
                    let json = try JSONSerialization.jsonObject(with: data, options: [])
                    if let dict = json as? [String: Any],
                        let choices = dict["choices"] as? [[String: Any]],
                        let lastIndex = choices.indices.last,
                        let content = choices[lastIndex]["message"] as? [String: Any],
                        let messageRole = content["role"] as? String,
                        let messageContent = content["content"] as? String
                    {
                        let receivedMessage = MessageEntity(context: viewContext)
                        receivedMessage.id = Int64(chat.messages.count + 1)
                        receivedMessage.name = "ChatGPT"
                        receivedMessage.body = messageContent.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        receivedMessage.timestamp = Date()
                        receivedMessage.own = false
                        receivedMessage.chat = chat
                        
                        lastMessageError = false

                        DispatchQueue.main.async {
                            chat.updatedDate = Date()
                            chat.addToMessages(receivedMessage)
                            try? viewContext.save()
                            chat.requestMessages.append(["role": messageRole, "content": messageContent])

                            chat.objectWillChange.send()
                            print("Value of choices[\(lastIndex)].message.content: \(messageContent)")
                        }

                    }
                }
                catch {
                    print("Error parsing JSON: \(error.localizedDescription)")
                    lastMessageError = true
                }
            }
            else if let error = error {
                print("Error fetching data: \(error.localizedDescription)")
                lastMessageError = true
            }

        }
        task.resume()
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
