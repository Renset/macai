//
//  CodeView.swift
//  macai
//
//  Created by Renat on 07.06.2024.
//

import AttributedText
import Foundation
import Highlightr
import SwiftUI

struct CodeView: View {
    let code: String
    let lang: String
    var isStreaming: Bool
    @Binding var searchText: String
    @StateObject private var viewModel: CodeViewModel
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject private var previewStateManager: PreviewStateManager
    @State private var highlightedCode: NSAttributedString?
    @State private var isRendered = false
    @AppStorage("chatFontSize") private var chatFontSize: Double = 14.0
    @AppStorage("codeFont") private var codeFont: String = AppConstants.firaCode
    
    init(code: String, lang: String, isStreaming: Bool = false, searchText: Binding<String>) {
        self.code = code
        self.lang = lang
        self.isStreaming = isStreaming
        self._searchText = searchText
        _viewModel = StateObject(
            wrappedValue: CodeViewModel(
                code: code,
                language: lang,
                isStreaming: isStreaming
            )
        )
    }
    
    var body: some View {
        VStack {
            headerView
            if let highlighted = highlightedCode {
                
                let finalAttributedString = searchText == "" ? highlighted : applySearchHighlighting(to: highlighted)
                AttributedText(finalAttributedString)
                    .textSelection(.enabled)
                    .padding([.horizontal, .bottom], 12)
            }
            else {
                Text(code)
                    .textSelection(.enabled)
                    .padding([.horizontal, .bottom], 12)
                    .font(.custom(codeFont, size: chatFontSize - 1))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(codeBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8.0))
        .onChange(of: colorScheme) { newScheme in
            updateHighlightedCode(colorScheme: newScheme)
        }
        .onChange(of: code) { code in
            if isStreaming {
                print("Code changed: \(code)")
                updateHighlightedCode(colorScheme: colorScheme, code: code)
            }
        }
        .onChange(of: highlightedCode) { _ in
            if !isRendered {
                isRendered = true
                NotificationCenter.default.post(
                    name: NSNotification.Name("CodeBlockRendered"),
                    object: nil
                )
            }
        }
        .onAppear {
            updateHighlightedCode(colorScheme: colorScheme)
        }
        .onChange(of: chatFontSize) { _ in
            HighlighterManager.shared.invalidateCache()
            updateHighlightedCode(colorScheme: colorScheme)
        }
        .onChange(of: codeFont) { _ in
            HighlighterManager.shared.invalidateCache()
            updateHighlightedCode(colorScheme: colorScheme)
        }
    }

    private var headerView: some View {
        HStack {
            if lang != "" {
                Text(lang)
                    .fontWeight(.bold)
            }
            Spacer()

            HStack(spacing: 12) {
                if lang.lowercased() == "html" {
                    runButton
                }
                copyButton
            }
        }
        .padding(12)

    }

    private var copyButton: some View {
        Button(action: viewModel.copyToClipboard) {
            Image(systemName: viewModel.isCopied ? "checkmark" : "doc.on.doc")
                .frame(height: 12)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var runButton: some View {
        Button(action: togglePreview) {
            Image(systemName: previewStateManager.isPreviewVisible ? "play.slash" : "play")
                .frame(height: 12)

            Text("Run")
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func togglePreview() {
        if previewStateManager.isPreviewVisible {
            previewStateManager.hidePreview()
        }
        else {
            previewStateManager.showPreview(content: code)
        }
    }

    private var codeBackground: Color {
        colorScheme == .dark ? Color(red: 0.15, green: 0.15, blue: 0.15) : Color(red: 0.96, green: 0.96, blue: 0.96)
    }

    private func updateHighlightedCode(colorScheme: ColorScheme, code: String = "") {
        DispatchQueue.main.async {
            if code != "" {
                viewModel.code = code
            }
            viewModel.updateHighlighting(colorScheme: colorScheme)
            highlightedCode = viewModel.highlightedCode
        }
    }
    
    private func applySearchHighlighting(to attributedString: NSAttributedString) -> NSAttributedString {
        guard !searchText.isEmpty else { return attributedString }
        
        let mutableAttributedString = NSMutableAttributedString(attributedString: attributedString)
        let lowerText = mutableAttributedString.string.lowercased()
        let lowerSearch = searchText.lowercased()
        var location = 0
        
        while location < mutableAttributedString.length {
            let searchRange = NSRange(location: location, length: mutableAttributedString.length - location)
            let foundRange = (lowerText as NSString).range(of: lowerSearch, range: searchRange)
            if foundRange.location != NSNotFound {
                mutableAttributedString.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.3), range: foundRange)
                location = foundRange.location + foundRange.length
            } else {
                break
            }
        }
        
        return mutableAttributedString
    }
}

#Preview {
    CodeView(code: "<h1>Hello World</h1>", lang: "html", searchText: .constant(""))
        .environmentObject(PreviewStateManager())
}
