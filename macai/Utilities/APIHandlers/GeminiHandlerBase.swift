//
//  GeminiHandlerBase.swift
//  macai
//
//  Created by Renat on 07.02.2025.
//

import AppKit
import CoreData
import Foundation

// MARK: - Shared Data Structures

struct GeminiContentRequest: Encodable {
    let role: String?
    let parts: [GeminiPartRequest]
}

struct GeminiPartRequest: Codable {
    let text: String?
    let inlineData: GeminiInlineData?
    let thoughtSignature: String?

    init(text: String, thoughtSignature: String? = nil) {
        self.text = text
        self.inlineData = nil
        self.thoughtSignature = thoughtSignature
    }

    init(inlineData: GeminiInlineData, thoughtSignature: String? = nil) {
        self.text = nil
        self.inlineData = inlineData
        self.thoughtSignature = thoughtSignature
    }
}

struct GeminiInlineData: Codable {
    let mimeType: String
    let data: String
}

struct PartsEnvelope: Codable {
    let serviceType: String
    let parts: [GeminiPartRequest]
}

// MARK: - Internal Response Structures

struct GeminiGenerateRequest: Encodable {
    let contents: [GeminiContentRequest]
    let systemInstruction: GeminiContentRequest?
    let generationConfig: GeminiGenerationConfig?
}

struct GeminiGenerationConfig: Encodable {
    let temperature: Float
}

struct GeminiGenerateResponse: Decodable {
    let candidates: [GeminiCandidate]?
}

struct GeminiCandidate: Decodable {
    let content: GeminiContentResponse?
    let finishReason: String?
}

struct GeminiContentResponse: Decodable {
    let parts: [GeminiPartResponse]?
}

struct GeminiPartResponse: Decodable {
    let text: String?
    let inlineData: GeminiInlineDataResponse?
    let thoughtSignature: String?
}

struct GeminiInlineDataResponse: Decodable {
    let mimeType: String?
    let data: String?
}

struct GeminiErrorEnvelope: Decodable {
    let error: GeminiAPIError
}

struct GeminiAPIError: Decodable {
    let code: Int?
    let message: String
    let status: String?
}

struct GeminiStreamParseResult {
    let delta: String?
    let finished: Bool
}

// MARK: - Base Handler Class

class GeminiHandlerBase: APIService {
    let name: String
    let baseURL: URL
    let model: String
    let session: URLSession
    var activeDataTask: URLSessionDataTask?
    var activeStreamTask: Task<Void, Never>?
    var lastResponseParts: [GeminiPartResponse]?

    init(config: APIServiceConfiguration, session: URLSession) {
        self.name = config.name
        self.baseURL = config.apiUrl
        self.model = config.model
        self.session = session
    }

    // MARK: - Abstract Methods (to be overridden by subclasses)

    func fetchModels() async throws -> [AIModel] {
        fatalError("Subclasses must override fetchModels()")
    }

    func prepareRequest(
        requestMessages: [[String: String]],
        temperature: Float,
        stream: Bool
    ) -> Result<URLRequest, APIError> {
        fatalError("Subclasses must override prepareRequest()")
    }

    func buildRequestURL(stream: Bool) -> URL? {
        fatalError("Subclasses must override buildRequestURL()")
    }

    // MARK: - APIService Protocol Implementation

