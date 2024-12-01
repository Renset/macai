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

    init(_ text: String, highlight: String, color: Color = .yellow) {
        self.text = text
        self.highlight = highlight.lowercased()
        self.color = color
    }

    var body: some View {
        guard !highlight.isEmpty else {
            return Text(text).eraseToAnyView()
        }

        let attributedString = NSMutableAttributedString(string: text)
        let range = NSString(string: text.lowercased())
        var location = 0

        while location < text.count {
            let searchRange = NSRange(location: location, length: text.count - location)
            let foundRange = range.range(of: highlight, options: [], range: searchRange)

            if foundRange.location != NSNotFound {
                attributedString.addAttribute(.backgroundColor, value: color.withAlphaComponent(0.2), range: foundRange)
                location = foundRange.location + foundRange.length
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
