//
//  ChatView.swift
//  macai
//
//  Created by Renat Notfullin on 18.03.2023.
//

import SwiftUI

struct Chat: Codable {
    var id: UUID
    var messagePreview: Message?
    var messages: [Message] = []
    var requestMessages = [["role": "user", "content": ""]]
    var newChat: Bool = true
    var temperature: Float64?
    var top_p: Float64?
    var behavior: String?
    var newMessage: String?
}

struct Message: Codable, Equatable {
    var id: Int
    var name: String
    var body: String
    var timestamp: Date
    var own: Bool
    var waitingForResponse: Bool?
}

struct MessageCell: View {
    @Binding var chat: Chat
    @State var timestamp: Date
    @State var message: String
    @Binding var isActive: Bool
    


    
    var body: some View {
        NavigationLink(destination: ChatView(chat: $chat, message: $chat.newMessage), isActive: $isActive) {
            VStack(alignment: .leading) {
                
                Text(timestamp, style: .date)
                    .font(.caption)
                
                // Show truncated message
                Text(message)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }
}

struct ChatView: View {
    //@State var id: Int = 0 // Chat id
    @Environment(\.updateAndSaveState) var saveState
    @Binding var chat: Chat
    @Binding var message: String?
    @State private var waitingForResponse = false
    @AppStorage("gptToken") var gptToken = ""
    @AppStorage("gptModel") var gptModel = "gpt-3.5-turbo"
    @State var messageCount: Int = 0
    @State private var messageField = ""
    
    let url = URL(string: "https://api.openai.com/v1/chat/completions")
    
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
                        if chat.messages.count > 0 {
                            ForEach(0..<chat.messages.count, id: \.self) { i in
                                ChatBubbleView(message: chat.messages[i].body, index: i, own: chat.messages[i].own, waitingForResponse: chat.messages[i].waitingForResponse)
                            }
                        }
                        
                    }
                    .padding()
                    // Add a listener to the messages array to listen for changes
                    .onReceive([chat.messages.count].publisher) { newCount in
                        // Add animation block to animate in new message
                        if newCount > self.messageCount {
                            self.messageCount = newCount
                            
                            withAnimation {
                                print("scrolling to message...")
                                scrollView.scrollTo($chat.messages.endIndex - 1)
                            }
                        }
                        
                    }
                }
            }
            
            // Input field, with multiline support and send button
            HStack {

                MessageInputView(text: $message, onEnter: {
                    if self.message != "" && self.message != " " {
                        self.sendMessage()
                        DispatchQueue.main.async {
                            self.message = ""
                        }
                    }
                })
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
                .padding()
            }

            
            
        }
        .background(backgroundColor)
        .navigationTitle("ChatGPT")
        //        .navigationBarTitleDisplayMode(.inline)
    }
    
    func getCurrentFormattedDate() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.string(from: Date())
    }
    
    func sendMessage() {
        let messageBody = self.message
        let sendingMessage = Message(
            id: chat.messages.count + 1, name: "", body: messageBody ?? "", timestamp: Date(), own: true)
        
        chat.messages.append(sendingMessage)
        chat.messagePreview = sendingMessage
        self.message = ""
        
        // Send message to OpenAI
        var request = URLRequest(url: url!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(gptToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if chat.newChat {
            chat.requestMessages = [["role": "system", "content": "You are ChatGPT, a large language model trained by OpenAI. Answer as concisely as possible.\nKnowledge cutoff: 2021-09-01\nCurrent date: \(getCurrentFormattedDate())"]]
            chat.newChat = false
        }
        
        chat.requestMessages.append(["role": "user", "content": messageBody ?? ""])
        
        
        let jsonDict: [String: Any] = [
            "model": gptModel,
            "messages": chat.requestMessages
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: jsonDict, options: [])
        
        print(String(data: request.httpBody!, encoding: .utf8))
        
        let session = URLSession.shared
        waitingForResponse = true
        
        // Display animated pencil icon when typing
        if self.waitingForResponse {
            chat.messages.append(Message(id: chat.messages.count + 1, name: "", body: "", timestamp: Date(), own: false, waitingForResponse: true))
        }
        
        let task = session.dataTask(with: request) { data, response, error in
            waitingForResponse = false
            if let error = error {
                print("Error: \(error)")
                // remove pencil icon
                chat.messages.removeLast()
                return
            }
            
            guard let data = data else {
                print("No data returned from API")
                // remove pencil icon
                chat.messages.removeLast()
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
                        
                        let receivedMessage = Message(
                            id: chat.messages.count + 1, name: "ChatGPT",
                            body: messageContent.trimmingCharacters(in: .whitespacesAndNewlines),
                            timestamp: Date(), own: false)
                        
                        DispatchQueue.main.async {
                            chat.messages.removeLast()
                            chat.messages.append(receivedMessage)
                            chat.messagePreview = receivedMessage
                            chat.requestMessages.append(["role": messageRole, "content": messageContent])
                            
                            // once we got response from server, we have to update chat id so the list is updated, too
                            chat.id = UUID()
                            self.saveState?(chat.id, self.message ?? "")
                            print("Value of choices[\(lastIndex)].message.content: \(messageContent)")
                        }
                        
                        
                        
                    }
                } catch {
                    DispatchQueue.main.async {
                        chat.messages.removeLast()
                        
                    }
                    print("Error parsing JSON: \(error.localizedDescription)")
                }
            } else if let error = error {
                print("Error fetching data: \(error.localizedDescription)")
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
