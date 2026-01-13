//
//  OpenRouterHandler.swift
//  macai
//
//  Created by Renat on 04.03.2025.
//

import Foundation

class OpenRouterHandler: ChatGPTHandler {    
    override func parseJSONResponse(data: Data) -> (String, String)? {
        if let responseString = String(data: data, encoding: .utf8) {
            #if DEBUG
                print("Response: \(responseString)")
            #endif
            do {
                let json = try JSONSerialization.jsonObject(with: data, options: [])
                if let dict = json as? [String: Any],
                   let choices = dict["choices"] as? [[String: Any]],
                   let lastIndex = choices.indices.last,
                   let message = choices[lastIndex]["message"] as? [String: Any],
                   let messageRole = message["role"] as? String,
                   let messageContent = message["content"] as? String
                {
                    var finalContent = messageContent
                    
                    // Handle reasoning content if available
                    if let reasoningContent = message["reasoning"] as? String {
                        finalContent = "<think>\n\(reasoningContent)\n</think>\n\n\(messageContent)"
                    }
                    
                    return (finalContent, messageRole)
                }
            } catch {
                print("Error parsing JSON: \(error.localizedDescription)")
                return nil
            }
        }
        return nil
    }
    
    override func parseDeltaJSONResponse(data: Data?) -> (Bool, Error?, String?, String?) {
        guard let data = data else {
            print("No data received.")
            return (true, APIError.decodingFailed("No data received in SSE event"), nil, nil)
        }

        let defaultRole = "assistant"
        let dataString = String(data: data, encoding: .utf8)
        if dataString == "[DONE]" {
            return (true, nil, nil, nil)
        }

        do {
            let jsonResponse = try JSONSerialization.jsonObject(with: data, options: [])

            if let dict = jsonResponse as? [String: Any],
               let choices = dict["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let delta = firstChoice["delta"] as? [String: Any]
            {
                var content: String?
                var reasoningContent: String?
                
                if let contentPart = delta["content"] as? String {
                    content = contentPart
                }
                
                if let reasoningPart = delta["reasoning"] as? String {
                    reasoningContent = reasoningPart
                }
                
                let finished = firstChoice["finish_reason"] as? String == "stop"
                
                if let reasoningContent = reasoningContent {
                    return (finished, nil, reasoningContent, "reasoning")
                } else if let content = content {
                    return (finished, nil, content, defaultRole)
                }
            }
        } catch {
            #if DEBUG
                print(String(data: data, encoding: .utf8) ?? "Data cannot be converted into String")
                print("Error parsing JSON: \(error)")
            #endif
            
            return (false, APIError.decodingFailed("Failed to parse JSON: \(error.localizedDescription)"), nil, nil)
        }

        return (false, nil, nil, nil)
    }

    override func sendMessageStream(_ requestMessages: [[String: String]], temperature: Float) async throws
        -> AsyncThrowingStream<String, Error>
    {
        return AsyncThrowingStream { continuation in
            let request = self.prepareRequest(
                requestMessages: requestMessages,
                model: model,
                temperature: temperature,
                stream: true
            )

            let streamTask = Task {
                defer { self.activeStreamTask = nil }
                var isInReasoningBlock = false
                
                do {
                    let (stream, response) = try await session.bytes(for: request)
                    let result = self.handleAPIResponse(response, data: nil, error: nil)
                    switch result {
                    case .failure(let error):
                        var data = Data()
                        for try await byte in stream {
                            data.append(byte)
                        }
                        let error = APIError.serverError(
                            String(data: data, encoding: .utf8) ?? error.localizedDescription
                        )
                        continuation.finish(throwing: error)
                        return
                    case .success:
                        break
                    }

                    for try await line in stream.lines {
                        if line.data(using: .utf8) != nil && isNotSSEComment(line) {
                            let prefix = "data:"
                            var index = line.startIndex
                            if line.starts(with: prefix) {
                                index = line.index(line.startIndex, offsetBy: prefix.count)
                            }
                            let jsonData = String(line[index...]).trimmingCharacters(in: .whitespacesAndNewlines)
                            if let jsonData = jsonData.data(using: .utf8) {
                                let (finished, error, messageData, role) = parseDeltaJSONResponse(data: jsonData)

                                if let error = error {
                                    continuation.finish(throwing: error)
                                } else if let messageData = messageData {
                                    if role == "reasoning" {
                                        if !isInReasoningBlock {
                                            isInReasoningBlock = true
                                            continuation.yield("<think>\n")
                                        }
                                        continuation.yield(messageData)
                                    } else {
                                        if isInReasoningBlock {
                                            isInReasoningBlock = false
                                            continuation.yield("\n</think>\n\n")
                                        }
                                        continuation.yield(messageData)
                                    }
                                }
                                
                                if finished {
                                    if isInReasoningBlock {
                                        continuation.yield("\n</think>\n\n")
                                    }
                                    continuation.finish()
                                }
                            }
                        }
                    }
                    continuation.finish()
                }
                catch {
                    continuation.finish(throwing: error)
                }
            }
            activeStreamTask?.cancel()
            activeStreamTask = streamTask
            continuation.onTermination = { _ in
                streamTask.cancel()
            }
        }
    }
    
    override internal func prepareRequest(requestMessages: [[String: String]], model: String, temperature: Float, stream: Bool)
        -> URLRequest
    {
        let filteredMessages = requestMessages.map { message -> [String: String] in
            var newMessage = message
            if let content = message["content"] {
                newMessage["content"] = removeThinkingTags(from: content)
            }
            return newMessage
        }

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add OpenRouter specific headers
        request.setValue("https://github.com/Renset/macai", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("macai", forHTTPHeaderField: "X-Title")

        var temperatureOverride = temperature

        if AppConstants.openAiReasoningModels.contains(self.model) {
            temperatureOverride = 1
        }

        var processedMessages: [[String: Any]] = []

        for message in filteredMessages {
            var processedMessage: [String: Any] = [:]

            if let role = message["role"] {
                processedMessage["role"] = role
            }

            if let content = message["content"] {
                let imageUUIDs = AttachmentParser.extractImageUUIDs(from: content)
                let fileUUIDs = AttachmentParser.extractFileUUIDs(from: content)
                let textContent = AttachmentParser.stripAttachments(from: content)

                if !imageUUIDs.isEmpty || !fileUUIDs.isEmpty {
                    var contentArray: [[String: Any]] = []

                    if !textContent.isEmpty {
                        contentArray.append(["type": "text", "text": textContent])
                    }

                    for uuid in imageUUIDs {
                        if let imageData = self.loadImageFromCoreData(uuid: uuid) {
                            contentArray.append([
                                "type": "image_url",
                                "image_url": ["url": "data:image/jpeg;base64,\(imageData.base64EncodedString())"],
                            ])
                        }
                    }

                    for uuid in fileUUIDs {
                        if let filePayload = self.loadFileFromCoreData(uuid: uuid) {
                            let mimeType = filePayload.mimeType ?? "application/pdf"
                            let base64 = filePayload.data.base64EncodedString()
                            let safeFilename = (filePayload.filename?.isEmpty == false)
                                ? (filePayload.filename ?? "document.pdf")
                                : "document.pdf"
                            contentArray.append([
                                "type": "file",
                                "file": [
                                    "filename": safeFilename,
                                    "file_data": "data:\(mimeType);base64,\(base64)",
                                ],
                            ])
                        }
                    }

                    processedMessage["content"] = contentArray
                }
                else if textContent != content {
                    processedMessage["content"] = textContent
                }
                else {
                    processedMessage["content"] = content
                }
            }

            processedMessages.append(processedMessage)
        }

        let jsonDict: [String: Any] = [
            "model": self.model,
            "stream": stream,
            "messages": processedMessages,
            "temperature": temperatureOverride,
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: jsonDict, options: [])

        return request
    }
    
    private func removeThinkingTags(from content: String) -> String {
        let pattern = "<think>\\s*([\\s\\S]*?)\\s*</think>"
        
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let range = NSRange(content.startIndex..., in: content)
            let modifiedString = regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: "")
            
            return modifiedString.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            print("Error creating regex: \(error.localizedDescription)")
            return content
        }
    }
}
