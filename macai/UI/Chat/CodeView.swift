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
    
    private let borderColorDark = Color(red: 0.25, green: 0.25, blue: 0.25)
    private let borderColorLight = Color(red: 0.86, green: 0.86, blue: 0.86)

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
                        ? borderColorDark
                    : borderColorLight
                )

                AttributedText(code ?? NSAttributedString(string: ""))
                    .textSelection(.enabled)
                    .padding(.top, 2)
                    .padding(.leading, 12)
                    .padding(.trailing, 12)
                    .padding(.bottom, 12)

            }
//            .background(
//                colorScheme == .dark
//                    ? Color(NSColor(red: 20 / 255, green: 20 / 255, blue: 20 / 255, alpha: 1))
//                    : .white
//            )
            .background(
                RoundedRectangle(cornerRadius: 8.0)
                    .stroke(
                        colorScheme == .dark ? borderColorDark : borderColorLight,
                        lineWidth: 2
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8.0))
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
