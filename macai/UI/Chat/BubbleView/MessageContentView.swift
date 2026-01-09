//
//  MessageContentView.swift
//  macai
//
//  Created by Renat on 03.04.2025.
//

import AttributedText
import SwiftUI

struct IdentifiableImage: Identifiable {
    let id = UUID()
    let image: NSImage
}
struct MessageContentView: View {
    var message: MessageEntity?
    let content: String
    let isStreaming: Bool
    let own: Bool
    let effectiveFontSize: Double
    let colorScheme: ColorScheme
    @Binding var searchText: String
    var currentSearchOccurrence: SearchOccurrence?

    @State private var showFullMessage = false
    @State private var isParsingFullMessage = false
    @State private var selectedImage: IdentifiableImage?

    private let largeMessageSymbolsThreshold = AppConstants.largeMessageSymbolsThreshold

    var body: some View {
        VStack(alignment: .leading) {
            // Check if message contains image data or JSON with image_url before applying truncation
            if content.count > largeMessageSymbolsThreshold && !showFullMessage && !containsImageData(content) {
                renderPartialContent()
            }
            else {
                renderFullContent()
            }
        }
    }

    private func containsImageData(_ message: String) -> Bool {
        if message.contains("<image-uuid>") || message.contains("<file-uuid>") {
            return true
        }
        return false
    }

