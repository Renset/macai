//
//  CodeView.swift
//  macai
//
//  Created by Renat on 07.06.2024.
//

import SwiftUI
import AttributedText
import Foundation
import Highlightr

struct CodeView: View {
    let code: NSAttributedString?
    let lang: String
    @State private var isCopied = false
    var isHovered = true
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack {
            VStack {
                HStack {
                    HStack {
                        if lang != "" {
                            Text(lang)
                                .fontWeight(.bold)
                        }
                        Spacer()
                        // Flat button to copy code to clipboard
                        // Display Check mark if copied
                        if isHovered {
                            Button(action: {
                                copyToClipboard(code?.string ?? "")
                                withAnimation{
                                    isCopied = true
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                    withAnimation {
                                        isCopied = false
                                    }
                                }
                            }) {
                                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                    .frame(height: 12)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(6)
                }
                .background(
                    colorScheme == .dark
                        ? Color(NSColor(red: 30 / 255, green: 30 / 255, blue: 30 / 255, alpha: 1))
                    : Color(NSColor(red: 220 / 255, green: 220 / 255, blue: 220 / 255, alpha: 1))
                )

                AttributedText(code ?? NSAttributedString(string: ""))
                    .textSelection(.enabled)
                    .padding(.top, 2)
                    .padding(.leading, 12)
                    .padding(.trailing, 12)
                    .padding(.bottom, 12)

            }
            .background(
                colorScheme == .dark
                    ? Color(NSColor(red: 20 / 255, green: 20 / 255, blue: 20 / 255, alpha: 1))
                    : .white
            )
            .cornerRadius(8)
        }
    }
    
    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

#Preview {
    CodeView(code: NSAttributedString(string: "let a = 1"), lang: "swift")
}
