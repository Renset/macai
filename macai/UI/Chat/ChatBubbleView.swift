//
//  ChatBubbleView.swift
//  macai
//
//  Created by Renat Notfullin on 18.03.2023.
//

import AttributedText
import Foundation
import SwiftUI

enum MessageElements {
    case text(String)
    case table(header: [String], data: [[String]])
    case code(code: String, lang: String, indent: Int)
    case formula(String)
}

struct ChatBubbleContent: Equatable {
    let message: String
    let own: Bool
    let waitingForResponse: Bool?
    let error: Bool
    let initialMessage: Bool
    let isStreaming: Bool

    static func == (lhs: ChatBubbleContent, rhs: ChatBubbleContent) -> Bool {
        return lhs.message == rhs.message && lhs.own == rhs.own && lhs.waitingForResponse == rhs.waitingForResponse
            && lhs.error == rhs.error && lhs.initialMessage == rhs.initialMessage && lhs.isStreaming == rhs.isStreaming
    }
}

struct ChatBubbleView: View, Equatable {
    let content: ChatBubbleContent
    @Environment(\.colorScheme) var colorScheme

    private let outgoingBubbleColorLight = Color(red: 0.92, green: 0.92, blue: 0.92)
    private let outgoingBubbleColorDark = Color(red: 0.3, green: 0.3, blue: 0.3)
    private let incomingBubbleColorLight = Color(.white).opacity(0)
    private let incomingBubbleColorDark = Color(.white).opacity(0)
    private let incomingLabelColor = NSColor.labelColor

    static func == (lhs: ChatBubbleView, rhs: ChatBubbleView) -> Bool {
        lhs.content == rhs.content
    }

    var body: some View {
        HStack {
            if content.own {
                Color.clear
                    .frame(width: 80)
                Spacer()
            }

            VStack(alignment: .leading) {
                if content.waitingForResponse ?? false {
                    HStack {
                        Text("Thinking")
                            .foregroundColor(.primary)
                            .font(.system(size: 14))
                            
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 6, height: 6)
                            .modifier(PulsatingCircle())
                            .padding(.top, 4)
                    }
                }
                else if content.error {
                    VStack {
                        HStack {
                            Image(systemName: "exclamationmark.bubble")
                                .foregroundColor(.white)
                            Text("Error getting message from server. Try again?")
                        }
                    }
                } else {
                    let parser = MessageParser(colorScheme: colorScheme)
                    let parsedElements = parser.parseMessageFromString(
                        input: content.message
                    )
                    ForEach(0..<parsedElements.count, id: \.self) { index in
                        switch parsedElements[index] {
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
                                let systemFont = NSFont.systemFont(ofSize: 14)

                                mutableAttributedString.addAttribute(.font, value: systemFont, range: fullRange)
                                mutableAttributedString.addAttribute(
                                    .foregroundColor,
                                    value: content.own ? NSColor.textColor : NSColor.textColor,
                                    range: fullRange
                                )

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

                        case .table(let header, let data):
                            TableView(header: header, tableData: data)
                                .padding()
                        case .code(let code, let lang, let indent):
                            CodeView(code: code, lang: lang, isStreaming: content.isStreaming)
                                .padding(.bottom, 8)
                                .padding(.leading, CGFloat(indent) * 4)
                        case .formula(let formula):
                            if content.isStreaming {
                                Text(formula).textSelection(.enabled)
                            }
                            else {
                                AdaptiveMathView(equation: formula, fontSize: NSFont.systemFontSize + CGFloat(2))
                                    .padding(.vertical, 16)
                            }
                        }
                    }
                }
            }
            .foregroundColor(
                content.error ? Color(.white) : Color(content.own ? incomingLabelColor : incomingLabelColor)
            )
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                content.error
                    ? Color(.red)
                    : content.initialMessage
                        ? Color(.systemOrange)
                        : colorScheme == .dark
                            ? (content.own ? outgoingBubbleColorDark : incomingBubbleColorDark)
                            : (content.own ? outgoingBubbleColorLight : incomingBubbleColorLight)
            )
            .cornerRadius(16)

            if !content.own {
                Spacer()
            }
        }
        .contextMenu {
            Button(action: {
                copyMessageToClipboard(content.message)
            }) {
                Label("Copy raw message", systemImage: "doc.on.doc")
            }
        }
        .padding(.vertical, 8)
    }

    private func copyMessageToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
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