    @ViewBuilder
    private func renderPartialContent() -> some View {
        let truncatedMessage = String(content.prefix(largeMessageSymbolsThreshold))
        let parser = MessageParser(colorScheme: colorScheme)
        let parsedElements = parser.parseMessageFromString(input: truncatedMessage)

        VStack(alignment: .leading, spacing: 8) {
            ForEach(parsedElements.indices, id: \.self) {
                index in
                renderElement(parsedElements[index], elementIndex: index)
            }

            HStack(spacing: 8) {
                Button(action: {
                    isParsingFullMessage = true
                    // Parse the full message in background: very long messages may take long time to parse (and even cause app crash)
                    DispatchQueue.global(qos: .userInitiated).async {
                        let parser = MessageParser(colorScheme: colorScheme)
                        _ = parser.parseMessageFromString(input: content)

                        DispatchQueue.main.async {
                            showFullMessage = true
                            isParsingFullMessage = false
                        }
                    }
                }) {
                    Text("Show Full Message")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 12)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(16)
                }
                .buttonStyle(PlainButtonStyle())

                if isParsingFullMessage {
                    ProgressView()
                        .scaleEffect(0.4)
                        .frame(width: 12, height: 12)
                }
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func renderFullContent() -> some View {
        let parser = MessageParser(colorScheme: colorScheme)
        let parsedElements = parser.parseMessageFromString(input: content)

        ForEach(parsedElements.indices, id: \.self) {
            index in
            renderElement(parsedElements[index], elementIndex: index)
                .id(generateElementID(elementIndex: index))
        }
    }
    
    private func generateElementID(elementIndex: Int) -> String {
        guard let messageID = message?.objectID else {
            return "element_\(elementIndex)"
        }
        let messageIDString = messageID.uriRepresentation().absoluteString
        return "\(messageIDString)_element_\(elementIndex)"
    }

    @ViewBuilder
    private func renderElement(_ element: MessageElements, elementIndex: Int) -> some View {
        switch element {
        case .thinking(let content, _):
            ThinkingProcessView(content: content)
                .padding(.vertical, 4)

        case .text(let text):
            renderText(text, elementIndex: elementIndex)

        case .table(let header, let data):
            TableView(header: header, tableData: data, searchText: $searchText, message: message, currentSearchOccurrence: currentSearchOccurrence, elementIndex: elementIndex)
                .padding(.bottom, 12)

        case .code(let code, let lang, let indent):
            renderCode(code: code, lang: lang, indent: indent, isStreaming: isStreaming, elementIndex: elementIndex)

        case .formula(let formula):
            if isStreaming {
                Text(formula).textSelection(.enabled)
            }
            else {
                AdaptiveMathView(equation: formula, fontSize: NSFont.systemFontSize + CGFloat(2))
                    .padding(.vertical, 16)
            }

        case .image(let image):
            renderImage(image)

        case .file(let fileInfo):
            renderFile(fileInfo)
        }
    }

    @ViewBuilder
    private func renderText(_ text: String, elementIndex: Int = 0) -> some View {
        let attributedString: NSAttributedString = {
            let options = AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace
            )
            let initialAttributedString =
                (try? NSAttributedString(markdown: text, options: options))
                ?? NSAttributedString(string: text)

            let mutableAttributedString = NSMutableAttributedString(
                attributedString: initialAttributedString
            )
            let fullRange = NSRange(location: 0, length: mutableAttributedString.length)
            let systemFont = NSFont.systemFont(ofSize: effectiveFontSize)

            mutableAttributedString.addAttribute(.font, value: systemFont, range: fullRange)
            mutableAttributedString.addAttribute(
                .foregroundColor,
                value: own ? NSColor.textColor : NSColor.textColor,
                range: fullRange
            )

            // Handle headers
            guard let headerRegex = try? NSRegularExpression(pattern: "^(#{1,6})\\s+(.*)", options: .anchorsMatchLines) else { return mutableAttributedString }
            let headerMatches = headerRegex.matches(in: mutableAttributedString.string, options: [], range: NSRange(location: 0, length: mutableAttributedString.string.utf16.count))

            for match in headerMatches.reversed() {
                let fullMatchRange = match.range(at: 0)
                let prefixHashesRange = match.range(at: 1)
                let contentTextRange = match.range(at: 2)

                let level = prefixHashesRange.length
                let fontSize = max(effectiveFontSize + 10 - pow(CGFloat(level), 1.5), 6)
                let font = NSFont.boldSystemFont(ofSize: fontSize)

                mutableAttributedString.addAttribute(.font, value: font, range: contentTextRange)
                
                let prefixToDeleteRange = NSRange(location: fullMatchRange.location, length: contentTextRange.location - fullMatchRange.location)
                mutableAttributedString.deleteCharacters(in: prefixToDeleteRange)
            }
            
            // Handle quote blocks
            guard let quoteRegex = try? NSRegularExpression(pattern: "^\\s*>\\s*(.*)", options: .anchorsMatchLines) else { return mutableAttributedString }
            let quoteMatches = quoteRegex.matches(in: mutableAttributedString.string, options: [], range: NSRange(location: 0, length: mutableAttributedString.string.utf16.count))
            
            for match in quoteMatches.reversed() {
                let fullMatchRange = match.range(at: 0)
                let contentTextRange = match.range(at: 1)
                
                let fontDescriptor = NSFont.systemFont(ofSize: effectiveFontSize).fontDescriptor
                let italicDescriptor = fontDescriptor.withSymbolicTraits(.italic)
                let italicFont = NSFont(descriptor: italicDescriptor, size: effectiveFontSize) ?? NSFont.systemFont(ofSize: effectiveFontSize)
                mutableAttributedString.addAttribute(.font, value: italicFont, range: contentTextRange)
                
                let quoteColor = colorScheme == .dark ? NSColor.secondaryLabelColor : NSColor.tertiaryLabelColor
                mutableAttributedString.addAttribute(.foregroundColor, value: quoteColor, range: contentTextRange)
                
                let prefixToDeleteRange = NSRange(location: fullMatchRange.location, length: contentTextRange.location - fullMatchRange.location)
                mutableAttributedString.deleteCharacters(in: prefixToDeleteRange)
            }

            // Apply search highlighting if searchText is not empty
            if !searchText.isEmpty, let messageId = message?.objectID {
                let body = mutableAttributedString.string
                let originalBody = text
                var searchStartIndex = body.startIndex
                var originalSearchStartIndex = originalBody.startIndex
                
                while let range = body.range(of: searchText, options: .caseInsensitive, range: searchStartIndex..<body.endIndex),
                      let originalRange = originalBody.range(of: searchText, options: .caseInsensitive, range: originalSearchStartIndex..<originalBody.endIndex) {
                    let nsRange = NSRange(range, in: body)
                    let originalNSRange = NSRange(originalRange, in: originalBody)
                    let occurrence = SearchOccurrence(messageID: messageId, range: originalNSRange, elementIndex: elementIndex, elementType: "text")
                    let isCurrent = occurrence == self.currentSearchOccurrence
                    let color = isCurrent 
                         ? NSColor(Color(hex: AppConstants.currentHighlightColor) ?? Color.yellow) 
                         : NSColor(Color(hex: AppConstants.defaultHighlightColor) ?? Color.gray).withAlphaComponent(0.3)
                    mutableAttributedString.addAttribute(.backgroundColor, value: color, range: nsRange)
                    searchStartIndex = range.upperBound
                    originalSearchStartIndex = originalRange.upperBound
                }
            }

            return mutableAttributedString
        }()

        if text.count > AppConstants.longStringCount {
            AttributedText(attributedString)
                .textSelection(.enabled)
        } else {
            Text(.init(attributedString))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func renderCode(code: String, lang: String, indent: Int, isStreaming: Bool, elementIndex: Int) -> some View {
        CodeView(code: code, lang: lang, isStreaming: isStreaming, message: message, searchText: $searchText, currentSearchOccurrence: currentSearchOccurrence, elementIndex: elementIndex)
            .padding(.bottom, 8)
            .padding(.leading, CGFloat(indent) * 4)
            .onAppear {
                NotificationCenter.default.post(name: NSNotification.Name("CodeBlockRendered"), object: nil)
            }
    }

    @ViewBuilder
    private func renderImage(_ image: NSImage) -> some View {
        let maxWidth: CGFloat = 300
        let aspectRatio = image.size.width / image.size.height
        let displayHeight = maxWidth / aspectRatio

        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: maxWidth, maxHeight: displayHeight)
            .cornerRadius(8)
            .padding(.bottom, 3)
            .onTapGesture {
                selectedImage = IdentifiableImage(image: image)
            }
            .sheet(item: $selectedImage) { identifiableImage in
                ZoomableImageView(
                    image: identifiableImage.image,
                    imageAspectRatio: aspectRatio,
                    chatName: message?.chat?.name
                )

            }
    }

    @ViewBuilder
    private func renderFile(_ fileInfo: FileAttachmentInfo) -> some View {
        let displayName = fileInfo.filename.isEmpty ? "Document.pdf" : fileInfo.filename
        HStack(spacing: 10) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.system(size: effectiveFontSize, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("PDF document")
                    .font(.system(size: max(10, effectiveFontSize - 2)))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .cornerRadius(10)
    }

}
