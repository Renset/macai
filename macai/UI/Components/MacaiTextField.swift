//
//  MacaiTextField.swift
//  macai
//
//  Created by Renat Notfullin on 20.12.2025
//

import SwiftUI

#if os(macOS)
import AppKit
import UniformTypeIdentifiers

struct PastedPDF {
    let url: URL?
    let data: Data?
    let filename: String
}

struct MacaiTextField: View {
    var title: String
    @Binding var text: String
    var isFocused: Binding<Bool>?
    var returnKeyType: ReturnKeyType
    var fontSize: CGFloat?
    var minHeight: CGFloat
    var maxHeight: CGFloat
    var onCommit: (() -> Void)?
    var onTab: (() -> Void)?
    var onBackTab: (() -> Void)?
    var onEscape: (() -> Void)?
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    var onPasteImage: ((NSImage) -> Void)?
    var onPastePDF: ((PastedPDF) -> Void)?
    var handlesPasteAttachments: Bool

    @State private var measuredHeight: CGFloat
    @State private var placeholderHeight: CGFloat = 0

    init<S: StringProtocol>(
        _ title: S,
        text: Binding<String>,
        isFocused: Binding<Bool>? = nil,
        returnKeyType: ReturnKeyType = .default,
        fontSize: CGFloat? = nil,
        minHeight: CGFloat = 16,
        maxHeight: CGFloat = 160,
        onTab: (() -> Void)? = nil,
        onBackTab: (() -> Void)? = nil,
        onEscape: (() -> Void)? = nil,
        onMoveUp: (() -> Void)? = nil,
        onMoveDown: (() -> Void)? = nil,
        onPasteImage: ((NSImage) -> Void)? = nil,
        onPastePDF: ((PastedPDF) -> Void)? = nil,
        handlesPasteAttachments: Bool = false,
        onCommit: (() -> Void)? = nil
    ) {
        self.title = String(title)
        _text = text
        self.isFocused = isFocused
        self.returnKeyType = returnKeyType
        self.fontSize = fontSize
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        self.onCommit = onCommit
        self.onTab = onTab
        self.onBackTab = onBackTab
        self.onEscape = onEscape
        self.onMoveUp = onMoveUp
        self.onMoveDown = onMoveDown
        self.onPasteImage = onPasteImage
        self.onPastePDF = onPastePDF
        self.handlesPasteAttachments = handlesPasteAttachments
        _measuredHeight = State(initialValue: minHeight)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text(title)
                .foregroundColor(.secondary)
                .opacity(text.isEmpty ? 0.5 : 0)
                .animation(nil, value: text)
                .font(fontSize.map { .system(size: $0) })
                .fixedSize(horizontal: false, vertical: true)
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear {
                                placeholderHeight = proxy.size.height
                            }
                            .onChange(of: proxy.size) { _, newSize in
                                placeholderHeight = newSize.height
                            }
                    }
                )

            MacaiTextFieldRep(
                text: $text,
                isFocused: isFocused,
                height: $measuredHeight,
                fontSize: fontSize,
                minHeight: minHeight,
                maxHeight: maxHeight,
                onCommit: onCommit,
                onTab: onTab,
                onBackTab: onBackTab,
                onEscape: onEscape,
                onMoveUp: onMoveUp,
                onMoveDown: onMoveDown,
                onPasteImage: onPasteImage,
                onPastePDF: onPastePDF,
                handlesPasteAttachments: handlesPasteAttachments
            )
        }
        .frame(height: min(max(currentHeight, minHeight), maxHeight))
    }

    private var currentHeight: CGFloat {
        if text.isEmpty {
            return max(measuredHeight, placeholderHeight)
        }
        return measuredHeight
    }
}

extension MacaiTextField {
    enum ReturnKeyType: String, CaseIterable {
        case done
        case next
        case `default`
        case `continue`
        case go
        case search
        case send
    }
}

