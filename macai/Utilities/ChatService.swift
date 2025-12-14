//
//  ChatService.swift
//  macai
//
//  Created by Renat Notfullin on 26.05.2023.
//

import Foundation

enum ChatError: Error {
    case requestFailed
    case responseUnsuccessful
    case invalidData
    case jsonParsingFailure
}

class ChatService {
    let session: URLSession
        var chat: ChatEntity
        var url: URL
        var gptToken: String
        var gptModel: String
        var chatContext: Double
        
    init(session: URLSession = URLSession(configuration: URLSessionConfiguration.default),
         chat: ChatEntity,
         url: URL,
         gptToken: String,
         gptModel: String,
         chatContext: Double) {
        self.session = session
        self.chat = chat
        self.url = url
        self.gptToken = gptToken
        self.gptModel = gptModel
        self.chatContext = chatContext
    }

    func sendMessage(_ message: String?, completion: @escaping (Result<MessageEntity, ChatError>) -> Void) {
        let request = prepareRequest(with: message)
        
        let task = session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Error: \(error)")
                    completion(.failure(.requestFailed))
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    completion(.failure(.responseUnsuccessful))
                    return
                }
                
                guard let data = data else {
                    completion(.failure(.invalidData))
                    return
                }
                
                do {
                    let messageEntity = try self.processResponse(data: data)
                    completion(.success(messageEntity))
                } catch {
                    completion(.failure(.jsonParsingFailure))
                }
            }
        }
        task.resume()
    }
    
    func prepareRequest(with message: String?) -> URLRequest {
        // Prepare the request
        var request = URLRequest(url: url)
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
        
        chat.requestMessages.append(["role": "user", "content": message ?? ""])
        
        let jsonDict: [String: Any] = [
            "model": gptModel,
            "messages": Array(chat.requestMessages.prefix(1) + chat.requestMessages.suffix(Int(chatContext) > chat.requestMessages.count - 1 ? chat.requestMessages.count - 1 : Int(chatContext)))
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: jsonDict, options: [])
        
        return request
    }
    
    func processResponse(data: Data?, response: URLResponse?, error: Error?) {
        DispatchQueue.main.async {
            self.waitingForResponse = false
            if let error = error {
                print("Error: \(error)")
                self.lastMessageError = true
                return
            }

            guard let data = data else {
                print("No data returned from API")
                self.lastMessageError = true
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
                        let receivedMessage = MessageEntity(context: self.viewContext)
                        receivedMessage.id = Int64(self.chat.messagesCount + 1)
                        receivedMessage.name = "ChatGPT"
                        receivedMessage.body = messageContent.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        receivedMessage.timestamp = Date()
                        receivedMessage.own = false
                        receivedMessage.chat = self.chat

                        self.lastMessageError = false

                        self.chat.updatedDate = Date()
                        self.chat.addToMessages(receivedMessage)
                        try? self.viewContext.save()
                        self.chat.requestMessages.append(["role": messageRole, "content": messageContent])

                        self.chat.objectWillChange.send()
                        print("Value of choices[\(lastIndex)].message.content: \(messageContent)")
                    }
                }
                catch {
                    print("Error parsing JSON: \(error.localizedDescription)")
                    self.lastMessageError = true
                }
            }
            else if let error = error {
                print("Error fetching data: \(error.localizedDescription)")
                self.lastMessageError = true
            }
        }
    }
    
    // Add other methods here: prepareRequest, processResponse, etc.
}
