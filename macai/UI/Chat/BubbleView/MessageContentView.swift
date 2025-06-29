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
    let message: String
    let isStreaming: Bool
    let own: Bool
    let effectiveFontSize: Double
    let colorScheme: ColorScheme

    @State private var showFullMessage = false
    @State private var isParsingFullMessage = false
    @State private var selectedImage: IdentifiableImage?

    private let largeMessageSymbolsThreshold = AppConstants.largeMessageSymbolsThreshold

    var body: some View {
        VStack(alignment: .leading) {
            // Check if message contains image data or JSON with image_url before applying truncation
            if message.count > largeMessageSymbolsThreshold && !showFullMessage && !containsImageData(message) {
                renderPartialContent()
            }
            else {
                renderFullContent()
            }
        }
    }

    private func containsImageData(_ message: String) -> Bool {
        if message.contains("<image-uuid>") {
            return true
        }
        return false
    }

    @ViewBuilder
    private func renderPartialContent() -> some View {
        let truncatedMessage = String(message.prefix(largeMessageSymbolsThreshold))
        let parser = MessageParser(colorScheme: colorScheme)
        let parsedElements = parser.parseMessageFromString(input: truncatedMessage)

        VStack(alignment: .leading, spacing: 8) {
            ForEach(parsedElements.indices, id: \.self) { index in
                renderElement(parsedElements[index])
            }

            HStack(spacing: 8) {
                Button(action: {
                    isParsingFullMessage = true
                    // Parse the full message in background: very long messages may take long time to parse (and even cause app crash)
                    DispatchQueue.global(qos: .userInitiated).async {
                        let parser = MessageParser(colorScheme: colorScheme)
                        _ = parser.parseMessageFromString(input: message)

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
        let parsedElements = parser.parseMessageFromString(input: message)

        ForEach(parsedElements.indices, id: \.self) { index in
            renderElement(parsedElements[index])
        }
    }

    @ViewBuilder
    private func renderElement(_ element: MessageElements) -> some View {
        switch element {
        case .thinking(let content, _):
            ThinkingProcessView(content: content)
                .padding(.vertical, 4)

        case .text(let text):
            renderText(text)

        case .table(let header, let data):
            TableView(header: header, tableData: data)
                .padding()

        case .code(let code, let lang, let indent):
            renderCode(code: code, lang: lang, indent: indent, isStreaming: isStreaming)

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
        }
    }

    @ViewBuilder
    private func renderText(_ text: String) -> some View {
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
            let headerRegex = try! NSRegularExpression(pattern: "^(#{1,6})\\s+(.*)", options: .anchorsMatchLines)
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
            let quoteRegex = try! NSRegularExpression(pattern: "^>\\s*(.*)", options: .anchorsMatchLines)
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

            return mutableAttributedString
        }()

        if text.count > AppConstants.longStringCount {
            AttributedText(attributedString)
                .textSelection(.enabled)
        }
        else {
            Text(.init(attributedString))
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func renderCode(code: String, lang: String, indent: Int, isStreaming: Bool) -> some View {
        CodeView(code: code, lang: lang, isStreaming: isStreaming)
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
                ZoomableImageView(image: identifiableImage.image, imageAspectRatio: aspectRatio)

            }
    }

}