    func sendMessage(
        _ requestMessages: [[String: String]],
        temperature: Float,
        completion: @escaping (Result<String, APIError>) -> Void
    ) {
        let requestResult = prepareRequest(
            requestMessages: requestMessages,
            temperature: temperature,
            stream: false
        )

        switch requestResult {
        case .failure(let error):
            DispatchQueue.main.async {
                completion(.failure(error))
            }
            return

        case .success(let request):
            activeDataTask?.cancel()
            let task = session.dataTask(with: request) { data, response, error in
                DispatchQueue.main.async {
                    self.activeDataTask = nil
                    let result = self.handleAPIResponse(response, data: data, error: error)

                    switch result {
                    case .success(let payload):
                        guard let payload = payload else {
                            completion(.failure(.invalidResponse))
                            return
                        }

                        do {
                            let decoder = self.makeDecoder()
                            let response = try decoder.decode(GeminiGenerateResponse.self, from: payload)
                            self.lastResponseParts = response.candidates?.first?.content?.parts
                            var inlineDataCache: [String: String] = [:]
                            if let message = self.renderMessage(from: response, inlineDataCache: &inlineDataCache) {
                                completion(.success(message))
                            }
                            else {
                                completion(.failure(.decodingFailed("Empty Gemini response")))
                            }
                        }
                        catch {
                            if let envelope = try? self.makeDecoder().decode(GeminiErrorEnvelope.self, from: payload) {
                                completion(.failure(.serverError(envelope.error.message)))
                            }
                            else {
                                completion(.failure(.decodingFailed("Failed to decode Gemini response: \(error.localizedDescription)")))
                            }
                        }

                    case .failure(let error):
                        completion(.failure(error))
                    }
                }
            }
            activeDataTask = task
            task.resume()
        }
    }

    func sendMessageStream(_ requestMessages: [[String: String]], temperature: Float) async throws
        -> AsyncThrowingStream<String, Error>
    {
        let requestResult = prepareRequest(
            requestMessages: requestMessages,
            temperature: temperature,
            stream: true
        )

        switch requestResult {
        case .failure(let error):
            throw error

        case .success(let request):
            return AsyncThrowingStream { continuation in
                let streamTask = Task {
                    defer { self.activeStreamTask = nil }
                    do {
                        let (stream, response) = try await self.session.bytes(for: request)
                        let responseCheck = self.handleAPIResponse(response, data: nil, error: nil)

                        switch responseCheck {
                        case .failure(let error):
                            var errorData = Data()
                            for try await byte in stream {
                                errorData.append(byte)
                            }

                            if let envelope = try? self.makeDecoder().decode(GeminiErrorEnvelope.self, from: errorData) {
                                continuation.finish(throwing: APIError.serverError(envelope.error.message))
                            }
                            else {
                                let message = String(data: errorData, encoding: .utf8) ?? error.localizedDescription
                                continuation.finish(throwing: APIError.serverError(message))
                            }
                            return

                        case .success:
                            break
                        }

                        let decoder = self.makeDecoder()
                        var aggregatedText = ""
                        var inlineDataCache: [String: String] = [:]

                        for try await line in stream.lines {
                            if line.isEmpty { continue }

                            if line.hasPrefix("data:") {
                                let index = line.index(line.startIndex, offsetBy: "data:".count)
                                let payload = String(line[index...]).trimmingCharacters(in: .whitespacesAndNewlines)

                                if payload.isEmpty { continue }

                                let result = try self.parseStreamPayload(
                                    payload,
                                    decoder: decoder,
                                    aggregatedText: &aggregatedText,
                                    inlineDataCache: &inlineDataCache
                                )

                                if let delta = result.delta, !delta.isEmpty {
                                    continuation.yield(delta)
                                }

                                if result.finished {
                                    continuation.finish()
                                    return
                                }
                            }
                        }

                        continuation.finish()
                    }
                    catch let apiError as APIError {
                        continuation.finish(throwing: apiError)
                    }
                    catch {
                        continuation.finish(throwing: APIError.requestFailed(error))
                    }
                }
                activeStreamTask?.cancel()
                activeStreamTask = streamTask
                continuation.onTermination = { _ in
                    streamTask.cancel()
                }
            }
        }
    }

    func cancelCurrentRequest() {
        activeDataTask?.cancel()
        activeStreamTask?.cancel()
    }

    // MARK: - Message Transformation

