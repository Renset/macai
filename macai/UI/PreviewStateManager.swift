//
//  PreviewStateManager.swift
//  macai
//
//  Created by Renat on 17.11.2024.
//


import SwiftUI

class PreviewStateManager: ObservableObject {
    @Published var isPreviewVisible = false
    @Published var previewContent: String = ""
    @AppStorage("previewPaneWidth") var previewPaneWidth: Double = 400
    
    func showPreview(content: String) {
        previewContent = content
        isPreviewVisible = true
    }
    
    func hidePreview() {
        isPreviewVisible = false
    }
}