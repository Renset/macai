//
//  OpenAIResponsesHandler.swift
//  macai
//
//  Created by Renat on 19.10.2025.
//

import AppKit
import CoreData
import Foundation

private struct OpenAIModelsResponse: Codable {
    let data: [OpenAIModel]
}

private struct OpenAIModel: Codable {
    let id: String
}

class OpenAIResponsesHandler: OpenAIHandlerBase, APIService {
    private static var temperatureUnsupportedModels = Set<String>()
    private static let temperatureLock = NSLock()
    private var activeDataTask: URLSessionDataTask?
    private var activeStreamTask: Task<Void, Never>?

    func sendMessage(
        _ requestMessages: [[String: String]],
        temperature: Float,
        completion: @escaping (Result<String, APIError>) -> Void
    ) {
        func performRequest(includeTemperature: Bool) {
            let request = prepareRequest(
                requestMessages: requestMessages,
                temperature: temperature,
                stream: false,
                includeTemperature: includeTemperature
            )

            activeDataTask?.cancel()
            let task = session.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    self.activeDataTask = nil
                    let result = self.handleAPIResponse(response, data: data, error: error)

                    switch result {
                    case .success(let responseData):
                        guard let responseData = responseData,
                              let (messageContent, _) = self.parseJSONResponse(data: responseData)
                        else {
                            completion(.failure(.decodingFailed("Failed to parse response")))
                            return
                        }

                        completion(.success(messageContent))

                    case .failure(let error):
                        if includeTemperature && self.isUnsupportedTemperatureError(error) {
                            Self.markTemperatureUnsupported(for: self.model)
                            performRequest(includeTemperature: false)
                            return
                        }
                        completion(.failure(error))
                    }
                }
            }
            activeDataTask = task
            task.resume()
        }

        performRequest(includeTemperature: shouldSendTemperature())
    }

    func sendMessageStream(_ requestMessages: [[String: String]], temperature: Float) async throws
        -> AsyncThrowingStream<String, Error>
    {
        return AsyncThrowingStream { continuation in
            let request = self.prepareRequest(
                requestMessages: requestMessages,
                temperature: temperature,
                stream: true,
                includeTemperature: self.shouldSendTemperature()
            )

            let streamTask = Task {
                defer { self.activeStreamTask = nil }
                do {
                    let (stream, response) = try await session.bytes(for: request)
                    let result = self.handleAPIResponse(response, data: nil, error: nil)
                    switch result {
                    case .failure(let error):
                        var data = Data()
                        for try await byte in stream {
                            data.append(byte)
                        }
                        let apiError = APIError.serverError(
                            String(data: data, encoding: .utf8) ?? error.localizedDescription
                        )
                        if self.isUnsupportedTemperatureError(apiError) {
                            Self.markTemperatureUnsupported(for: self.model)
                        }
                        continuation.finish(throwing: apiError)
                        return
                    case .success:
                        break
                    }

                    var hasYieldedContent = false

                    for try await line in stream.lines {
                        if line.isEmpty || !self.isNotSSEComment(line) {
                            continue
                        }

                        let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmedLine.hasPrefix("event:") {
                            continue
                        }

                        let prefix = "data:"
                        var payloadString = trimmedLine
                        if trimmedLine.hasPrefix(prefix) {
                            payloadString = String(trimmedLine.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                        }

                        guard !payloadString.isEmpty else { continue }
                        if payloadString == "[DONE]" {
                            continuation.finish()
                            return
                        }

                        guard let jsonData = payloadString.data(using: .utf8) else { continue }
                        let (finished, error, messageData) = self.parseStreamResponse(data: jsonData)

                        if let error = error {
                            continuation.finish(throwing: error)
                            return
                        }

                        if let messageData = messageData, !messageData.isEmpty {
                            if finished && hasYieldedContent {
                                // Avoid replaying the full message when we've already streamed it.
                            }
                            else {
                                continuation.yield(messageData)
                                hasYieldedContent = true
                            }
                        }

                        if finished {
                            continuation.finish()
                            return
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

    func fetchModels() async throws -> [AIModel] {
        let modelsURL = baseURL
            .deletingLastPathComponent()
            .appendingPathComponent("models")

        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await session.data(for: request)

            let result = handleAPIResponse(response, data: data, error: nil)
            switch result {
            case .success(let responseData):
                guard let responseData = responseData else {
                    throw APIError.invalidResponse
                }

                let decodedResponse = try JSONDecoder().decode(OpenAIModelsResponse.self, from: responseData)
                return decodedResponse.data.map { AIModel(id: $0.id) }

            case .failure(let error):
                throw error
            }
        }
        catch {
            throw APIError.requestFailed(error)
        }
    }

    func cancelCurrentRequest() {
        activeDataTask?.cancel()
        activeStreamTask?.cancel()
    }

    private func prepareRequest(
        requestMessages: [[String: String]],
        temperature: Float,
        stream: Bool,
        includeTemperature: Bool = true
    ) -> URLRequest {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("responses=v1", forHTTPHeaderField: "OpenAI-Beta")

        if stream {
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }

        var temperatureOverride = temperature
        let normalizedModel = self.model.lowercased()

        if AppConstants.openAiReasoningModels.contains(normalizedModel) {
            temperatureOverride = 1
        }

        var processedMessages: [[String: Any]] = []

        for message in requestMessages {
            var processedMessage: [String: Any] = [:]

            let role = message["role"]
            if let role {
                processedMessage["role"] = role
            }

            if let content = message["content"] {
                let textContent = AttachmentParser.stripAttachments(from: content)

                var contentArray: [[String: Any]] = []
                let textType = role == "assistant" ? "output_text" : "input_text"

                if !textContent.isEmpty {
                    contentArray.append(["type": textType, "text": textContent])
                }

                if role != "assistant" {
                    for uuid in AttachmentParser.extractImageUUIDs(from: content) {
                        if let imageData = self.loadImageFromCoreData(uuid: uuid) {
                            contentArray.append([
                                "type": "input_image",
                                "image_url": "data:image/jpeg;base64,\(imageData.base64EncodedString())",
                            ])
                        }
                    }

                    for uuid in AttachmentParser.extractFileUUIDs(from: content) {
                        if let filePayload = self.loadFileFromCoreData(uuid: uuid) {
                            let mimeType = filePayload.mimeType ?? "application/pdf"
                            let base64 = filePayload.data.base64EncodedString()
                            let safeFilename = (filePayload.filename?.isEmpty == false)
                                ? (filePayload.filename ?? "document.pdf")
                                : "document.pdf"
                            var fileItem: [String: Any] = [
                                "type": "input_file",
                                "file_data": "data:\(mimeType);base64,\(base64)",
                                "filename": safeFilename,
                            ]
                            contentArray.append(fileItem)
                        }
                    }
                }

                processedMessage["content"] = contentArray
            }

            processedMessages.append(processedMessage)
        }

        var jsonDict: [String: Any] = [
            "model": self.model,
            "input": processedMessages,
        ]

        if includeTemperature {
            jsonDict["temperature"] = temperatureOverride
        }

        if shouldIncludeImageGenerationTool() {
            jsonDict["tools"] = [["type": "image_generation"]]
        }

        if stream {
            jsonDict["stream"] = true
        }

        request.httpBody = try? JSONSerialization.data(withJSONObject: jsonDict, options: [])

        return request
    }

    private func parseJSONResponse(data: Data) -> (String, String)? {
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            return nil
        }

        return extractMessage(from: json)
    }

    private func parseStreamResponse(data: Data) -> (Bool, APIError?, String?) {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                return (false, APIError.decodingFailed("Failed to parse streaming payload"), nil)
            }

            if let errorDict = json["error"] as? [String: Any],
               let message = errorDict["message"] as? String
            {
                return (true, APIError.serverError(message), nil)
            }

            if let type = json["type"] as? String {
                switch type {
                case "response.completed":
                    if let response = json["response"] as? [String: Any],
                       let (messageText, _) = extractMessage(from: response)
                    {
                        return (true, nil, messageText)
                    }
                    return (true, nil, nil)
                case "response.error":
                    let message = (json["message"] as? String)
                        ?? (json["error"] as? [String: Any])?["message"] as? String
                        ?? String(data: data, encoding: .utf8)
                        ?? "Unknown error"
                    return (true, APIError.serverError(message), nil)
                default:
                    if type.hasSuffix(".delta") {
                        if let deltaString = json["delta"] as? String {
                            return (false, nil, deltaString)
                        }
                        else if let deltaDict = json["delta"] as? [String: Any] {
                            let placeholders = extractImagePlaceholders(from: deltaDict)
                            if !placeholders.isEmpty {
                                return (false, nil, joinSegments(placeholders))
                            }
                        }
                    }

                    if type.hasSuffix(".done") {
                        return (false, nil, nil)
                    }
                }
            }

            if let (messageText, _) = extractMessage(from: json) {
                return (false, nil, messageText)
            }

            if let deltaString = json["delta"] as? String {
                return (false, nil, deltaString)
            }

            return (false, nil, nil)
        }
        catch {
            return (false, APIError.decodingFailed("Failed to parse JSON: \(error.localizedDescription)"), nil)
        }
    }

    private func extractMessage(from json: [String: Any]) -> (String, String)? {
        if let response = json["response"] as? [String: Any] {
            return extractMessage(from: response)
        }

        if let outputText = json["output_text"] as? String,
           !outputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            let role = json["role"] as? String ?? "assistant"
            return (outputText, role)
        }

        if let outputItems = json["output"] as? [[String: Any]] {
            return aggregateOutputItems(outputItems, fallbackRole: json["role"] as? String ?? "assistant")
        }

        if let contentItems = json["content"] as? [[String: Any]] {
            let role = json["role"] as? String ?? "assistant"
            let aggregated = aggregateContentItems(contentItems)
            return aggregated.isEmpty ? nil : (aggregated, role)
        }

        if let message = json["message"] as? [String: Any] {
            return extractMessage(from: message)
        }

        return nil
    }

    private func aggregateOutputItems(_ items: [[String: Any]], fallbackRole: String) -> (String, String)? {
        var segments: [String] = []
        var role = fallbackRole

        for item in items {
            if let itemRole = item["role"] as? String {
                role = itemRole
            }

            if let type = item["type"] as? String {
                switch type {
                case "message":
                    if let content = item["content"] as? [[String: Any]] {
                        let text = aggregateContentItems(content)
                        if !text.isEmpty { segments.append(text) }
                    }
                case "output_text":
                    if let text = item["text"] as? String ?? item["output_text"] as? String {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { segments.append(trimmed) }
                    }
                case "image_generation_call", "output_image", "image":
                    let placeholders = extractImagePlaceholders(from: item)
                    segments.append(contentsOf: placeholders)
                case "refusal":
                    if let refusal = item["refusal"] as? String {
                        segments.append(refusal)
                    }
                    else if let content = item["content"] as? [[String: Any]] {
                        let text = aggregateContentItems(content)
                        if !text.isEmpty { segments.append(text) }
                    }
                default:
                    let placeholders = extractImagePlaceholders(from: item)
                    segments.append(contentsOf: placeholders)

                    if let content = item["content"] as? [[String: Any]] {
                        let text = aggregateContentItems(content)
                        if !text.isEmpty { segments.append(text) }
                    }
                    else if let text = item["text"] as? String {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { segments.append(trimmed) }
                    }
                }
            }
            else if let content = item["content"] as? [[String: Any]] {
                let text = aggregateContentItems(content)
                if !text.isEmpty { segments.append(text) }
            }
        }

        let message = joinSegments(segments)
        return message.isEmpty ? nil : (message, role)
    }

    private func aggregateContentItems(_ items: [[String: Any]]) -> String {
        var segments: [String] = []

        for item in items {
            if let type = item["type"] as? String {
                switch type {
                case "input_text", "output_text", "text":
                    if let text = item["text"] as? String ?? item["output_text"] as? String {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { segments.append(trimmed) }
                    }
                case "image", "output_image", "image_url":
                    let placeholders = extractImagePlaceholders(from: item)
                    segments.append(contentsOf: placeholders)
                case "refusal":
                    if let refusal = item["refusal"] as? String {
                        segments.append(refusal)
                    }
                default:
                    let placeholders = extractImagePlaceholders(from: item)
                    segments.append(contentsOf: placeholders)

                    if let text = item["text"] as? String {
                        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { segments.append(trimmed) }
                    }
                }
            }
            else if let text = item["text"] as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { segments.append(trimmed) }
            }
        }

        return joinSegments(segments)
    }

    private func joinSegments(_ segments: [String]) -> String {
        segments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractImagePlaceholders(from item: [String: Any]) -> [String] {
        let payloads = collectImagePayloads(from: item)
        guard !payloads.isEmpty else { return [] }

        var seen = Set<String>()
        var placeholders: [String] = []

        for (base64, hint) in payloads {
            guard !base64.isEmpty else { continue }
            if seen.contains(base64) { continue }
            seen.insert(base64)

            if let placeholder = storeGeneratedImage(base64: base64, formatHint: hint) {
                placeholders.append(placeholder)
            }
        }

        return placeholders
    }

    private func collectImagePayloads(from item: [String: Any], formatHint: String? = nil) -> [(String, String?)] {
        var results: [(String, String?)] = []
        let currentHint = item["mime_type"] as? String
            ?? item["media_type"] as? String
            ?? item["content_type"] as? String
            ?? (item["format"] as? String)
            ?? formatHint

        if let resultString = item["result"] as? String {
            results.append((resultString, currentHint))
        }
        else if let resultArray = item["result"] as? [String] {
            results.append(contentsOf: resultArray.map { ($0, currentHint) })
        }
        else if let resultDict = item["result"] as? [String: Any] {
            results.append(contentsOf: collectImagePayloads(from: resultDict, formatHint: currentHint))
        }

        if let imageDict = item["image"] as? [String: Any] {
            results.append(contentsOf: collectImagePayloads(from: imageDict, formatHint: currentHint))
        }

        if let imagesArray = item["images"] as? [[String: Any]] {
            for image in imagesArray {
                results.append(contentsOf: collectImagePayloads(from: image, formatHint: currentHint))
            }
        }

        if let dataArray = item["data"] as? [[String: Any]] {
            for entry in dataArray {
                results.append(contentsOf: collectImagePayloads(from: entry, formatHint: currentHint))
            }
        }

        if let base64 = item["b64_json"] as? String {
            results.append((base64, currentHint))
        }

        if let base64 = item["base64"] as? String {
            results.append((base64, currentHint))
        }

        if let inlineData = item["inline_data"] as? [String: Any] {
            let inlineHint = inlineData["mime_type"] as? String ?? currentHint
            if let embedded = inlineData["data"] as? String {
                results.append((embedded, inlineHint))
            }
        }

        if let urlString = item["image_url"] as? String, urlString.starts(with: "data:image") {
            let components = urlString.split(separator: ",", maxSplits: 1).map(String.init)
            if components.count == 2 {
                let metadata = components[0]
                let base64Part = components[1]
                var hintFromUrl: String? = currentHint
                if let mimePart = metadata.split(separator: ":").last?.split(separator: ";").first {
                    hintFromUrl = String(mimePart)
                }
                results.append((base64Part, hintFromUrl))
            }
        }

        if let mediaArray = item["media"] as? [[String: Any]] {
            for media in mediaArray {
                results.append(contentsOf: collectImagePayloads(from: media, formatHint: currentHint))
            }
        }

        return results
    }

    private func storeGeneratedImage(base64: String, formatHint: String?) -> String? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        let format = determineImageFormat(for: data, hint: formatHint)
        guard let uuid = saveImageData(data, format: format) else { return nil }
        return "<image-uuid>\(uuid.uuidString)</image-uuid>"
    }

    private func determineImageFormat(for data: Data, hint: String?) -> String {
        if let normalized = normalizeFormatHint(hint) {
            return normalized
        }

        let bytes = [UInt8](data.prefix(12))

        if bytes.count >= 4 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 {
            return "png"
        }

        if bytes.count >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8 {
            return "jpeg"
        }

        if bytes.count >= 3,
           let signature = String(bytes: bytes[0..<3], encoding: .ascii),
           signature == "GIF"
        {
            return "gif"
        }

        if bytes.count >= 12,
           let riff = String(bytes: bytes[0..<4], encoding: .ascii), riff == "RIFF",
           let webp = String(bytes: bytes[8..<12], encoding: .ascii), webp == "WEBP"
        {
            return "webp"
        }

        return "jpeg"
    }

    private func normalizeFormatHint(_ hint: String?) -> String? {
        guard let hint = hint?.lowercased(), !hint.isEmpty else {
            return nil
        }

        if hint.contains("/") {
            let suffix = hint.split(separator: "/").last ?? Substring()
            let cleaned = suffix.replacingOccurrences(of: "jpg", with: "jpeg")
            return cleaned.isEmpty ? nil : cleaned
        }

        if hint == "jpg" {
            return "jpeg"
        }

        return hint
    }

    private func saveImageData(_ data: Data, format: String) -> UUID? {
        guard !data.isEmpty, let image = NSImage(data: data) else { return nil }
        let uuid = UUID()
        let context = PersistenceController.shared.container.viewContext
        var saveSucceeded = false

        context.performAndWait {
            let imageEntity = ImageEntity(context: context)
            imageEntity.id = uuid
            imageEntity.image = data
            imageEntity.imageFormat = format
            imageEntity.thumbnail = createThumbnailData(from: image)

            do {
                try context.save()
                saveSucceeded = true
            }
            catch {
                context.rollback()
                print("Error saving generated image: \(error)")
            }
        }

        return saveSucceeded ? uuid : nil
    }

    private func createThumbnailData(from image: NSImage) -> Data? {
        let thumbnailSize = CGFloat(AppConstants.thumbnailSize)
        let originalSize = image.size
        guard originalSize.width > 0, originalSize.height > 0 else { return nil }

        let aspectRatio = originalSize.width / originalSize.height
        var targetSize = CGSize(width: thumbnailSize, height: thumbnailSize)

        if aspectRatio > 1 {
            targetSize.height = thumbnailSize / aspectRatio
        }
        else {
            targetSize.width = thumbnailSize * aspectRatio
        }

        let thumbnail = NSImage(size: targetSize)
        thumbnail.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: CGRect(origin: .zero, size: targetSize), from: .zero, operation: .copy, fraction: 1.0)
        thumbnail.unlockFocus()

        guard let tiffData = thumbnail.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }

        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
    }

    private func shouldIncludeImageGenerationTool() -> Bool {
        imageGenerationSupported
    }

    private func shouldSendTemperature() -> Bool {
        let modelID = self.model.lowercased()
        Self.temperatureLock.lock()
        let isUnsupported = Self.temperatureUnsupportedModels.contains(modelID)
        Self.temperatureLock.unlock()
        return !isUnsupported
    }

    private static func markTemperatureUnsupported(for model: String) {
        temperatureLock.lock()
        temperatureUnsupportedModels.insert(model.lowercased())
        temperatureLock.unlock()
    }

    private func isUnsupportedTemperatureError(_ error: APIError) -> Bool {
        let message: String
        switch error {
        case .serverError(let text), .unknown(let text):
            message = text
        default:
            return false
        }

        let lowered = message.lowercased()
        return lowered.contains("'temperature' is not supported") || lowered.contains("unsupported parameter")
    }
}