    func transformMessages(_ requestMessages: [[String: String]]) -> (
        GeminiContentRequest?,
        [GeminiContentRequest]
    ) {
        var systemInstruction: GeminiContentRequest?
        var contents: [GeminiContentRequest] = []
        let requiresThoughtSignatures = model.lowercased().contains("gemini-3")

        for message in requestMessages {
            guard let role = message["role"], let content = message["content"] else { continue }
            let storedParts = decodeStoredParts(from: message["message_parts"])

            switch role {
            case "system":
                let text = Self.stripImagePlaceholders(from: content).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                systemInstruction = GeminiContentRequest(
                    role: "system",
                    parts: [GeminiPartRequest(text: text)]
                )
            case "assistant":
                let parts = storedParts ?? buildParts(from: content, allowInlineData: true)
                // For Gemini 3 models, we must include thought signatures; if missing, skip to avoid INVALID_ARGUMENT.
                if requiresThoughtSignatures, !parts.contains(where: { $0.thoughtSignature != nil }) {
                    continue
                }
                guard !parts.isEmpty else { continue }
                contents.append(
                    GeminiContentRequest(
                        role: "model",
                        parts: parts
                    )
                )
            default:
                let parts = storedParts ?? buildParts(from: content, allowInlineData: true)
                guard !parts.isEmpty else { continue }
                contents.append(
                    GeminiContentRequest(
                        role: "user",
                        parts: parts
                    )
                )
            }
        }

        return (systemInstruction, contents)
    }

    func buildParts(from content: String, allowInlineData: Bool) -> [GeminiPartRequest] {
        var parts: [GeminiPartRequest] = []

        let pattern = "<image-uuid>(.*?)</image-uuid>"
        let regex = try? NSRegularExpression(pattern: pattern, options: [])
        let nsString = content as NSString
        let fullRange = NSRange(location: 0, length: nsString.length)

        var currentLocation = 0
        let matches = regex?.matches(in: content, options: [], range: fullRange) ?? []

        for match in matches {
            let matchRange = match.range
            let textLength = matchRange.location - currentLocation
            if textLength > 0 {
                let textSegment = nsString.substring(with: NSRange(location: currentLocation, length: textLength))
                if !textSegment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    parts.append(GeminiPartRequest(text: textSegment))
                }
            }

            if allowInlineData, match.numberOfRanges > 1 {
                let uuidRange = match.range(at: 1)
                let uuidString = nsString.substring(with: uuidRange)
                if let uuid = UUID(uuidString: uuidString),
                    let image = loadImageFromCoreData(uuid: uuid)
                {
                    let base64 = image.data.base64EncodedString()
                    let inlineData = GeminiInlineData(mimeType: image.mimeType, data: base64)
                    parts.append(GeminiPartRequest(inlineData: inlineData))
                }
            }

            currentLocation = matchRange.location + matchRange.length
        }

