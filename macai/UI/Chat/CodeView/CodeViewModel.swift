//
//  CodeViewModel.swift
//  macai
//
//  Created by Renat Notfullin on 17.11.2024.
//

import SwiftUI

class CodeViewModel: ObservableObject {
    @Published var highlightedCode: NSAttributedString?
    @Published var isCopied = false
    
    public var code: String
    private let language: String
    private let isStreaming: Bool
    
    init(code: String, language: String, isStreaming: Bool) {
        self.code = code
        self.language = language
        self.isStreaming = isStreaming
    }
    
    func updateHighlighting(colorScheme: ColorScheme) {
        let theme = colorScheme == .dark ? "monokai-sublime" : "color-brewer"
        highlightedCode = HighlighterManager.shared.highlight(
            code: code,
            language: language,
            theme: theme,
            isStreaming: isStreaming
        )
    }
    
    func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(code, forType: .string)
        
        withAnimation {
            isCopied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            withAnimation {
                self.isCopied = false
            }
        }
    }
}
