//
//  Vendored from https://github.com/gonzalezreal/AttributedText (MIT License,
//  Copyright (c) 2020 Guille Gonzalez). Vendored to fix window sizing: the
//  NSTextView's intrinsic text width must be advisory, not required.
//

import SwiftUI

struct AttributedTextImpl {
  var attributedText: NSAttributedString
  var maxLayoutWidth: CGFloat
  var textSizeViewModel: TextSizeViewModel
  var onOpenLink: ((URL) -> Void)?
}
