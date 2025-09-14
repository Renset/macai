//
//  ImageEnabledMessageInputView.swift
//  macai
//
//  Created by Renat on 2024-07-15
//

import SwiftUI
import UniformTypeIdentifiers

struct MessageInputView: View {
    @Binding var text: String
    @Binding var attachedImages: [ImageAttachment]
    var imageUploadsAllowed: Bool
    var onEnter: () -> Void
    var onAddImage: () -> Void

    @FocusState private var isTextEditorFocused: Bool
    @State var dynamicHeight: CGFloat = 40 // Increase initial height
    @State var inputPlaceholderText = "Type your prompt here"
    @State var cornerRadius = 20.0
    @State private var isHoveringDropZone = false

    private let maxInputHeight = 160.0
    private let initialInputSize = 40.0
    private let inputPadding = 8.0
    private let lineWidthOnBlur = 2.0
    private let lineWidthOnFocus = 3.0
    private let lineColorOnBlur = Color.gray.opacity(0.5)
    private let lineColorOnFocus = Color.blue.opacity(0.8)
    @AppStorage("chatFontSize") private var chatFontSize: Double = 14.0

    private var effectiveFontSize: Double {
        chatFontSize
    }
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(attachedImages) { attachment in
                        ImagePreviewView(attachment: attachment) { index in
                            if let index = attachedImages.firstIndex(where: { $0.id == attachment.id }) {
                                withAnimation {
                                    attachedImages.remove(at: index)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 0)
                .padding(.bottom, 8)
            }
            .frame(height: attachedImages.isEmpty ? 0 : 100)
            
            HStack(spacing: 8) {
                if imageUploadsAllowed {
                    Button(action: onAddImage) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 16))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Add image")
                }
                
                ZStack {
                    Text(text == "" ? inputPlaceholderText : text)
                        .font(.system(size: effectiveFontSize))
                        .lineLimit(10)
                        .background(
                            GeometryReader { geometryText in
                                Color.clear
                                    .onAppear {
                                        dynamicHeight = calculateDynamicHeight(using: geometryText.size.height)
                                    }
                                    .onChange(of: geometryText.size) { _ in
                                        dynamicHeight = calculateDynamicHeight(using: geometryText.size.height)
                                    }
                            }
                        )
                        .padding(inputPadding)
                        .hidden()
                    
                    ZStack(alignment: .topLeading) {
                        if text.isEmpty {
                            Text(inputPlaceholderText)
                                .font(.system(size: effectiveFontSize))
                                .foregroundColor(.secondary)
                                .allowsHitTesting(false)
                        }
                        
                        TextEditor(text: $text)
                            .font(.system(size: effectiveFontSize))
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .focused($isTextEditorFocused)
                            .textFieldStyle(.plain)
                            .onChange(of: text) { _ in
                                DispatchQueue.main.async {
                                }
                            }
                    }
                    .padding(inputPadding)
                    .frame(height: max(dynamicHeight, 40))
                    .background(Color.clear)
                }
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(
                            isHoveringDropZone
                            ? Color.green.opacity(0.8)
                            : (isTextEditorFocused ? lineColorOnFocus : lineColorOnBlur),
                            lineWidth: isHoveringDropZone
                            ? 6 : (isTextEditorFocused ? lineWidthOnFocus : lineWidthOnBlur)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                )
                .onTapGesture {
                    isTextEditorFocused = true
                }
                
            }
        }
        .onDrop(of: [.image, .fileURL], isTargeted: $isHoveringDropZone) { providers in
            guard imageUploadsAllowed else { return false }
            return handleDrop(providers: providers)
        }
        .onAppear {
            DispatchQueue.main.async {
                isTextEditorFocused = true
            }
        }
    }
    
    private func calculateDynamicHeight(using height: CGFloat? = nil) -> CGFloat {
        let newHeight = height ?? dynamicHeight
        return min(max(newHeight, initialInputSize), maxInputHeight) + inputPadding * 2
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var didHandleDrop = false
        
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { (data, error) in
                    if let url = data as? URL {
                        DispatchQueue.main.async {
                            let attachment = ImageAttachment(url: url)
                            withAnimation {
                                attachedImages.append(attachment)
                            }
                        }
                        didHandleDrop = true
                    }
                }
            }
            else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (data, error) in
                    if let urlData = data as? Data,
                       let url = URL(dataRepresentation: urlData, relativeTo: nil),
                       isValidImageFile(url: url)
                    {
                        DispatchQueue.main.async {
                            let attachment = ImageAttachment(url: url)
                            withAnimation {
                                attachedImages.append(attachment)
                            }
                        }
                        didHandleDrop = true
                    }
                }
            }
        }
        
        return didHandleDrop
    }
    
    private func isValidImageFile(url: URL) -> Bool {
        let validExtensions = ["jpg", "jpeg", "png", "webp", "heic", "heif"]
        return validExtensions.contains(url.pathExtension.lowercased())
    }
}

struct ImagePreviewView: View {
    @ObservedObject var attachment: ImageAttachment
    var onRemove: (Int) -> Void
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            if attachment.isLoading {
                ProgressView()
                    .frame(width: 80, height: 80)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
            }
            else if let thumbnail = attachment.thumbnail ?? attachment.image {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipped()
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                    )
                
                Button(action: {
                    onRemove(0)
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white)
                        .background(Circle().fill(Color.black.opacity(0.6)))
                        .padding(4)
                }
                .buttonStyle(PlainButtonStyle())
            }
            else if let error = attachment.error {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.red)
                    Text("Error")
                        .font(.caption)
                }
                .frame(width: 80, height: 80)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .help(error.localizedDescription)
            }
        }
    }
}
