//
//  ToolbarButton.swift
//  macai
//
//  Created by Renat on 04.04.2025.
//

import SwiftUI

struct ToolbarButton: View {
    let icon: String
    let text: String
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .imageScale(.small)
                .frame(width: 10)
            Text(text)
                .font(.system(size: 12))
        }
        .buttonStyle(PlainButtonStyle())
        .foregroundColor(isHovered ? .primary : .gray.opacity(0.7))
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeInOut(duration: 0.2), value: isHovered)
    }
}
