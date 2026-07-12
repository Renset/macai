//
//  Vendored from https://github.com/gonzalezreal/AttributedText (MIT License,
//  Copyright (c) 2020 Guille Gonzalez). Vendored to fix window sizing: the
//  NSTextView's intrinsic text width must be advisory, not required.
//

import SwiftUI

extension NSLineBreakMode {
  init(truncationMode: Text.TruncationMode) {
    switch truncationMode {
    case .head:
      self = .byTruncatingHead
    case .tail:
      self = .byTruncatingTail
    case .middle:
      self = .byTruncatingMiddle
    @unknown default:
      self = .byWordWrapping
    }
  }
}
