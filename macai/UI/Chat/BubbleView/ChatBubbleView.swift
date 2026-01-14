//
//  ChatBubbleView.swift
//  macai
//
//  Created by Renat Notfullin on 18.03.2023.
//

import AppKit
import CoreData
import Foundation
import SwiftUI

enum MessageElements {
    case text(String)
    case table(header: [String], data: [[String]])
    case code(code: String, lang: String, indent: Int)
    case formula(String)
    case thinking(String, isExpanded: Bool)
    case image(NSImage, UUID)
    case file(FileAttachmentInfo)
}

struct FileAttachmentInfo: Identifiable {
    let id: UUID
    let filename: String
    let mimeType: String?
}

struct ChatBubbleContent: Equatable {
    let message: String
    let own: Bool
    let waitingForResponse: Bool?
    let errorMessage: ErrorMessage?
    let systemMessage: Bool
    let isStreaming: Bool
    let isLatestMessage: Bool
    let reasoningDuration: TimeInterval?
    let isActiveReasoning: Bool

    static func == (lhs: ChatBubbleContent, rhs: ChatBubbleContent) -> Bool {
        return lhs.message == rhs.message && lhs.own == rhs.own && lhs.waitingForResponse == rhs.waitingForResponse
            && lhs.systemMessage == rhs.systemMessage && lhs.isStreaming == rhs.isStreaming
            && lhs.isLatestMessage == rhs.isLatestMessage && lhs.reasoningDuration == rhs.reasoningDuration
            && lhs.isActiveReasoning == rhs.isActiveReasoning
    }
}

