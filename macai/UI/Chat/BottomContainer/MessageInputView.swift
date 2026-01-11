//
//  ImageEnabledMessageInputView.swift
//  macai
//
//  Created by Renat on 2024-07-15
//

import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct MessageInputView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Binding var text: String
    @Binding var attachedImages: [ImageAttachment]
    @Binding var attachedFiles: [DocumentAttachment]
    let isInferenceInProgress: Bool
    let isEditingSystemMessage: Bool
    var imageUploadsAllowed: Bool
    var pdfUploadsAllowed: Bool
    var imageGenerationSupported: Bool
    var onEnter: () -> Void
    var onAddImage: () -> Void
    var onAddFile: () -> Void
    var onStopInference: () -> Void
    var onCancelEdit: () -> Void

    private let frontReturnKeyType: MacaiTextField.ReturnKeyType = .next
    @State var isFocused: Focus?
    private let inputPlaceholderText: String
    private let cornerRadius: Double
    @State private var isHoveringDropZone = false
    @State private var attachmentOrder: [AttachmentKey] = []
    @State private var draggingAttachment: AttachmentKey?
    @State private var isShowingPhotosPicker = false
    @State private var photoPickerItems: [PhotosPickerItem] = []

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

    private var attachmentButtonIcon: String? {
        switch (imageUploadsAllowed, pdfUploadsAllowed) {
        case (true, true):
            return "paperclip"
        case (true, false):
            return "photo.badge.plus"
        case (false, true):
            return "doc.badge.plus"
        case (false, false):
            return nil
        }
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
        attachedFiles: Binding<[DocumentAttachment]>,
        isInferenceInProgress: Bool,
        isEditingSystemMessage: Bool = false,
        imageUploadsAllowed: Bool,
        pdfUploadsAllowed: Bool,
        imageGenerationSupported: Bool,
        onEnter: @escaping () -> Void,
        onAddImage: @escaping () -> Void,
        onAddFile: @escaping () -> Void,
        onStopInference: @escaping () -> Void,
        onCancelEdit: @escaping () -> Void = {},
        inputPlaceholderText: String = "Type your prompt here",
        cornerRadius: Double = 20.0
    ) {
        self._text = text
        self._attachedImages = attachedImages
        self._attachedFiles = attachedFiles
        self.isInferenceInProgress = isInferenceInProgress
        self.isEditingSystemMessage = isEditingSystemMessage
        self.imageUploadsAllowed = imageUploadsAllowed
        self.pdfUploadsAllowed = pdfUploadsAllowed
        self.imageGenerationSupported = imageGenerationSupported
        self.onEnter = onEnter
        self.onAddImage = onAddImage
        self.onAddFile = onAddFile
        self.onStopInference = onStopInference
        self.onCancelEdit = onCancelEdit
        self.inputPlaceholderText = inputPlaceholderText
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        let orderedAttachments = orderedAttachmentItems()
        let previewRequests = attachmentPreviewRequests(from: orderedAttachments)
        let previewIndexById = previewRequests.enumerated().reduce(into: [UUID: Int]()) { result, entry in
            result[entry.element.id] = entry.offset
        }

        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(orderedAttachments) { attachment in
                        switch attachment {
                        case .image(let imageAttachment):
                            ImagePreviewView(
                                attachment: imageAttachment,
                                onPreview: {
                                    if let index = previewIndexById[imageAttachment.id] {
                                        QuickLookPreviewer.shared.preview(requests: previewRequests, selectedIndex: index)
                                    }
                                }
                            ) { _ in
                                if let index = attachedImages.firstIndex(where: { $0.id == imageAttachment.id }) {
                                    withAnimation {
                                        attachedImages.remove(at: index)
                                    }
                                }
                            }
                            .onDrag {
                                draggingAttachment = .image(imageAttachment.id)
                                return NSItemProvider(object: attachment.dragIdentifier as NSString)
                            }
                            .onDrop(
                                of: [.text],
                                delegate: AttachmentDropDelegate(
                                    item: .image(imageAttachment.id),
                                    order: $attachmentOrder,
                                    dragging: $draggingAttachment,
                                    onMove: applyAttachmentOrder
                                )
                            )
                        case .file(let fileAttachment):
                            FilePreviewView(
                                attachment: fileAttachment,
                                onPreview: {
                                    if let index = previewIndexById[fileAttachment.id] {
                                        QuickLookPreviewer.shared.preview(requests: previewRequests, selectedIndex: index)
                                    }
                                }
                            ) { _ in
                                if let index = attachedFiles.firstIndex(where: { $0.id == fileAttachment.id }) {
                                    withAnimation {
                                        attachedFiles.remove(at: index)
                                    }
                                }
                            }
                            .onDrag {
                                draggingAttachment = .file(fileAttachment.id)
                                return NSItemProvider(object: attachment.dragIdentifier as NSString)
                            }
                            .onDrop(
                                of: [.text],
                                delegate: AttachmentDropDelegate(
                                    item: .file(fileAttachment.id),
                                    order: $attachmentOrder,
                                    dragging: $draggingAttachment,
                                    onMove: applyAttachmentOrder
                                )
                            )
                        }
                    }
                }
                .padding(.horizontal, 0)
                .padding(.bottom, 8)
            }
            .frame(height: (attachedImages.isEmpty && attachedFiles.isEmpty) ? 0 : 100)
            
            HStack(spacing: 8) {
                if let attachmentButtonIcon {
                    Menu {
                        if pdfUploadsAllowed {
                            Button("Add PDF", action: onAddFile)
                        }
                        if imageUploadsAllowed {
                            Button("Add Image from File", action: onAddImage)
                            Button("Add Image from Photos") {
                                isShowingPhotosPicker = true
                            }
                        }
                    } label: {
                        Image(systemName: attachmentButtonIcon)
                            .font(.system(size: 16))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Add attachment")
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
        .scaleEffect(isHoveringDropZone ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHoveringDropZone)
        .onDrop(of: [.image, .pdf, .fileURL], isTargeted: $isHoveringDropZone) { providers in
            guard imageUploadsAllowed || pdfUploadsAllowed else { return false }
            return handleDrop(providers: providers)
        }
        .onAppear {
            syncAttachmentOrder()
        }
        .onChange(of: attachedImages.map { $0.id }) { _ in
            syncAttachmentOrder()
        }
        .onChange(of: attachedFiles.map { $0.id }) { _ in
            syncAttachmentOrder()
        }
        .onAppear {
            DispatchQueue.main.async {
                isFocused = .focused
            }
        }
        .photosPicker(isPresented: $isShowingPhotosPicker, selection: $photoPickerItems, matching: .images, photoLibrary: .shared())
        .onChange(of: photoPickerItems) { newItems in
            guard imageUploadsAllowed, !newItems.isEmpty else { return }
            Task {
                var newAttachments: [ImageAttachment] = []
                for item in newItems {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = NSImage(data: data) {
                        let attachment = ImageAttachment(image: image)
                        attachment.saveToEntity(image: image, context: self.viewContext)
                        newAttachments.append(attachment)
                    }
                }
                if !newAttachments.isEmpty {
                    await MainActor.run {
                        withAnimation {
                            attachedImages.append(contentsOf: newAttachments)
                        }
                    }
                }
                await MainActor.run {
                    photoPickerItems = []
                }
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var didHandleDrop = false

        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                didHandleDrop = didHandleDrop || imageUploadsAllowed || pdfUploadsAllowed
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (data, _) in
                    if let urlData = data as? Data,
                       let url = URL(dataRepresentation: urlData, relativeTo: nil),
                       (isValidImageFile(url: url) || isValidPDFFile(url: url))
                    {
                        DispatchQueue.main.async {
                            if isValidPDFFile(url: url) {
                                guard pdfUploadsAllowed else { return }
                                let attachment = DocumentAttachment(url: url, context: self.viewContext)
                                withAnimation {
                                    attachedFiles.append(attachment)
                                }
                            } else {
                                guard imageUploadsAllowed else { return }
                                let attachment = ImageAttachment(url: url, context: self.viewContext)
                                withAnimation {
                                    attachedImages.append(attachment)
                                }
                            }
                        }
                    }
                }
                continue
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                guard imageUploadsAllowed else { continue }
                didHandleDrop = true
                provider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { (item, _) in
                    let attachment: ImageAttachment?

                    if let url = item as? URL {
                        attachment = ImageAttachment(url: url, context: self.viewContext)
                    } else if let image = item as? NSImage {
                        let newAttachment = ImageAttachment(image: image)
                        newAttachment.saveToEntity(image: image, context: self.viewContext)
                        attachment = newAttachment
                    } else if let data = item as? Data, let image = NSImage(data: data) {
                        let newAttachment = ImageAttachment(image: image)
                        newAttachment.saveToEntity(image: image, context: self.viewContext)
                        attachment = newAttachment
                    } else {
                        attachment = nil
                    }

                    guard let attachment else { return }

                    DispatchQueue.main.async {
                        withAnimation {
                            attachedImages.append(attachment)
                        }
                    }
                }
                continue
            }

            if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                guard pdfUploadsAllowed else { continue }
                didHandleDrop = true
                provider.loadItem(forTypeIdentifier: UTType.pdf.identifier, options: nil) { (item, _) in
                    if let url = item as? URL {
                        DispatchQueue.main.async {
                            let attachment = DocumentAttachment(url: url, context: self.viewContext)
                            withAnimation {
                                attachedFiles.append(attachment)
                            }
                        }
                        return
                    }

                    if let data = item as? Data,
                       let url = PreviewFileHelper.writeTemporaryFile(
                        data: data,
                        filename: (provider.suggestedName ?? "Document.pdf"),
                        defaultExtension: "pdf",
                        id: UUID()
                       )
                    {
                        DispatchQueue.main.async {
                            let attachment = DocumentAttachment(url: url, context: self.viewContext)
                            withAnimation {
                                attachedFiles.append(attachment)
                            }
                        }
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

    private func isValidPDFFile(url: URL) -> Bool {
        return url.pathExtension.lowercased() == "pdf"
    }

    private func attachmentPreviewRequests(
        from attachments: [AttachmentItem]
    ) -> [QuickLookPreviewer.PreviewItemRequest] {
        var requests: [QuickLookPreviewer.PreviewItemRequest] = []

        for attachment in attachments {
            switch attachment {
            case .image(let imageAttachment):
                if let url = imageAttachment.previewURL() {
                    requests.append(
                        QuickLookPreviewer.PreviewItemRequest(
                            id: imageAttachment.id,
                            title: url.lastPathComponent,
                            url: url
                        )
                    )
                } else {
                    let title = imageAttachment.url?.lastPathComponent ?? "Image.jpg"
                    requests.append(
                        QuickLookPreviewer.PreviewItemRequest(
                            id: imageAttachment.id,
                            title: title
                        ) { completion in
                            imageAttachment.fetchPreviewURL(completion: completion)
                        }
                    )
                }
            case .file(let fileAttachment):
                let title = fileAttachment.filename.isEmpty ? "Document.pdf" : fileAttachment.filename
                if let url = fileAttachment.previewURL() {
                    requests.append(
                        QuickLookPreviewer.PreviewItemRequest(
                            id: fileAttachment.id,
                            title: title,
                            url: url
                        )
                    )
                } else {
                    requests.append(
                        QuickLookPreviewer.PreviewItemRequest(
                            id: fileAttachment.id,
                            title: title
                        ) { completion in
                            fileAttachment.fetchPreviewURL(completion: completion)
                        }
                    )
                }
            }
        }

        return requests
    }

    private func orderedAttachmentItems() -> [AttachmentItem] {
        let imageMap = Dictionary(uniqueKeysWithValues: attachedImages.map { ($0.id, $0) })
        let fileMap = Dictionary(uniqueKeysWithValues: attachedFiles.map { ($0.id, $0) })

        return attachmentOrder.compactMap { key in
            switch key {
            case .image(let id):
                if let attachment = imageMap[id] {
                    return .image(attachment)
                }
            case .file(let id):
                if let attachment = fileMap[id] {
                    return .file(attachment)
                }
            }
            return nil
        }
    }

    private func syncAttachmentOrder() {
        let currentKeys = attachedImages.map { AttachmentKey.image($0.id) }
            + attachedFiles.map { AttachmentKey.file($0.id) }

        if attachmentOrder.isEmpty {
            attachmentOrder = currentKeys
            return
        }

        let currentSet = Set(currentKeys)
        attachmentOrder.removeAll { !currentSet.contains($0) }

        let existingSet = Set(attachmentOrder)
        let newKeys = currentKeys.filter { !existingSet.contains($0) }
        attachmentOrder.append(contentsOf: newKeys)
    }

    private func applyAttachmentOrder(_ order: [AttachmentKey]) {
        let imageMap = Dictionary(uniqueKeysWithValues: attachedImages.map { ($0.id, $0) })
        let fileMap = Dictionary(uniqueKeysWithValues: attachedFiles.map { ($0.id, $0) })

        var newImages: [ImageAttachment] = []
        var newFiles: [DocumentAttachment] = []

        for key in order {
            switch key {
            case .image(let id):
                if let attachment = imageMap[id] {
                    newImages.append(attachment)
                }
            case .file(let id):
                if let attachment = fileMap[id] {
                    newFiles.append(attachment)
                }
            }
        }

        attachedImages = newImages
        attachedFiles = newFiles
    }

    private enum AttachmentKey: Hashable {
        case image(UUID)
        case file(UUID)
    }

    private enum AttachmentItem: Identifiable {
        case image(ImageAttachment)
        case file(DocumentAttachment)

        var id: AttachmentKey {
            switch self {
            case .image(let attachment):
                return .image(attachment.id)
            case .file(let attachment):
                return .file(attachment.id)
            }
        }

        var dragIdentifier: String {
            switch self {
            case .image(let attachment):
                return "image:\(attachment.id.uuidString)"
            case .file(let attachment):
                return "file:\(attachment.id.uuidString)"
            }
        }
    }

    private struct AttachmentDropDelegate: DropDelegate {
        let item: AttachmentKey
        @Binding var order: [AttachmentKey]
        @Binding var dragging: AttachmentKey?
        let onMove: ([AttachmentKey]) -> Void

        func dropEntered(info: DropInfo) {
            guard let dragging, dragging != item else { return }
            guard let fromIndex = order.firstIndex(of: dragging),
                  let toIndex = order.firstIndex(of: item) else {
                return
            }

            if order[toIndex] != dragging {
                let updated = move(order, fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex)
                order = updated
                onMove(updated)
            }
        }

        func dropUpdated(info: DropInfo) -> DropProposal? {
            DropProposal(operation: .move)
        }

        func performDrop(info: DropInfo) -> Bool {
            dragging = nil
            return true
        }

        private func move(_ values: [AttachmentKey], fromOffsets: IndexSet, toOffset: Int) -> [AttachmentKey] {
            var updated = values
            updated.move(fromOffsets: fromOffsets, toOffset: toOffset)
            return updated
        }
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
    var onPreview: () -> Void
    var onRemove: (Int) -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: {
                onPreview()
            }) {
                Group {
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
            .buttonStyle(PlainButtonStyle())
            .disabled(attachment.isLoading || attachment.error != nil)

            if attachment.isPreparingPreview {
                ProgressView()
                    .scaleEffect(0.7)
                    .padding(6)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .padding(6)
            }

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
    }
}

struct FilePreviewView: View {
    @ObservedObject var attachment: DocumentAttachment
    var onPreview: () -> Void
    var onRemove: (Int) -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let previewSize: CGFloat = 80
        let overlayHeight: CGFloat = previewSize * 0.45

        ZStack(alignment: .topTrailing) {
            Button(action: {
                onPreview()
            }) {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.1))
                        .frame(width: previewSize, height: previewSize)

                    if attachment.isLoading {
                        ProgressView()
                            .frame(width: previewSize, height: previewSize)
                    }
                    else if let error = attachment.error {
                        VStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.red)
                            Text("Error")
                                .font(.caption)
                        }
                        .frame(width: previewSize, height: previewSize)
                        .help(error.localizedDescription)
                    }
                    else {
                        let displayName = attachment.filename.isEmpty ? "Document.pdf" : attachment.filename
                        let hasThumbnail = (attachment.thumbnail != nil)

                        if let thumbnail = attachment.thumbnail {
                            Image(nsImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: previewSize, height: previewSize)
                        }

                        if hasThumbnail {
                            Rectangle()
                                .fill(.ultraThinMaterial)
                                .mask(
                                    LinearGradient(
                                        colors: [.clear, .black],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .overlay(
                                    LinearGradient(
                                        colors: gradientColors,
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                    .opacity(0.85)
                                )
                                .frame(height: overlayHeight)
                                .frame(maxWidth: previewSize)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            if attachment.previewUnavailable && !hasThumbnail {
                                Text("Preview unavailable")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(secondaryTextColor)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            Text(displayName)
                                .font(.caption2.weight(.semibold))
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .foregroundColor(primaryTextColor)
                                .shadow(color: shadowColor, radius: 1, x: 0, y: 1)
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 6)
                        .frame(width: previewSize, height: previewSize, alignment: .bottomLeading)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(borderColor, lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(attachment.isLoading || attachment.error != nil)

            if attachment.isPreparingPreview {
                ProgressView()
                    .scaleEffect(0.7)
                    .padding(6)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .padding(6)
            }

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
    }

    private var gradientColors: [Color] {
        if colorScheme == .dark {
            return [
                Color.black.opacity(0.0),
                Color.black.opacity(0.6),
                Color.black.opacity(0.85),
            ]
        }
        return [
            Color.white.opacity(0.0),
            Color.white.opacity(0.7),
            Color.white.opacity(0.92),
        ]
    }

    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black
    }

    private var secondaryTextColor: Color {
        colorScheme == .dark ? .white.opacity(0.85) : .black.opacity(0.65)
    }

    private var shadowColor: Color {
        colorScheme == .dark ? .black.opacity(0.55) : .white.opacity(0.6)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
    }
}
