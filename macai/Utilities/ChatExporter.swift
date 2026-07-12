//
//  ChatExporter.swift
//  macai
//
//  Created by Renat Notfullin on 07.07.2026.
//

import AppKit
import CoreData
import Foundation
import UniformTypeIdentifiers

enum ChatExportFormat: String, CaseIterable {
    case markdown
    case plainText

    var displayName: String {
        switch self {
        case .markdown: return "Markdown"
        case .plainText: return "Plain Text"
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .plainText: return "txt"
        }
    }

    var contentType: UTType {
        switch self {
        case .markdown: return UTType(filenameExtension: "md") ?? .plainText
        case .plainText: return .plainText
        }
    }
}

/// Renders a chat transcript to Markdown or plain text for export.
struct ChatExporter {
    struct ExportMessage {
        let isUser: Bool
        let timestamp: Date
        let body: String
    }

    struct ExportImage {
        let data: Data
        let mimeType: String
    }

    static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    // MARK: - Rendering

    static func render(
        chatName: String,
        systemMessage: String?,
        messages: [ExportMessage],
        format: ChatExportFormat,
        fileNameResolver: (UUID) -> String? = { _ in nil },
        imageResolver: (UUID) -> ExportImage? = { _ in nil }
    ) -> String {
        let title = chatName.trimmingCharacters(in: .whitespacesAndNewlines)
        var sections: [String] = []

        switch format {
        case .markdown:
            var headerParts: [String] = []
            if !title.isEmpty {
                headerParts.append("# \(title)")
            }
            if let systemMessage = normalized(systemMessage), !systemMessage.isEmpty {
                let quoted = systemMessage
                    .components(separatedBy: "\n")
                    .map { "> \($0)" }
                    .joined(separator: "\n")
                headerParts.append("**System prompt:**\n\n\(quoted)")
            }
            if !headerParts.isEmpty {
                sections.append(headerParts.joined(separator: "\n\n"))
            }
            for message in messages {
                guard
                    let body = exportableBody(
                        message.body,
                        format: format,
                        fileNameResolver: fileNameResolver,
                        imageResolver: imageResolver
                    )
                else { continue }
                let role = message.isUser ? "User" : "Assistant"
                let timestamp = timestampFormatter.string(from: message.timestamp)
                sections.append("#### \(role) — \(timestamp)\n\n\(body)")
            }
            return sections.joined(separator: "\n\n---\n\n") + "\n"

        case .plainText:
            if !title.isEmpty {
                sections.append(title + "\n" + String(repeating: "=", count: min(title.count, 60)))
            }
            if let systemMessage = normalized(systemMessage), !systemMessage.isEmpty {
                sections.append("System prompt:\n\(systemMessage)")
            }
            for message in messages {
                guard let body = exportableBody(message.body, format: format, fileNameResolver: fileNameResolver)
                else { continue }
                let role = message.isUser ? "User" : "Assistant"
                let timestamp = timestampFormatter.string(from: message.timestamp)
                sections.append("\(role) — \(timestamp):\n\(body)")
            }
            return sections.joined(separator: "\n\n" + String(repeating: "-", count: 40) + "\n\n") + "\n"
        }
    }

    /// Normalizes a raw message body for export: strips reasoning blocks and
    /// replaces attachment placeholders with readable markers.
    /// Returns nil if nothing remains to export.
    static func exportableBody(
        _ body: String,
        format: ChatExportFormat,
        fileNameResolver: (UUID) -> String? = { _ in nil },
        imageResolver: (UUID) -> ExportImage? = { _ in nil }
    ) -> String? {
        var result = removingThinkingBlocks(from: body)

        result = replacingPlaceholders(in: result, tag: "image-uuid") { uuid in
            if format == .markdown, let uuid, let image = imageResolver(uuid) {
                let base64 = image.data.base64EncodedString()
                return "![Attached image](data:\(image.mimeType);base64,\(base64))"
            }
            return format == .markdown ? "*[Attached image]*" : "[Attached image]"
        }
        result = replacingPlaceholders(in: result, tag: "file-uuid") { uuid in
            let name = uuid.flatMap(fileNameResolver)
            let label = name.map { "Attached file: \($0)" } ?? "Attached file"
            return format == .markdown ? "*[\(label)]*" : "[\(label)]"
        }

        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Removes `<think>…</think>` reasoning blocks. An unterminated block is
    /// removed to the end of the string (streaming may be cut off mid-thought).
    static func removingThinkingBlocks(from text: String) -> String {
        guard text.contains("<think>") else { return text }
        var result = text
        if let regex = try? NSRegularExpression(pattern: "<think>.*?</think>", options: [.dotMatchesLineSeparators]) {
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(result.startIndex..., in: result),
                withTemplate: ""
            )
        }
        if let openRange = result.range(of: "<think>") {
            result = String(result[..<openRange.lowerBound])
        }
        return result
    }

