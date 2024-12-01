//
//  HighlighterManager.swift
//  macai
//
//  Created by Renat Notfullin on 17.11.2024.
//

import SwiftUI
import Highlightr

class HighlighterManager {
    static let shared = HighlighterManager()
    private let highlightr = Highlightr()
    private let cache = NSCache<NSString, NSAttributedString>()
    
    func highlight(code: String, language: String, theme: String, isStreaming: Bool = false) -> NSAttributedString? {
        var cacheKey: NSString = ""
        if !isStreaming {
            cacheKey = "\(code):\(language):\(theme)" as NSString
            
            if let cached = cache.object(forKey: cacheKey) {
                return cached
            }
        }
        
        highlightr?.setTheme(to: theme)
        if let highlighted = highlightr?.highlight(code, as: language) {
            if !isStreaming {
                cache.setObject(highlighted, forKey: cacheKey)
            }
            return highlighted
        }
        return nil
    }
}