        let remainingLength = nsString.length - currentLocation
        if remainingLength > 0 {
            let trailingText = nsString.substring(with: NSRange(location: currentLocation, length: remainingLength))
            if !trailingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parts.append(GeminiPartRequest(text: trailingText))
            }
        }

        if parts.isEmpty {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                parts.append(GeminiPartRequest(text: content))
            }
        }

        return parts
    }

    func decodeStoredParts(from base64: String?) -> [GeminiPartRequest]? {
        guard let base64 = base64, let data = Data(base64Encoded: base64) else { return nil }
        // Expect a vendor-tagged envelope
        if let envelope = try? JSONDecoder().decode(PartsEnvelope.self, from: data),
           envelope.serviceType.lowercased() == "gemini" || envelope.serviceType.lowercased() == "vertex" {
            return envelope.parts
        }
        // Legacy direct array encoding
        if let parts = try? JSONDecoder().decode([GeminiPartRequest].self, from: data) {
            return parts
        }
        return nil
    }

    static func stripImagePlaceholders(from content: String) -> String {
        let pattern = "<image-uuid>.*?</image-uuid>"
        return content.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Response Handling

    func handleAPIResponse(_ response: URLResponse?, data: Data?, error: Error?) -> Result<Data?, APIError> {
        if let error = error {
            return .failure(.requestFailed(error))
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            return .failure(.invalidResponse)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            var message = "HTTP \(httpResponse.statusCode)"

            if let data = data {
                if let decodedError = try? makeDecoder().decode(GeminiErrorEnvelope.self, from: data) {
                    message = decodedError.error.message
                }
                else if let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
                    message = raw
                }
            }

            switch httpResponse.statusCode {
            case 400:
                return .failure(.serverError("Bad Request: \(message)"))
            case 401, 403:
                return .failure(.unauthorized)
            case 429:
                return .failure(.rateLimited)
            case 500...599:
                return .failure(.serverError("Gemini API Error: \(message)"))
            default:
                return .failure(.unknown(message))
            }
        }

        return .success(data)
    }

    func renderMessage(
        from response: GeminiGenerateResponse,
        inlineDataCache: inout [String: String]
    ) -> String? {
        guard let candidate = response.candidates?.first,
            let parts = candidate.content?.parts
        else {
            return nil
        }

        var message = ""

        for part in parts {
            if let text = part.text, !text.isEmpty {
                message += text
            }

            if let inline = part.inlineData,
                let base64 = inline.data
            {
                let normalized = base64.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !normalized.isEmpty else { continue }

                if let cached = inlineDataCache[normalized] {
                    appendInlinePlaceholder(cached, to: &message)
                    continue
                }

                if let placeholder = storeInlineImage(base64: normalized, mimeType: inline.mimeType) {
                    inlineDataCache[normalized] = placeholder
                    appendInlinePlaceholder(placeholder, to: &message)
                }
            }
        }

        while message.hasSuffix("\n") {
            message.removeLast()
        }

        return message.isEmpty ? nil : message
    }

    func parseStreamPayload(
        _ payload: String,
        decoder: JSONDecoder,
        aggregatedText: inout String,
        inlineDataCache: inout [String: String]
    ) throws -> GeminiStreamParseResult {
        if payload == "[DONE]" {
            return GeminiStreamParseResult(delta: nil, finished: true)
        }

        guard let data = payload.data(using: .utf8) else {
            return GeminiStreamParseResult(delta: nil, finished: false)
        }

        if let response = try? decoder.decode(GeminiGenerateResponse.self, from: data) {
            lastResponseParts = response.candidates?.first?.content?.parts
            let delta = extractDelta(
                from: response,
                aggregatedText: &aggregatedText,
                inlineDataCache: &inlineDataCache
            )
            let finished = shouldFinish(after: response)
            return GeminiStreamParseResult(delta: delta, finished: finished)
        }

        if let envelope = try? decoder.decode(GeminiErrorEnvelope.self, from: data) {
            throw APIError.serverError(envelope.error.message)
        }

        if let stringPayload = try? decoder.decode(String.self, from: data) {
            let delta = mergeRawDelta(stringPayload, aggregatedText: &aggregatedText)
            return GeminiStreamParseResult(delta: delta, finished: false)
        }

        if let plain = String(data: data, encoding: .utf8), !plain.isEmpty {
            let delta = mergeRawDelta(plain, aggregatedText: &aggregatedText)
            return GeminiStreamParseResult(delta: delta, finished: false)
        }

        return GeminiStreamParseResult(delta: nil, finished: false)
    }

    func extractDelta(
        from response: GeminiGenerateResponse,
        aggregatedText: inout String,
        inlineDataCache: inout [String: String]
    ) -> String? {
        guard let message = renderMessage(from: response, inlineDataCache: &inlineDataCache) else {
            return nil
        }

        return mergeRawDelta(message, aggregatedText: &aggregatedText)
    }

    func mergeRawDelta(_ fragment: String, aggregatedText: inout String) -> String? {
        guard !fragment.isEmpty else { return nil }

        if aggregatedText.isEmpty {
            aggregatedText = fragment
            return fragment
        }

        if fragment == aggregatedText {
            return nil
        }

        if fragment.hasPrefix(aggregatedText) {
            let delta = String(fragment.dropFirst(aggregatedText.count))
            aggregatedText = fragment
            return delta.isEmpty ? nil : delta
        }

        let commonPrefix = fragment.commonPrefix(with: aggregatedText)
        if !commonPrefix.isEmpty {
            let delta = String(fragment.dropFirst(commonPrefix.count))
            aggregatedText = fragment
            return delta.isEmpty ? nil : delta
        }

        aggregatedText.append(fragment)
        return fragment
    }

    func shouldFinish(after response: GeminiGenerateResponse) -> Bool {
        guard let candidates = response.candidates else { return false }
        for candidate in candidates {
            if let reason = candidate.finishReason, isTerminalFinishReason(reason) {
                return true
            }
        }
        return false
    }

    func isTerminalFinishReason(_ reason: String) -> Bool {
        switch reason.uppercased() {
        case "STOP", "MAX_TOKENS", "SAFETY", "RECITATION", "BLOCKLIST", "OTHER":
            return true
        default:
            return false
        }
    }

    // MARK: - Response Parts

    func consumeLastResponseParts() -> [GeminiPartRequest]? {
        defer { lastResponseParts = nil }
        guard let parts = lastResponseParts else { return nil }
        let requestParts: [GeminiPartRequest] = parts.compactMap { responsePart in
            if let text = responsePart.text {
                return GeminiPartRequest(text: text, thoughtSignature: responsePart.thoughtSignature)
            }
            if let mime = responsePart.inlineData?.mimeType,
               let data = responsePart.inlineData?.data {
                return GeminiPartRequest(
                    inlineData: GeminiInlineData(mimeType: mime, data: data),
                    thoughtSignature: responsePart.thoughtSignature
                )
            }
            return nil
        }
        return requestParts.isEmpty ? nil : requestParts
    }

    // MARK: - Helpers

    func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    func appendInlinePlaceholder(_ placeholder: String, to message: inout String) {
        if !message.isEmpty, !message.hasSuffix("\n") {
            message += "\n"
        }

        message += placeholder

        if !message.hasSuffix("\n") {
            message += "\n"
        }
    }

    func normalizedModelIdentifier() -> String {
        if model.hasPrefix("models/") {
            return model.replacingOccurrences(of: "models/", with: "")
        }
        return model
    }

    // MARK: - Image Handling

    func storeInlineImage(base64: String, mimeType: String?) -> String? {
        guard let data = Data(base64Encoded: base64) else { return nil }
        let format = formatFromMimeType(mimeType)

        guard let uuid = saveImageData(data, format: format) else {
            return nil
        }

        return "<image-uuid>\(uuid.uuidString)</image-uuid>"
    }

    func saveImageData(_ data: Data, format: String) -> UUID? {
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
                print("Error saving generated image: \(error)")
                context.rollback()
            }
        }

        return saveSucceeded ? uuid : nil
    }

    func createThumbnailData(from image: NSImage) -> Data? {
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

    func formatFromMimeType(_ mimeType: String?) -> String {
        switch mimeType?.lowercased() {
        case "image/png":
            return "png"
        case "image/gif":
            return "gif"
        case "image/webp":
            return "webp"
        case "image/heic", "image/heif":
            return "heic"
        case "image/jpg":
            return "jpeg"
        default:
            return "jpeg"
        }
    }

    func loadImageFromCoreData(uuid: UUID) -> (data: Data, mimeType: String)? {
        let viewContext = PersistenceController.shared.container.viewContext

        let fetchRequest: NSFetchRequest<ImageEntity> = ImageEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
        fetchRequest.fetchLimit = 1

        do {
            let results = try viewContext.fetch(fetchRequest)
            if let imageEntity = results.first, let imageData = imageEntity.image {
                let format = imageEntity.imageFormat ?? "jpeg"
                return (imageData, mimeTypeForImageFormat(format))
            }
        }
        catch {
            print("Error fetching image from CoreData: \(error)")
        }

        return nil
    }

    func mimeTypeForImageFormat(_ format: String) -> String {
        switch format.lowercased() {
        case "png":
            return "image/png"
        case "heic", "heif":
            return "image/heic"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"
        default:
            return "image/jpeg"
        }
    }
}