struct ChatBubbleView: View, Equatable {
    let content: ChatBubbleContent
    var message: MessageEntity?
    var color: String?
    var onEdit: (() -> Void)?
    @Binding var searchText: String
    var currentSearchOccurrence: SearchOccurrence?

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.managedObjectContext) private var viewContext
    private let outgoingBubbleColorLight = Color(red: 0.92, green: 0.92, blue: 0.92)
    private let outgoingBubbleColorDark = Color(red: 0.3, green: 0.3, blue: 0.3)
    private let incomingBubbleColorLight = Color(.white).opacity(0)
    private let incomingBubbleColorDark = Color(.white).opacity(0)
    private let incomingLabelColor = NSColor.labelColor
    @State private var isHovered = false
    @State private var showingDeleteConfirmation = false
    @State private var isCopied = false
    @AppStorage("chatFontSize") private var chatFontSize: Double = 14.0

    private var effectiveFontSize: Double {
        chatFontSize
    }

    static func == (lhs: ChatBubbleView, rhs: ChatBubbleView) -> Bool {
        lhs.content == rhs.content && lhs.currentSearchOccurrence == rhs.currentSearchOccurrence
    }

    var body: some View {
        let prefetchedElements = prefetchedElementsIfNeeded(from: content.message)
        let attachments = prefetchedElements.map(extractAttachments) ?? []

        VStack {
            HStack {
                if content.own {
                    Color.clear
                        .frame(width: 80)
                    Spacer()
                }
                VStack(alignment: content.own ? .trailing : .leading, spacing: 6) {
                    if content.own,
                       !(content.waitingForResponse ?? false),
                       content.errorMessage == nil,
                       !attachments.isEmpty
                    {
                        attachmentRow(attachments: attachments)
                    }

                    bubbleContent(prefetchedElements: prefetchedElements)
                }

                if !content.own {
                    Spacer()
                }
            }

            if content.errorMessage == nil && !(content.waitingForResponse ?? false) {
                HStack {
                    if content.own {
                        Spacer()
                        toolbarContent
                            .padding(.trailing, 6)
                            .onHover { hovering in
                                if hovering {
                                    self.isHovered = true
                                }
                            }
                    }
                    else {
                        toolbarContent
                            .padding(.leading, 12)
                            .onHover { hovering in
                                if hovering {
                                    self.isHovered = true
                                }
                            }
                        Spacer()
                    }
                }
                .frame(height: 12)
                .transition(.opacity)
                .opacity(isHovered ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: isHovered)
            }
            else {
                Color.clear.frame(height: 12)
            }
        }
        .padding(.vertical, 8)
        .background(
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
        )
        .onHover { isHovered in
            self.isHovered = isHovered
        }
        .alert(isPresented: $showingDeleteConfirmation) {
            Alert(
                title: Text("Delete Message"),
                message: Text("Are you sure you want to delete this message?"),
                primaryButton: .destructive(Text("Delete")) {
                    deleteMessage()
                },
                secondaryButton: .cancel()
            )
        }
    }

    @ViewBuilder
    private func bubbleContent(prefetchedElements: [MessageElements]?) -> some View {
        Group {
            if content.waitingForResponse ?? false {
                HStack {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 6, height: 6)
                        .modifier(PulsatingCircle())
                        .padding(.top, 4)
                    Text("Thinking")
                        .foregroundColor(.primary)
                        .font(.system(size: 14))
                }
            }
            else if let errorMessage = content.errorMessage {
                ErrorBubbleView(
                    error: errorMessage,
                    onRetry: {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("RetryMessage"),
                            object: nil
                        )
                    },
                    onIgnore: {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("IgnoreError"),
                            object: nil
                        )
                    }
                )
            }
            else {
                MessageContentView(
                    message: message,
                    content: content.message,
                    isStreaming: content.isStreaming,
                    own: content.own,
                    effectiveFontSize: effectiveFontSize,
                    colorScheme: colorScheme,
                    inlineAttachments: !content.own,
                    reasoningDuration: content.reasoningDuration,
                    isActiveReasoning: content.isActiveReasoning,
                    prefetchedElements: prefetchedElements,
                    searchText: $searchText,
                    currentSearchOccurrence: currentSearchOccurrence
                )
            }
        }
        .foregroundColor(Color(content.own ? incomingLabelColor : incomingLabelColor))
        .multilineTextAlignment(.leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            content.systemMessage
                ? (color != nil ? (Color(hex: color!) ?? Color(NSColor.systemGray)) : Color(NSColor.systemGray)).opacity(0.6)
                : colorScheme == .dark
                    ? (content.own ? outgoingBubbleColorDark : incomingBubbleColorDark)
                    : (content.own ? outgoingBubbleColorLight : incomingBubbleColorLight)
        )
        .cornerRadius(16)
    }

    private func prefetchedElementsIfNeeded(from message: String) -> [MessageElements]? {
        guard content.own else { return nil }
        guard message.contains("<image-uuid>") || message.contains("<file-uuid>") else { return nil }
        let parser = MessageParser(colorScheme: colorScheme)
        return parser.parseMessageFromString(input: message)
    }

    private func extractAttachments(from elements: [MessageElements]) -> [MessageElements] {
        elements.compactMap { element in
            switch element {
            case .image, .file:
                return element
            default:
                return nil
            }
        }
    }

    @ViewBuilder
    private func attachmentRow(attachments: [MessageElements]) -> some View {
        let tileSize: CGFloat = 160
        let spacing: CGFloat = 8
        let previewRequests = attachmentPreviewRequests(from: attachments)
        let previewIndexById = previewRequests.enumerated().reduce(into: [UUID: Int]()) { result, entry in
            result[entry.element.id] = entry.offset
        }
        TrailingAttachmentFlowLayout(
            itemSize: CGSize(width: tileSize, height: tileSize),
            spacing: spacing
        ) {
            ForEach(attachments.indices, id: \.self) { index in
                let attachment = attachments[index]
                attachmentTileView(
                    attachment: attachment,
                    tileSize: tileSize,
                    previewIndexById: previewIndexById,
                    previewRequests: previewRequests
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
    
    @ViewBuilder
    private func attachmentTileView(
        attachment: MessageElements,
        tileSize: CGFloat,
        previewIndexById: [UUID: Int],
        previewRequests: [QuickLookPreviewer.PreviewItemRequest]
    ) -> some View {
        switch attachment {
        case .image(let image, let id):
            ImageAttachmentTileView(
                image: image,
                size: tileSize,
                onPreview: {
                    if let index = previewIndexById[id] {
                        QuickLookPreviewer.shared.preview(requests: previewRequests, selectedIndex: index)
                    }
                }
            )
        case .file(let fileInfo):
            PDFAttachmentTileView(
                fileInfo: fileInfo,
                size: tileSize,
                onPreview: {
                    if let index = previewIndexById[fileInfo.id] {
                        QuickLookPreviewer.shared.preview(requests: previewRequests, selectedIndex: index)
                    }
                }
            )
        default:
            EmptyView()
        }
    }

    private func attachmentPreviewRequests(from attachments: [MessageElements]) -> [QuickLookPreviewer.PreviewItemRequest] {
        attachments.map(makePreviewRequest)
    }

    private func makePreviewRequest(for element: MessageElements) -> QuickLookPreviewer.PreviewItemRequest {
        switch element {
        case .image(_, let id):
            if let cached = PreviewFileHelper.cachedPreviewURL(for: id) {
                return QuickLookPreviewer.PreviewItemRequest(
                    id: id,
                    title: cached.lastPathComponent,
                    url: cached
                )
            }
            return QuickLookPreviewer.PreviewItemRequest(id: id, title: "Image.jpg") { completion in
                PersistenceController.shared.container.performBackgroundTask { context in
                    let fetchRequest: NSFetchRequest<ImageEntity> = ImageEntity.fetchRequest()
                    fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
                    fetchRequest.fetchLimit = 1

                    guard let imageEntity = try? context.fetch(fetchRequest).first,
                          let imageData = imageEntity.image else {
                        completion(nil)
                        return
                    }

                    let rawExtension = (imageEntity.imageFormat?.isEmpty == false)
                        ? imageEntity.imageFormat!.lowercased()
                        : "jpg"
                    let fileExtension = (rawExtension == "jpeg") ? "jpg" : rawExtension
                    let filename = "Image.\(fileExtension)"
                    let url = PreviewFileHelper.previewURL(
                        for: id,
                        data: imageData,
                        filename: filename,
                        defaultExtension: fileExtension
                    )
                    completion(url)
                }
            }
        case .file(let fileInfo):
            let displayName = fileInfo.filename.isEmpty ? "Document.pdf" : fileInfo.filename
            if let cached = PreviewFileHelper.cachedPreviewURL(for: fileInfo.id) {
                return QuickLookPreviewer.PreviewItemRequest(
                    id: fileInfo.id,
                    title: displayName,
                    url: cached
                )
            }
            return QuickLookPreviewer.PreviewItemRequest(id: fileInfo.id, title: displayName) { completion in
                PersistenceController.shared.container.performBackgroundTask { context in
                    let fetchRequest: NSFetchRequest<DocumentEntity> = DocumentEntity.fetchRequest()
                    fetchRequest.predicate = NSPredicate(format: "id == %@", fileInfo.id as CVarArg)
                    fetchRequest.fetchLimit = 1

                    guard let documentEntity = try? context.fetch(fetchRequest).first,
                          let fileData = documentEntity.fileData else {
                        completion(nil)
                        return
                    }

                    let suggestedName = fileInfo.filename.isEmpty ? "Document.pdf" : fileInfo.filename
                    let baseName = URL(fileURLWithPath: suggestedName).deletingPathExtension().lastPathComponent
                    let name = "\(baseName).pdf"
                    let url = PreviewFileHelper.previewURL(
                        for: fileInfo.id,
                        data: fileData,
                        filename: name,
                        defaultExtension: "pdf"
                    )
                    completion(url)
                }
            }
        default:
            return QuickLookPreviewer.PreviewItemRequest(id: UUID(), title: nil, url: nil)
        }
    }


    private func copyMessageToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        markCopied()
    }

    private func copyFirstImageToClipboard() {
        let imageIDs = AttachmentParser.extractImageUUIDs(from: content.message)
        guard let firstID = imageIDs.first,
              let image = loadImageFromCoreData(id: firstID) else {
            return
        }

        AttachmentActionHelper.copyImage(image)
        markCopied()
    }

    private func loadImageFromCoreData(id: UUID) -> NSImage? {
        let fetchRequest: NSFetchRequest<ImageEntity> = ImageEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        fetchRequest.fetchLimit = 1

        guard let imageEntity = try? viewContext.fetch(fetchRequest).first,
              let imageData = imageEntity.image else {
            return nil
        }

        return NSImage(data: imageData)
    }

    private func markCopied() {
        withAnimation {
            isCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            withAnimation {
                isCopied = false
            }
        }
    }

    private func deleteMessage() {
        guard let messageEntity = message else { return }
        viewContext.delete(messageEntity)
        do {
            try viewContext.save()
        }
        catch {
            print("Error deleting message: \(error)")
        }
    }

    private var toolbarContent: some View {
        HStack(spacing: 12) {
            let isImageOnlyMessage = AttachmentParser.stripAttachments(from: content.message).isEmpty
                && !AttachmentParser.extractImageUUIDs(from: content.message).isEmpty
                && AttachmentParser.extractFileUUIDs(from: content.message).isEmpty
            let copyIcon = isImageOnlyMessage ? "photo" : "doc.on.doc"
            if content.systemMessage {
                ToolbarButton(
                    icon: "pencil",
                    text: "Edit",
                    action: {
                        onEdit?()
                    }
                )
            }

            if content.isLatestMessage && !content.systemMessage {
                ToolbarButton(
                    icon: "arrow.clockwise",
                    text: "Retry",
                    action: {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("RetryMessage"),
                            object: nil
                        )
                    }
                )
            }

            ToolbarButton(
                icon: isCopied ? "checkmark" : copyIcon,
                text: "Copy",
                action: {
                    if isImageOnlyMessage {
                        copyFirstImageToClipboard()
                    }
                    else {
                        copyMessageToClipboard(content.message)
                    }
                }
            )

            if !content.systemMessage {
                ToolbarButton(
                    icon: "trash",
                    text: "",  // No text for delete button
                    action: {
                        showingDeleteConfirmation = true
                    }
                )
            }
        }
    }
}

private struct TrailingAttachmentFlowLayout: Layout {
    var itemSize: CGSize
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }

        let availableWidth = proposal.width ?? idealWidth(for: subviews.count)
        let itemsPerRow = itemsPerRow(for: availableWidth, fallbackCount: subviews.count)
        let rowCount = Int(ceil(Double(subviews.count) / Double(itemsPerRow)))
        let height = CGFloat(rowCount) * itemSize.height + CGFloat(max(0, rowCount - 1)) * spacing

        if let proposedWidth = proposal.width {
            return CGSize(width: proposedWidth, height: height)
        }

        let maxItemsInRow = min(itemsPerRow, subviews.count)
        let width = CGFloat(maxItemsInRow) * itemSize.width + CGFloat(max(0, maxItemsInRow - 1)) * spacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }

        let availableWidth = bounds.width
        let itemsPerRow = itemsPerRow(for: availableWidth, fallbackCount: subviews.count)
        var rowStart = 0
        var y = bounds.minY

        while rowStart < subviews.count {
            let rowEnd = min(rowStart + itemsPerRow, subviews.count)
            let rowCount = rowEnd - rowStart
            let rowWidth = CGFloat(rowCount) * itemSize.width + CGFloat(max(0, rowCount - 1)) * spacing
            var x = bounds.maxX - rowWidth

            for index in rowStart..<rowEnd {
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(width: itemSize.width, height: itemSize.height)
                )
                x += itemSize.width + spacing
            }

            y += itemSize.height + spacing
            rowStart = rowEnd
        }
    }

    private func idealWidth(for count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        let totalSpacing = CGFloat(max(0, count - 1)) * spacing
        return CGFloat(count) * itemSize.width + totalSpacing
    }

    private func itemsPerRow(for availableWidth: CGFloat, fallbackCount: Int) -> Int {
        guard availableWidth.isFinite, availableWidth > 0, itemSize.width > 0 else {
            return max(1, fallbackCount)
        }
        let raw = (availableWidth + spacing) / (itemSize.width + spacing)
        guard raw.isFinite, raw > 0 else { return max(1, fallbackCount) }
        return max(1, Int(raw))
    }
}

struct PulsatingCircle: ViewModifier {
    @State private var isAnimating = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isAnimating ? 1.5 : 1.0)
            .opacity(isAnimating ? 0.5 : 1.0)
            .animation(
                Animation
                    .easeInOut(duration: 0.8)
                    .repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}
