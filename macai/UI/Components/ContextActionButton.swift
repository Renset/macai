//
//  ContextActionButton.swift
//  macai
//
//  Created by Renat on 10.02.2025.
//


import SwiftUI

struct ContextActionButton: View {
    let action: () -> Void
    let isWaitingForResponse: Bool
    let isEditingSystemMessage: Bool
    let hasInputText: Bool
    let hasMessages: Bool
    
    var body: some View {
        Button(action: action) {
            Image(systemName: iconName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Color.accentColor)
                .clipShape(Circle())
        }
        .buttonStyle(.borderless)
        .help(buttonTooltip)
    }
    
    private var iconName: String {
        if isWaitingForResponse {
            return "stop.fill"
        } else if isEditingSystemMessage {
            return "checkmark"
        } else if !hasInputText && hasMessages {
            return "arrow.clockwise"
        } else {
            return "arrow.up"
        }
    }
    
    private var buttonTooltip: String {
        if isWaitingForResponse {
            return "Stop generating"
        } else if isEditingSystemMessage {
            return "Save system message"
        } else if !hasInputText && hasMessages {
            return "Retry last message"
        } else {
            return "Send message"
        }
    }
}
