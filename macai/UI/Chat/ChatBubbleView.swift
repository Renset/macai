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
    case code(code: NSAttributedString?, lang: String, indent: Int)
    case formula(String)
}

struct ChatBubbleView: View {
    var message: String = ""
    @State var index: Int
    @State var own: Bool
    @State var waitingForResponse: Bool?
    @State var error = false
    @State var initialMessage = false
    @Binding var isStreaming: Bool
    @State private var isPencilIconVisible = false
    @State private var wobbleAmount = 0.0
    @Environment(\.colorScheme) var colorScheme

    #if os(macOS)
        var outgoingBubbleColor = NSColor.systemBlue
        var incomingBubbleColor = NSColor.windowBackgroundColor
        var incomingLabelColor = NSColor.labelColor
    #else
        var outgoingBubbleColor = UIColor.systemBlue
        var incomingBubbleColor = UIColor.secondarySystemBackground
        var incomingLabelColor = UIColor.label
    #endif

    var body: some View {
        HStack {
            if own {
                Spacer()
            }

            VStack(alignment: .leading) {
                if self.waitingForResponse ?? false {
                    HStack {
                        //self.isPencilIconVisible = true
                        Image(systemName: "pencil")
                            .foregroundColor(.blue)
                            .offset(x: wobbleAmount, y: 0)
                            //.rotationEffect(.degrees(-wobbleAmount * 0.1))
                            .animation(
                                .easeIn(duration: 0.5).repeatForever(autoreverses: true),
                                value: wobbleAmount
                            )
                            .onAppear {
                                wobbleAmount = 20
                            }
                        Spacer()
                    }
                    .frame(width: 30)
                }
                else if self.error {
                    VStack {
                        HStack {
                            //self.isPencilIconVisible = true
                            Image(systemName: "exclamationmark.bubble")
                                .foregroundColor(.white)
                            Text("Error getting message from server. Try again?")
                        }
                    }
                }
                else {
                    let parser = MessageParser(colorScheme: colorScheme)
                    let parsedElements = parser.parseMessageFromString(input: message, shouldSkipCodeHighlighting: isStreaming)
                    ForEach(0..<parsedElements.count, id: \.self) { index in
                        switch parsedElements[index] {
                        case .text(let text):
                            let attributedString: NSAttributedString = {
                                let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                                let initialAttributedString = (try? NSAttributedString(markdown: text, options: options)) ?? NSAttributedString(string: text)
                                
                                let mutableAttributedString = NSMutableAttributedString(attributedString: initialAttributedString)
                                
                                let fullRange = NSRange(location: 0, length: mutableAttributedString.length)
                                
                                let systemFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
                                mutableAttributedString.addAttribute(.font, value: systemFont, range: fullRange)
                                
                                mutableAttributedString.addAttribute(.foregroundColor, value: own ? NSColor(Color(.white)) : NSColor.textColor, range: fullRange)
                                
                                return mutableAttributedString
                            }()
                            
                            if (text.count > AppConstants.longStringCount) {
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
                            CodeView(code: code, lang: lang)
                                .padding(.bottom, 8)
                                .padding(.leading, CGFloat(indent)*4)
                        case .formula(let formula):
                            if (isStreaming) {
                                Text(formula).textSelection(.enabled)
                            } else {
                                AdaptiveMathView(equation: formula, fontSize: NSFont.systemFontSize + CGFloat(2))
                                    .padding(.vertical, 16)
                            }

                        }
                    }
                }
            }
            .foregroundColor(error ? Color(.white) : Color(own ? .white : incomingLabelColor))
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                error
                    ? Color(.red)
                    : initialMessage ? Color(.systemOrange) : Color(own ? outgoingBubbleColor : incomingBubbleColor)
            )
            .cornerRadius(16)
            if !own {
                Spacer()
            }
        }
        .contextMenu {
            Button(action: {
                copyMessageToClipboard()
            }) {
                Label("Copy raw message", systemImage: "doc.on.doc")
            }
        }
    }

    private func copyMessageToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(message, forType: .string)
    }
}
