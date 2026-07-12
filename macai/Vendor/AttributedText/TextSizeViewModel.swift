//
//  Vendored from https://github.com/gonzalezreal/AttributedText (MIT License,
//  Copyright (c) 2020 Guille Gonzalez). Vendored to fix window sizing: the
//  NSTextView's intrinsic text width must be advisory, not required.
//

import SwiftUI

final class TextSizeViewModel {
  @Published var textSize: CGSize?

  func didUpdateTextView(_ textView: AttributedTextImpl.TextView) {
    // macai fix: intrinsicContentSize no longer carries the width (see
    // AttributedTextImpl+macOS.swift); use the natural text size instead.
    textSize = textView.naturalContentSize
  }
}