private struct MacaiTextFieldRep: NSViewRepresentable {
    @Binding var text: String
    var isFocused: Binding<Bool>?
    @Binding var height: CGFloat
    var fontSize: CGFloat?
    var minHeight: CGFloat
    var maxHeight: CGFloat
    var onCommit: (() -> Void)?
    var onTab: (() -> Void)?
    var onBackTab: (() -> Void)?
    var onEscape: (() -> Void)?
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    var onPasteImage: ((NSImage) -> Void)?
    var onPastePDF: ((PastedPDF) -> Void)?
    var handlesPasteAttachments: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = makeTextView()
        textView.focusBinding = isFocused
        textView.onPasteImage = onPasteImage
        textView.onPastePDF = onPastePDF
        textView.handlesPasteAttachments = handlesPasteAttachments
        textView.delegate = context.coordinator
        textView.string = text
        if let fontSize {
            textView.font = NSFont.systemFont(ofSize: fontSize)
        }
        textView.onSizeChange = { [weak textView, weak coordinator = context.coordinator] in
            guard let textView, let coordinator else { return }
            coordinator.updateHeight(for: textView)
        }

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = textView

        context.coordinator.textView = textView
        updateHeight(for: textView)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self

        guard let textView = scrollView.documentView as? MacaiNSTextView else { return }
        textView.focusBinding = isFocused
        textView.onPasteImage = onPasteImage
        textView.onPastePDF = onPastePDF
        textView.handlesPasteAttachments = handlesPasteAttachments

        if textView.string != text, !textView.hasMarkedText() {
            let selectedRange = textView.selectedRange()
            textView.string = text
            let clampedLocation = min(selectedRange.location, (text as NSString).length)
            textView.setSelectedRange(NSRange(location: clampedLocation, length: 0))
        }

        if let fontSize {
            textView.font = NSFont.systemFont(ofSize: fontSize)
        }

        updateHeight(for: textView)
        updateFocus(for: textView)
    }

    private func makeTextView() -> MacaiNSTextView {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)

        let textView = MacaiNSTextView(frame: .zero, textContainer: textContainer)
        textView.backgroundColor = NSColor.clear
        textView.drawsBackground = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.textContainerInset = NSSize.zero
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = NSView.AutoresizingMask.width
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: minHeight)
        textView.focusRingType = NSFocusRingType.none

        return textView
    }

    private func updateHeight(for textView: NSTextView) {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer
        else { return }
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        let newHeight = max(minHeight, ceil(usedRect.height))
        if let scrollView = textView.enclosingScrollView {
            let targetWidth = scrollView.contentSize.width
            let targetHeight = newHeight
            if abs(textView.frame.size.width - targetWidth) > 0.5 || abs(textView.frame.size.height - targetHeight) > 0.5 {
                textView.setFrameSize(NSSize(width: max(targetWidth, 1), height: targetHeight))
            }
        }
        if abs(height - newHeight) > 0.5 {
            DispatchQueue.main.async {
                height = newHeight
            }
        }
    }

    private func updateFocus(for textView: NSTextView) {
        guard let isFocused else { return }
        DispatchQueue.main.async {
            let isFirstResponder = textView.window?.firstResponder == textView
            if isFocused.wrappedValue, textView.window != nil, !isFirstResponder {
                textView.window?.makeFirstResponder(textView)
            } else if !isFocused.wrappedValue, isFirstResponder {
                textView.window?.makeFirstResponder(nil)
            }
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MacaiTextFieldRep
        weak var textView: NSTextView?

        init(_ parent: MacaiTextFieldRep) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            updateHeight(for: textView)
            textView.scrollRangeToVisible(textView.selectedRange())
        }

        func textView(_: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if let onCommit = parent.onCommit,
               commandSelector == #selector(NSResponder.insertNewline(_:)),
               let event = NSApp.currentEvent,
               !event.modifierFlags.contains(.shift)
            {
                onCommit()
                return true
            } else if let onTab = parent.onTab,
                      commandSelector == #selector(NSResponder.insertTab(_:))
            {
                onTab()
                return true
            } else if let onBackTab = parent.onBackTab,
                      commandSelector == #selector(NSResponder.insertBacktab(_:))
            {
                onBackTab()
                return true
            } else if let onEscape = parent.onEscape,
                      commandSelector == #selector(NSResponder.cancelOperation(_:))
            {
                onEscape()
                return true
            } else if let onMoveUp = parent.onMoveUp,
                      commandSelector == #selector(NSResponder.moveUp(_:))
            {
                onMoveUp()
                return true
            } else if let onMoveDown = parent.onMoveDown,
                      commandSelector == #selector(NSResponder.moveDown(_:))
            {
                onMoveDown()
                return true
            }

            return false
        }

        func updateHeight(for textView: NSTextView) {
            parent.updateHeight(for: textView)
        }
    }
}