    private static func replacingPlaceholders(
        in text: String,
        tag: String,
        replacement: (UUID?) -> String
    ) -> String {
        guard text.contains("<\(tag)>") else { return text }
        guard let regex = try? NSRegularExpression(pattern: "<\(tag)>(.*?)</\(tag)>", options: []) else { return text }

        var result = ""
        var currentIndex = text.startIndex
        let nsText = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        for match in matches {
            guard let matchRange = Range(match.range, in: text) else { continue }
            result += text[currentIndex..<matchRange.lowerBound]
            let uuidString = match.numberOfRanges > 1
                ? nsText.substring(with: match.range(at: 1))
                : ""
            result += replacement(UUID(uuidString: uuidString))
            currentIndex = matchRange.upperBound
        }
        result += text[currentIndex...]
        return result
    }

    private static func normalized(_ text: String?) -> String? {
        text?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Core Data integration

    static func export(chat: ChatEntity, format: ChatExportFormat) -> String {
        let messages = chat.messagesArray.map {
            ExportMessage(isUser: $0.own, timestamp: $0.timestamp, body: $0.body)
        }
        let context = chat.managedObjectContext
        return render(
            chatName: chat.name,
            systemMessage: chat.effectiveSystemMessage,
            messages: messages,
            format: format,
            fileNameResolver: { uuid in
                guard let context else { return nil }
                return documentFilename(for: uuid, in: context)
            },
            imageResolver: { uuid in
                guard let context else { return nil }
                return imageData(for: uuid, in: context)
            }
        )
    }

    static func export(chats: [ChatEntity], format: ChatExportFormat) -> String {
        combine(
            transcripts: chats.map { export(chat: $0, format: format) },
            format: format
        )
    }

    static func combine(transcripts: [String], format: ChatExportFormat) -> String {
        let separator = format == .markdown
            ? "\n\n---\n\n"
            : "\n\n\(String(repeating: "=", count: 60))\n\n"
        let content = transcripts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: separator)
        return content.isEmpty ? "" : content.appending("\n")
    }

    static func suggestedFileName(for chat: ChatEntity, format: ChatExportFormat) -> String {
        var name = chat.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            name = "Chat"
        }
        let invalidCharacters = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        name = name.components(separatedBy: invalidCharacters).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        if name.isEmpty {
            name = "Chat"
        }
        return "\(name).\(format.fileExtension)"
    }

    static func suggestedFileName(chatCount: Int, format: ChatExportFormat) -> String {
        "\(chatCount) Chats.\(format.fileExtension)"
    }

    private static func documentFilename(for uuid: UUID, in context: NSManagedObjectContext) -> String? {
        var filename: String?
        context.performAndWait {
            let fetchRequest: NSFetchRequest<DocumentEntity> = DocumentEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
            fetchRequest.fetchLimit = 1
            filename = (try? context.fetch(fetchRequest))?.first?.filename
        }
        return filename
    }

    private static func imageData(for uuid: UUID, in context: NSManagedObjectContext) -> ExportImage? {
        var exportImage: ExportImage?
        context.performAndWait {
            let fetchRequest: NSFetchRequest<ImageEntity> = ImageEntity.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
            fetchRequest.fetchLimit = 1
            guard let entity = (try? context.fetch(fetchRequest))?.first, let data = entity.image else { return }
            exportImage = ExportImage(data: data, mimeType: mimeType(forImageFormat: entity.imageFormat))
        }
        return exportImage
    }

    private static func mimeType(forImageFormat format: String?) -> String {
        switch format?.lowercased() {
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "tiff", "tif": return "image/tiff"
        case "bmp": return "image/bmp"
        default: return "image/jpeg"
        }
    }

    // MARK: - Save panel

    static func exportWithSavePanel(chat: ChatEntity, format: ChatExportFormat) {
        exportWithSavePanel(chats: [chat], format: format)
    }

    static func exportWithSavePanel(chats: [ChatEntity], format: ChatExportFormat) {
        guard !chats.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = chats.count == 1
            ? suggestedFileName(for: chats[0], format: format)
            : suggestedFileName(chatCount: chats.count, format: format)
        panel.title = chats.count == 1 ? "Export Chat" : "Export \(chats.count) Chats"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Render and write off the main thread: embedding images base64-encodes
        // potentially many megabytes of data.
        let chatIDs = chats.map(\.objectID)
        guard chatIDs.allSatisfy({ !$0.isTemporaryID }),
              let coordinator = chats[0].managedObjectContext?.persistentStoreCoordinator else {
            writeExport(export(chats: chats, format: format), to: url)
            return
        }

        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        context.perform {
            let backgroundChats = chatIDs.compactMap {
                try? context.existingObject(with: $0) as? ChatEntity
            }
            guard !backgroundChats.isEmpty else { return }
            let content = export(chats: backgroundChats, format: format)
            writeExport(content, to: url)
        }
    }

    private static func writeExport(_ content: String, to url: URL) {
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Export Failed"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.presentAsSheetOrModal { _ in }
            }
        }
    }
}
