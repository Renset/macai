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
    let code: String
    let lang: String
    var isStreaming: Bool
    @StateObject private var viewModel: CodeViewModel
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject private var previewStateManager: PreviewStateManager
    @State private var highlightedCode: NSAttributedString?
    
    init(code: String, lang: String, isStreaming: Bool = false) {
        self.code = code
        self.lang = lang
        self.isStreaming = isStreaming
        _viewModel = StateObject(wrappedValue: CodeViewModel(
            code: code,
            language: lang,
            isStreaming: isStreaming
        ))
    }
    
    var body: some View {
        VStack {
            headerView
            if let highlighted = highlightedCode {
                AttributedText(highlighted)
                    .textSelection(.enabled)
                    .padding([.horizontal, .bottom], 12)
            }
        }
        .background(backgroundShape)
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
        .onAppear {
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
            
            HStack(spacing: 8) {
                if lang.lowercased() == "html" {
                    previewButton
                }
                copyButton
            }
        }
        .padding(6)
        .background(headerBackground)
        
    }
    
    private var copyButton: some View {
        Button(action: viewModel.copyToClipboard) {
            Image(systemName: viewModel.isCopied ? "checkmark" : "doc.on.doc")
                .frame(height: 12)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var previewButton: some View {
        Button(action: togglePreview) {
            Image(systemName: previewStateManager.isPreviewVisible ? "eye.slash" : "eye")
                .frame(height: 12)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func togglePreview() {
        if previewStateManager.isPreviewVisible {
            previewStateManager.hidePreview()
        } else {
            previewStateManager.showPreview(content: code)
        }
    }
    
    private var headerBackground: Color {
        colorScheme == .dark ? Color(red: 0.25, green: 0.25, blue: 0.25) : Color(red: 0.86, green: 0.86, blue: 0.86)
    }
    
    private var backgroundShape: some View {
        RoundedRectangle(cornerRadius: 8.0)
            .stroke(
                colorScheme == .dark ? Color(red: 0.25, green: 0.25, blue: 0.25) : Color(red: 0.86, green: 0.86, blue: 0.86),
                lineWidth: 2
            )
    }
    
    private func updateHighlightedCode(colorScheme: ColorScheme, code: String = "") {
        //guard !isStreaming else { return }
        DispatchQueue.main.async {
            if (code != "") {
                viewModel.code = code
            }
            viewModel.updateHighlighting(colorScheme: colorScheme)
            highlightedCode = viewModel.highlightedCode
        }
    }
}

#Preview {
    CodeView(code: "<h1>Hello World</h1>", lang: "html")
        .environmentObject(PreviewStateManager())
}