private final class MacaiNSTextView: NSTextView {
    var focusBinding: Binding<Bool>?
    var onSizeChange: (() -> Void)?
    var onPasteImage: ((NSImage) -> Void)?
    var onPastePDF: ((PastedPDF) -> Void)?
    var handlesPasteAttachments = false
    private var isUpdatingSize = false

    override func becomeFirstResponder() -> Bool {
        focusBinding?.wrappedValue = true
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        focusBinding?.wrappedValue = false
        return super.resignFirstResponder()
    }

    override func paste(_ sender: Any?) {
        let pasteboard = NSPasteboard.general

        if let file = pastedFile(from: pasteboard) {
            if file.type.conforms(to: .pdf), let onPastePDF {
                onPastePDF(PastedPDF(url: file.url, data: nil, filename: file.url.lastPathComponent))
            } else if file.type.conforms(to: .image),
                      let onPasteImage,
                      let image = NSImage(contentsOf: file.url)
            {
                onPasteImage(image)
            } else {
                NSSound.beep()
            }
            return
        }

        if pasteboard.availableType(from: [.fileURL]) != nil {
            NSSound.beep()
            return
        }

        if let pdfData = pasteboard.data(forType: .pdf) {
            if let onPastePDF {
                onPastePDF(PastedPDF(url: nil, data: pdfData, filename: "Pasted Document.pdf"))
            } else if handlesPasteAttachments {
                NSSound.beep()
            }
            return
        }

        if let image = pastedBitmap(from: pasteboard) {
            if let onPasteImage {
                onPasteImage(image)
            } else if handlesPasteAttachments {
                NSSound.beep()
            }
            return
        }
        super.paste(sender)
    }

    private func pastedFile(from pasteboard: NSPasteboard) -> (url: URL, type: UTType)? {
        let fileObjects = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [NSURL] ?? []

        guard fileObjects.count == 1 else { return nil }
        let url = fileObjects[0] as URL
        let type = UTType(filenameExtension: url.pathExtension) ?? .data
        return (url, type)
    }

    private func pastedBitmap(from pasteboard: NSPasteboard) -> NSImage? {
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pasteboard.data(forType: type),
               let image = NSImage(data: data)
            {
                return image
            }
        }
        return nil
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard window != nil else { return }
        guard !isUpdatingSize else { return }
        isUpdatingSize = true
        if Thread.isMainThread {
            onSizeChange?()
            isUpdatingSize = false
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.onSizeChange?()
                self?.isUpdatingSize = false
            }
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if shouldIgnoreFileDrop(sender) {
            return []
        }
        return super.draggingEntered(sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if shouldIgnoreFileDrop(sender) {
            return false
        }
        return super.prepareForDragOperation(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if shouldIgnoreFileDrop(sender) {
            return false
        }
        return super.performDragOperation(sender)
    }

    private func shouldIgnoreFileDrop(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        let types = [
            UTType.image.identifier,
            UTType.pdf.identifier,
            UTType.fileURL.identifier
        ]
        return pasteboard.canReadItem(withDataConformingToTypes: types)
    }
}
#endif
