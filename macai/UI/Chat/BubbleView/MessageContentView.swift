//
//  MessageContentView.swift
//  macai
//
//  Created by Renat on 03.04.2025.
//

import SwiftUI
import AttributedText

struct MessageContentView: View {
    let message: String
    let isStreaming: Bool
    let own: Bool
    let effectiveFontSize: Double
    let colorScheme: ColorScheme

    var body: some View {
        let parser = MessageParser(colorScheme: colorScheme)
        let parsedElements = parser.parseMessageFromString(input: message)
        ForEach(0..<parsedElements.count, id: \.self) { index in
            switch parsedElements[index] {
            case .thinking(let content, _):
                ThinkingProcessView(content: content)
                    .padding(.vertical, 4)
            case .text(let text):
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
                    return mutableAttributedString
                }()

                if text.count > AppConstants.longStringCount {
                    AttributedText(attributedString)
                        .textSelection(.enabled)
                } else {
                    Text(.init(attributedString))
                        .textSelection(.enabled)
                }
            case .table(let header, let data):
                TableView(header: header, tableData: data)
                    .padding()
            case .code(let code, let lang, let indent):
                CodeView(code: code, lang: lang, isStreaming: isStreaming)
                    .padding(.bottom, 8)
                    .padding(.leading, CGFloat(indent) * 4)
            case .formula(let formula):
                if isStreaming {
                    Text(formula).textSelection(.enabled)
                } else {
                    AdaptiveMathView(equation: formula, fontSize: NSFont.systemFontSize + CGFloat(2))
                        .padding(.vertical, 16)
                }
            }
        }
    }
}
