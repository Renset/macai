//
//  Vendored from https://github.com/gonzalezreal/AttributedText (MIT License,
//  Copyright (c) 2020 Guille Gonzalez). Vendored to fix window sizing: the
//  NSTextView's intrinsic text width must be advisory, not required.
//

#if os(macOS)
  import SwiftUI

  extension AttributedTextImpl: NSViewRepresentable {
    func makeNSView(context: Context) -> TextView {
      let nsView = TextView(frame: .zero)

      nsView.drawsBackground = false
      nsView.textContainerInset = .zero
      nsView.isEditable = false
      nsView.isRichText = false
      nsView.textContainer?.lineFragmentPadding = 0
      // we are setting the container's width manually
      nsView.textContainer?.widthTracksTextView = false
      nsView.delegate = context.coordinator

      // macai fix: keep the intrinsic text width advisory. With the default
      // (required-ish) compression resistance, AppKit propagates the widest
      // rendered line through NSHostingView and the split views into the
      // window's minimum size, making the window impossible to shrink.
      nsView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

      return nsView
    }

    func updateNSView(_ nsView: TextView, context: Context) {
      nsView.textStorage?.setAttributedString(attributedText)
      nsView.maxLayoutWidth = maxLayoutWidth

      nsView.textContainer?.maximumNumberOfLines = context.environment.lineLimit ?? 0
      nsView.textContainer?.lineBreakMode = NSLineBreakMode(
        truncationMode: context.environment.truncationMode
      )
      context.coordinator.openLink = onOpenLink ?? { context.environment.openURL($0) }
      textSizeViewModel.didUpdateTextView(nsView)
    }

    func makeCoordinator() -> Coordinator {
      Coordinator()
    }
  }

  extension AttributedTextImpl {
    final class TextView: NSTextView {
      var maxLayoutWidth: CGFloat {
        get { textContainer?.containerSize.width ?? 0 }
        set {
          guard textContainer?.containerSize.width != newValue else { return }
          textContainer?.containerSize.width = newValue
          invalidateIntrinsicContentSize()
        }
      }

      /// Natural size of the laid-out text. Reported to SwiftUI through
      /// TextSizeViewModel; deliberately kept out of `intrinsicContentSize`.
      var naturalContentSize: NSSize {
        guard maxLayoutWidth > 0,
          let textContainer = self.textContainer,
          let layoutManager = self.layoutManager
        else {
          return super.intrinsicContentSize
        }

        layoutManager.ensureLayout(for: textContainer)
        return layoutManager.usedRect(for: textContainer).size
      }

      // macai fix: never advertise the text width to Auto Layout. `fittingSize`
      // honors the intrinsic width even at low compression-resistance priority,
      // and NSHostingView/NSSplitView propagate it into the window's minimum
      // size — the window then cannot be made narrower than the widest rendered
      // line. Height stays intrinsic so vertical layout keeps working.
      override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: naturalContentSize.height)
      }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
      var openLink: ((URL) -> Void)?

      func textView(_: NSTextView, clickedOnLink link: Any, at _: Int) -> Bool {
        guard let openLink = self.openLink,
          let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:))
        else {
          return false
        }

        openLink(url)
        return true
      }
    }
  }
#endif
