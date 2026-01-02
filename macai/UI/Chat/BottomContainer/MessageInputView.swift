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
    let isInferenceInProgress: Bool
    let isEditingSystemMessage: Bool
    var imageUploadsAllowed: Bool
    var imageGenerationSupported: Bool
    var onEnter: () -> Void
    var onAddImage: () -> Void
    var onStopInference: () -> Void
    var onCancelEdit: () -> Void

    private let frontReturnKeyType: MacaiTextField.ReturnKeyType = .next
    @State var isFocused: Focus?
    private let inputPlaceholderText: String
    private let cornerRadius: Double
    @State private var isHoveringDropZone = false

    private let maxInputHeight = 160.0
    private let initialInputSize = 16.0
    private let inputPadding = 8.0
    private let lineWidthOnBlur = 2.0
    private let lineWidthOnFocus = 3.0
    private let lineColorOnBlur = Color.gray.opacity(0.5)
    private let lineColorOnFocus = Color.blue.opacity(0.8)
    @AppStorage("chatFontSize") private var chatFontSize: Double = 14.0

    private var effectiveFontSize: Double {
        chatFontSize
    }

    private var effectivePlaceholderText: String {
        if imageGenerationSupported {
            return "Ask anything or describe an image to generate"
        }
        return inputPlaceholderText
    }

    private var defaultInputHeight: CGFloat {
        CGFloat(initialInputSize + inputPadding * 2)
    }

    private var stopButtonTransition: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.2, anchor: .trailing)
                .combined(with: .opacity)
                .combined(with: .offset(x: -8, y: 6)),
            removal: .scale(scale: 0.6, anchor: .trailing)
                .combined(with: .opacity)
        )
    }

    private var stopButtonAnimation: Animation {
        .interpolatingSpring(stiffness: 240, damping: 14)
    }

    private var shouldShowAccessoryButton: Bool {
        isInferenceInProgress || isEditingSystemMessage
    }

    private var accessoryButtonConfig: (systemName: String, foregroundColor: Color, backgroundColor: Color, helpText: String, action: () -> Void) {
        if isInferenceInProgress {
            return ("stop.fill", .blue, Color.blue.opacity(0.15), "Stop generating", onStopInference)
        }
        return ("xmark", .blue, Color.blue.opacity(0.15), "Cancel editing", onCancelEdit)
    }

    enum Focus {
        case focused, notFocused
    }

    init(
        text: Binding<String>,
        attachedImages: Binding<[ImageAttachment]>,
        isInferenceInProgress: Bool,
        isEditingSystemMessage: Bool = false,
        imageUploadsAllowed: Bool,
        imageGenerationSupported: Bool,
        onEnter: @escaping () -> Void,
        onAddImage: @escaping () -> Void,
        onStopInference: @escaping () -> Void,
        onCancelEdit: @escaping () -> Void = {},
        inputPlaceholderText: String = "Type your prompt here",
        cornerRadius: Double = 20.0
    ) {
        self._text = text
        self._attachedImages = attachedImages
        self.isInferenceInProgress = isInferenceInProgress
        self.isEditingSystemMessage = isEditingSystemMessage
        self.imageUploadsAllowed = imageUploadsAllowed
        self.imageGenerationSupported = imageGenerationSupported
        self.onEnter = onEnter
        self.onAddImage = onAddImage
        self.onStopInference = onStopInference
        self.onCancelEdit = onCancelEdit
        self.inputPlaceholderText = inputPlaceholderText
        self.cornerRadius = cornerRadius
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
                
                MacaiTextField(
                    effectivePlaceholderText,
                    text: $text,
                    isFocused: $isFocused.equalTo(.focused),
                    returnKeyType: frontReturnKeyType,
                    fontSize: effectiveFontSize,
                    minHeight: initialInputSize,
                    maxHeight: maxInputHeight,
                    onEscape: isEditingSystemMessage ? onCancelEdit : nil,
                    onCommit: {
                        guard !isInferenceInProgress else { return }
                        onEnter()
                    }
                )
                .padding(inputPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.clear)
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(
                            isHoveringDropZone
                                ? Color.green.opacity(0.8)
                                : (isFocused == .focused ? lineColorOnFocus : lineColorOnBlur),
                            lineWidth: isHoveringDropZone
                                ? 6 : (isFocused == .focused ? lineWidthOnFocus : lineWidthOnBlur)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                )
                .onTapGesture {
                    isFocused = .focused
                }

                if shouldShowAccessoryButton {
                    let config = accessoryButtonConfig
                    InputAccessoryButton(
                        systemName: config.systemName,
                        size: defaultInputHeight,
                        foregroundColor: config.foregroundColor,
                        backgroundColor: config.backgroundColor,
                        helpText: config.helpText,
                        action: config.action
                    )
                    .transition(stopButtonTransition)
                }
            }
            .animation(stopButtonAnimation, value: shouldShowAccessoryButton)
        }
        .onDrop(of: [.image, .fileURL], isTargeted: $isHoveringDropZone) { providers in
            guard imageUploadsAllowed else { return false }
            return handleDrop(providers: providers)
        }
        .onAppear {
            DispatchQueue.main.async {
                isFocused = .focused
            }
        }
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

private struct InputAccessoryButton: View {
    let systemName: String
    let size: CGFloat
    let foregroundColor: Color
    let backgroundColor: Color
    let helpText: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundColor(foregroundColor)
                .frame(width: size, height: size)
                .background(Circle().fill(backgroundColor))
                .overlay(
                    Circle()
                        .stroke(foregroundColor.opacity(0.4), lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .help(helpText)
        .accessibilityLabel(Text(helpText))
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
                #if os(macOS)
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
                #else
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 80)
                    .clipped()
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                    )
                #endif

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
