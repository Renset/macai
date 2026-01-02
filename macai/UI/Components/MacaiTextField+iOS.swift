//
//  MacaiTextField+iOS.swift
//  macai
//
//  iOS implementation of MacaiTextField.
//

#if os(iOS)
import SwiftUI
import UIKit

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
                returnKeyType: returnKeyType,
                onCommit: onCommit
            )
        }
        .frame(height: min(max(currentHeight, minHeight), maxHeight))
        .frame(maxWidth: .infinity)
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

private struct MacaiTextFieldRep: UIViewRepresentable {
    @Binding var text: String
    var isFocused: Binding<Bool>?
    @Binding var height: CGFloat
    var fontSize: CGFloat?
    var minHeight: CGFloat
    var maxHeight: CGFloat
    var returnKeyType: MacaiTextField.ReturnKeyType
    var onCommit: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.text = text
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.font = UIFont.systemFont(ofSize: fontSize ?? UIFont.systemFontSize)
        textView.returnKeyType = mapReturnKey(returnKeyType)
        context.coordinator.textView = textView
        updateHeight(for: textView)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self

        if textView.text != text {
            textView.text = text
        }

        textView.font = UIFont.systemFont(ofSize: fontSize ?? UIFont.systemFontSize)
        textView.returnKeyType = mapReturnKey(returnKeyType)
        updateHeight(for: textView)
        updateFocus(for: textView)
    }

    private func mapReturnKey(_ type: MacaiTextField.ReturnKeyType) -> UIReturnKeyType {
        switch type {
        case .done: return .done
        case .next: return .next
        case .continue: return .continue
        case .go: return .go
        case .search: return .search
        case .send: return .send
        case .default: return .default
        }
    }

    private func updateHeight(for textView: UITextView) {
        let targetWidth = textView.bounds.width
        let fittingSize = CGSize(width: targetWidth > 0 ? targetWidth : UIScreen.main.bounds.width, height: .greatestFiniteMagnitude)
        let size = textView.sizeThatFits(fittingSize)
        let newHeight = max(minHeight, min(size.height, maxHeight))
        if abs(height - newHeight) > 0.5 {
            DispatchQueue.main.async {
                height = newHeight
            }
        }
    }

    private func updateFocus(for textView: UITextView) {
        guard let isFocused else { return }
        DispatchQueue.main.async {
            if isFocused.wrappedValue, !textView.isFirstResponder {
                textView.becomeFirstResponder()
            } else if !isFocused.wrappedValue, textView.isFirstResponder {
                textView.resignFirstResponder()
            }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: MacaiTextFieldRep
        weak var textView: UITextView?

        init(_ parent: MacaiTextFieldRep) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            parent.updateHeight(for: textView)
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n", let onCommit = parent.onCommit {
                onCommit()
                return false
            }
            return true
        }
    }
}
#endif
