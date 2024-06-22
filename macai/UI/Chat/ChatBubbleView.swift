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
    var viewContext: NSManagedObjectContext

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
                    MessageContentView(isStreaming: $isStreaming, message: message, colorScheme: colorScheme, viewContext: viewContext)
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
                
                //if isStreaming ?? false {
                    // TODO: uncomment when state update is fixed
//                    VStack {
//                        Image(systemName: "pencil")
//                            .foregroundColor(.blue)
//                            .offset(x: wobbleAmount, y: 0)
//                            .padding(.top, 8)
//                            .rotationEffect(.degrees(-wobbleAmount * 0.8))
//                            .animation(
//                                .easeIn(duration: 0.3).repeatForever(autoreverses: true),
//                                value: wobbleAmount
//                            )
//                            .onAppear {
//                                wobbleAmount = 5
//                            }
//                        Spacer()
//                    }
                //}
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
