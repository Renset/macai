//
//  ChatView.swift
//  macai
//
//  Created by Renat Notfullin on 18.03.2023.
//

import CoreData
import SwiftUI

struct ChatView: View {
    @Environment(\.managedObjectContext) private var viewContext
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
                        Accordion(title: chat.gptModel, isExpanded: chat.messages.count == 0) {
                            HStack {
                                VStack(alignment: .leading, content: {
                                    Text("System message: \(chat.systemMessage)")
                                    if (chat.messages.count == 0 && !editSystemMessage && isHovered) {
                                        Button(action: {
                                            newMessage = chat.systemMessage
                                            editSystemMessage = true
                                        }) {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        .buttonStyle(BorderlessButtonStyle())
                                        .foregroundColor(.gray)
                                    }
                                })
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
                            ForEach(Array(chat.messages.sorted(by: { $0.id < $1.id })), id: \.self) { messageEntity in
                                ChatBubbleView(
                                    message: messageEntity.body,
                                    index: Int(messageEntity.id),
                                    own: messageEntity.own,
                                    waitingForResponse: false,
                                    isStreaming: isStreaming
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
                                        Button(action: {
                                            sendMessage(ignoreMessageInput: true)}
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
        .navigationTitle(chat.name != "" ? chat.name : apiUrl == AppConstants.apiUrlChatCompletions ? "ChatGPT" : "macai LLM chat")
        .onAppear(perform: {
            self.lastOpenedChatId = chat.id.uuidString
            print("lastOpenedChatId: \(lastOpenedChatId)")
        })
    }
}

extension ChatView {
    private func processDeltaResponse(with data: Data?) {
        guard let data = data else {
            print("No data received.")
            return
        }
        
        let defaultRole = "assistant"
        let dataString = String(data: data, encoding: .utf8)
        if (dataString == "[DONE]") {
            handleChatCompletion(role: defaultRole)
            return
        }
        
        do {
            let jsonResponse = try JSONSerialization.jsonObject(with: data, options: [])
            
            if let dict = jsonResponse as? [String: Any] {
                // ChatGPT-compatible API
                if let choices = dict["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let delta = firstChoice["delta"] as? [String: String],
                   let contentPart = delta["content"] {
                    self.isStreaming = true
                    self.currentStreamingMessage += contentPart
                    DispatchQueue.main.async {
                        self.updateUIWithResponse(content: self.currentStreamingMessage, role: defaultRole)
                    }
                    if let finishReason = firstChoice["finish_reason"] as? String, finishReason == "stop" {
                        handleChatCompletion(role: defaultRole)
                    }
                }
                
                // Ollama-compatible API
                if let message = dict["message"] as? [String: Any],
                   let messageRole = message["role"] as? String,
                   let done = dict["done"] as? Bool,
                   let messageContent = message["content"] as? String {
                    self.isStreaming = true
                    self.currentStreamingMessage += messageContent
                    DispatchQueue.main.async {
                        self.updateUIWithResponse(content: self.currentStreamingMessage, role: messageRole)
                    }
                    
                    if done {
                        handleChatCompletion(role: messageRole)
                    }
                }
            }
               
        } catch {
            print(String(data: data, encoding: .utf8))
            print("Error parsing JSON: \(error)")
        }
    }
    
    private func handleChatCompletion(role: String) {
        print("Chat interaction completed.")
        DispatchQueue.main.async {
            self.resetCurrentMessage()
            // TODO: force the child view for update to reflect the new state
            self.isStreaming = false
            self.addNewMessageToRequestMessages(content: self.currentStreamingMessage, role: role)
            resetCurrentStreamingMessage()
            generateChatNameIfNeeded()
        }
    }
    
    private func resetCurrentStreamingMessage() {
        self.currentStreamingMessage = ""
    }
    
    func resetCurrentMessage() {
        self.viewContext.rollback()
    }

    func sendMessage(ignoreMessageInput: Bool = false) {
        let messageBody = newMessage
        
        if (!ignoreMessageInput) {
            saveNewMessageInStore(with: messageBody)
        }
        
        resetCurrentStreamingMessage()
        self.waitingForResponse = true

        if useStream {
            Task {
                do {
                    Task {
                        let request = prepareRequest(with: messageBody)
                        try? await sendAsync(using: request) { data in
                            self.processDeltaResponse(with: data)
                        }
                    }
                } catch {
                    print("An error occurred: \(error)")
                }
            }
        } else {
            let request = prepareRequest(with: messageBody)
            send(using: request) { data, response, error in
                processResponse(with: data, response: response, error: error)
                generateChatNameIfNeeded()
            }
        }
    }

    private func sendAsync(using request: URLRequest, processLine: @escaping (Data) -> Void) async throws {
        let (stream, response) = try await URLSession.shared.bytes(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case 200...299:
                    #if DEBUG
                    print("Got successful response code from server")
                    #endif
                case 400...599:
                    self.waitingForResponse = false
                    self.lastMessageError = true
                    return
                default:
                    print("Unhandled status code: \(httpResponse.statusCode)")
                    return
                }
            } else {
                throw URLError(.badServerResponse)
            }
        for try await line in stream.lines {
            if let lineData = line.data(using: .utf8) {
                let prefix = "data: "
                var index = line.startIndex
                if line.starts(with: prefix) {
                    index = line.index(line.startIndex, offsetBy: prefix.count)
                }
                let jsonData = String(line[index...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if let jsonData = jsonData.data(using: .utf8) {
                    processLine(jsonData)  // Process the JSON data
                    self.waitingForResponse = false
                }
            }

        }
    }


    private func generateChatNameIfNeeded() {
        guard self.chat.name == "", useChatGptForNames, self.chat.messages.count > 0 else {
            #if DEBUG
            print("Chat name not needed, skipping generation")
            #endif
            return }

        let requestContent = AppConstants.chatGptGenerateChatInstruction
        let request = prepareRequest(with: requestContent, forceStreamFalse: true)

        send(using: request) { data, response, error in
            DispatchQueue.main.async {
                guard let data = data else { return }

                guard let (messageContent, _) = parseJSONResponse(data: data) else {
                    print("Error parsing JSON")
                    return
                }

                let chatName = messageContent.trimmingCharacters(in: .whitespacesAndNewlines)
                self.chat.name = chatName
                self.viewContext.saveWithRetry(attempts: 3)
                
                // remove 'generate chat name' instruction from requestMessages
                #if DEBUG
                print("Length of requestMessages before deletion: \(self.chat.requestMessages.count)")
                #endif
                self.chat.requestMessages = self.chat.requestMessages.filter { $0["content"] != AppConstants.chatGptGenerateChatInstruction }
                #if DEBUG
                print("Length of requestMessages after deletion: \(self.chat.requestMessages.count)")
                #endif
            }
        }
    }
    
    private func saveNewMessageInStore(with messageBody: String) -> Void {
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
    
    private func prepareRequest(with messageBody: String, model: String = "", forceStreamFalse: Bool = false) -> URLRequest {
        var request = URLRequest(url: URL(string: apiUrl)!)
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

        chat.requestMessages.append(["role": "user", "content": messageBody ])

        let jsonDict: [String: Any] = [
            "model": (model != "") ? model : gptModel,
            "stream": forceStreamFalse ? false : useStream,
            "messages": Array(chat.requestMessages.prefix(1) + chat.requestMessages.suffix(Int(chatContext) > chat.requestMessages.count - 1 ? chat.requestMessages.count - 1 : Int(chatContext)))
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: jsonDict, options: [])
        
        return request
    }
    
    private func send(using request: URLRequest, completion: @escaping (Data?, URLResponse?, Error?) -> Void) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = AppConstants.requestTimeout

        let session = URLSession(configuration: configuration)

        let task = session.dataTask(with: request) { data, response, error in
            completion(data, response, error)
        }
        task.resume()
    }
    
    private func processResponse(with data: Data?, response: URLResponse?, error: Error?) {
        DispatchQueue.main.async {
            handleErrors(data: data, response: response, error: error)

            guard let data = data else { return }

            guard let (messageContent, messageRole) = parseJSONResponse(data: data) else {
                print("Error parsing JSON")
                self.lastMessageError = true
                return
            }

            updateUIWithResponse(content: messageContent, role: messageRole)
        }
    }

    private func handleErrors(data: Data?, response: URLResponse?, error: Error?) {
        self.waitingForResponse = false

        if let error = error {
            print("Error: \(error)")
            self.lastMessageError = true
            return
        }

        guard data != nil else {
            print("No data returned from API")
            self.lastMessageError = true
            return
        }
    }

    private func parseJSONResponse(data: Data) -> (String, String)? {
        if let responseString = String(data: data, encoding: .utf8) {
            #if DEBUG
            print("Response: \(responseString)")
            #endif
            do {
                let json = try JSONSerialization.jsonObject(with: data, options: [])
                if let dict = json as? [String: Any] {
                    // ChatGPT-compatible API
                    if let choices = dict["choices"] as? [[String: Any]],
                       let lastIndex = choices.indices.last,
                       let content = choices[lastIndex]["message"] as? [String: Any],
                       let messageRole = content["role"] as? String,
                       let messageContent = content["content"] as? String {
                        return (messageContent, messageRole)
                    }
                    
                    // ChatGPT-compatible API
                    if let message = dict["message"] as? [String: Any],
                       let messageRole = message["role"] as? String,
                       let messageContent = message["content"] as? String {
                        return (messageContent, messageRole)
                    }
                }
            }
            catch {
                print("Error parsing JSON: \(error.localizedDescription)")
                return nil
            }
        }
        return nil
    }

    private func updateUIWithResponse(content: String, role: String) {
        if useStream {
            let sortedMessages = chat.messages.sorted(by: { $0.timestamp < $1.timestamp })
                if let lastMessage = sortedMessages.last {
                    if lastMessage.own {
                        addNewMessageToChat(content: content, role: role)
                    } else {
                        lastMessage.body = content
                        lastMessage.own = false
                        lastMessage.timestamp = Date()
                        lastMessage.waitingForResponse = false
                        // Force the view to update
                        self.chat.objectWillChange.send()
                        self.viewContext.saveWithRetry(attempts: 3)
                    }
                }
        } else {
            addNewMessageToChat(content: content, role: role)
            addNewMessageToRequestMessages(content: content, role: role)
        }

    }

    private func addNewMessageToChat(content: String, role: String) {
        let receivedMessage = MessageEntity(context: self.viewContext)
        receivedMessage.id = Int64(self.chat.messages.count + 1)
        receivedMessage.name = "ChatGPT"
        receivedMessage.body = content.trimmingCharacters(in: .whitespacesAndNewlines)
        receivedMessage.timestamp = Date()
        receivedMessage.own = false
        receivedMessage.chat = self.chat

        self.lastMessageError = false

        self.chat.updatedDate = Date()
        self.chat.addToMessages(receivedMessage)
        self.viewContext.saveWithRetry(attempts: 3)
        
        self.chat.objectWillChange.send()
        #if DEBUG
        print("Value of choices[\(self.chat.requestMessages.count - 1)].message.content: \(content)")
        #endif
    }
    
    private func addNewMessageToRequestMessages(content: String, role: String) {
        self.chat.requestMessages.append(["role": role, "content": content])
        self.viewContext.saveWithRetry(attempts: 3)
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
