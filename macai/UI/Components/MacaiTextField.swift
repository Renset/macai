//
//  MacaiTextField.swift
//  macai
//
//  Created by Renat on 2025-12-20
//

import SwiftUI

#if os(macOS)
import AppKit

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
                onBackTab: onBackTab
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

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = makeTextView()
        textView.focusBinding = isFocused
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

    override func becomeFirstResponder() -> Bool {
        focusBinding?.wrappedValue = true
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        focusBinding?.wrappedValue = false
        return super.resignFirstResponder()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        onSizeChange?()
    }
}
#endif
