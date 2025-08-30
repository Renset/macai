//
//  HighlightedText.swift
//  macai
//
//  Created by Renat Notfullin on 01.12.2024.
//

import SwiftUI

struct HighlightedText: View {
    let text: String
    let highlight: String
    let color: Color
    let message: MessageEntity?
    let currentSearchOccurrence: SearchOccurrence?
    let originalContent: String
    let elementIndex: Int
    let elementType: String
    let cellPosition: Int

    init(_ text: String, highlight: String, color: Color = .yellow, message: MessageEntity? = nil, currentSearchOccurrence: SearchOccurrence? = nil, originalContent: String? = nil, elementIndex: Int = 0, elementType: String = "text", cellPosition: Int = 0) {
        self.text = text
        self.highlight = highlight.lowercased()
        self.color = color
        self.message = message
        self.currentSearchOccurrence = currentSearchOccurrence
        self.originalContent = originalContent ?? text
        self.elementIndex = elementIndex
        self.elementType = elementType
        self.cellPosition = cellPosition
    }

    var body: some View {
        guard !highlight.isEmpty else {
            return Text(text).eraseToAnyView()
        }

        let attributedString = NSMutableAttributedString(string: text)
        let range = NSString(string: text.lowercased())
        let originalRange = NSString(string: originalContent.lowercased())
        var location = 0
        var originalLocation = 0

        while location < text.count && originalLocation < originalContent.count {
            let searchRange = NSRange(location: location, length: text.count - location)
            let originalSearchRange = NSRange(location: originalLocation, length: originalContent.count - originalLocation)
            let foundRange = range.range(of: highlight, options: [], range: searchRange)
            let originalFoundRange = originalRange.range(of: highlight, options: [], range: originalSearchRange)

            if foundRange.location != NSNotFound && originalFoundRange.location != NSNotFound {
                var highlightColor = NSColor(Color(hex: AppConstants.defaultHighlightColor) ?? Color.gray).withAlphaComponent(0.3)
                
                // Check if this is the current occurrence
                if let messageId = message?.objectID, let currentOccurrence = currentSearchOccurrence {
                    let adjustedRange = elementType == "table" ? NSRange(location: foundRange.location + cellPosition * 10000, length: foundRange.length) : foundRange
                    let occurrence = SearchOccurrence(messageID: messageId, range: adjustedRange, elementIndex: elementIndex, elementType: elementType)
                    if occurrence == currentOccurrence {
                        highlightColor = NSColor(Color(hex: AppConstants.currentHighlightColor) ?? Color.yellow)
                    }
                }
                
                attributedString.addAttribute(.backgroundColor, value: highlightColor, range: foundRange)
                location = foundRange.location + foundRange.length
                originalLocation = originalFoundRange.location + originalFoundRange.length
            }
            else {
                break
            }
        }

        return Text(AttributedString(attributedString))
            .eraseToAnyView()
    }
}

extension Color {
    func withAlphaComponent(_ alpha: CGFloat) -> NSColor {
        return NSColor(self).withAlphaComponent(alpha)
    }
}

extension View {
    func eraseToAnyView() -> AnyView {
        AnyView(self)
    }
}
