//
//  HighlighterManager.swift
//  macai
//
//  Created by Renat Notfullin on 17.11.2024.
//

import Highlightr
import SwiftUI

class HighlighterManager {
    static let shared = HighlighterManager()
    private let highlightr = Highlightr()
    private let cache = NSCache<NSString, NSAttributedString>()
    @AppStorage("codeFont") private var codeFont: String = AppConstants.firaCode

    func highlight(code: String, language: String, theme: String, fontSize: Double = 14, isStreaming: Bool = false) -> NSAttributedString? {
        var cacheKey: NSString = ""
        if !isStreaming {
            cacheKey = "\(code):\(language):\(theme):\(codeFont)" as NSString

            if let cached = cache.object(forKey: cacheKey) {
                return cached
            }
        }

        highlightr?.setTheme(to: theme)
        if let highlighted = highlightr?.highlight(code, as: language) {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont(name: codeFont, size: fontSize - 1)
                    ?? NSFont.systemFont(ofSize: fontSize - 1)
            ]
            let attributedString = NSMutableAttributedString(attributedString: highlighted)
            attributedString.addAttributes(attributes, range: NSRange(location: 0, length: attributedString.length))

            if !isStreaming {
                cache.setObject(attributedString, forKey: cacheKey)
            }
            return attributedString
        }
        return nil
    }
    
    func invalidateCache() {
        cache.removeAllObjects()
    }
    
}
