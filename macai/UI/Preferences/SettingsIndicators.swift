//
//  SettingsIndicators.swift
//  macai
//
//  Created by Renat Notfullin on 18.12.2025.
//

import SwiftUI

enum SettingsIndicatorKeys {
    static let generalSeen = "SettingsIndicator.GeneralSeen"
    static let backupSeen = "SettingsIndicator.BackupSeen"
    static let iCloudSectionSeen = "SettingsIndicator.ICloudSectionSeen"
    static let backupSectionSeen = "SettingsIndicator.BackupSectionSeen"
}

enum SettingsIndicatorState {
    static func needsAttention(
        generalSeen: Bool,
        backupSeen: Bool,
        iCloudSectionSeen: Bool,
        backupSectionSeen: Bool
    ) -> Bool {
        return !(generalSeen && backupSeen && iCloudSectionSeen && backupSectionSeen)
    }
}

struct SettingsIndicatorDot: View {
    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 6, height: 6)
            .shadow(color: Color.red.opacity(0.35), radius: 1, x: 0, y: 0)
            .accessibilityLabel("New settings")
    }
}

struct SettingsIndicatorBadge: View {
    let text: String
    var color: Color = Color(red: 0.92, green: 0.62, blue: 0.18)

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color))
            .accessibilityLabel(text)
    }
}

struct SettingsTabIcon: View {
    let systemName: String
    let showsIndicator: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: systemName)
                .frame(width: 18, height: 18)
            if showsIndicator {
                SettingsIndicatorDot()
                    .offset(x: 6, y: -4)
            }
        }
        .frame(width: 20, height: 20)
    }
}
