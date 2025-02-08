//
//  TabGeneralSettingsView.swift
//  macai
//
//  Created by Renat on 31.01.2025.
//

import Sparkle
import SwiftUI

struct TabGeneralSettingsView: View {
    @AppStorage("autoCheckForUpdates") var autoCheckForUpdates = true
    @AppStorage("chatFontSize") var chatFontSize: Double = 14.0
    @AppStorage("preferredColorScheme") private var preferredColorSchemeRaw: Int = 0
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var selectedColorSchemeRaw: Int = 0

    private var preferredColorScheme: Binding<ColorScheme?> {
        Binding(
            get: {
                switch preferredColorSchemeRaw {
                case 1: return .light
                case 2: return .dark
                default: return nil
                }
            },
            set: { newValue in
                // This ugly solution is needed to workaround the SwiftUI (?) bug with the view not updated completely on setting theme to System
                if newValue == nil {
                    let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    preferredColorSchemeRaw = isDark ? 2 : 1
                    selectedColorSchemeRaw = 0

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        preferredColorSchemeRaw = 0
                    }
                }
                else {
                    switch newValue {
                    case .light: preferredColorSchemeRaw = 1
                    case .dark: preferredColorSchemeRaw = 2
                    case .none: preferredColorSchemeRaw = 0
                    case .some(_):
                        preferredColorSchemeRaw = 0
                    }
                    selectedColorSchemeRaw = preferredColorSchemeRaw
                }
            }
        )
    }

    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Form {
                GroupBox {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 16) {
                        GridRow {
                            HStack {
                                Text("Chat Font Size")
                                Spacer()
                            }
                            .frame(width: 120)
                            .gridCellAnchor(.top)

                            VStack(spacing: 4) {
                                HStack {
                                    Text("A")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 12))

                                    Slider(value: $chatFontSize, in: 10...24, step: 1)
                                        .frame(width: 200)

                                    Text("A")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 20))
                                }
                                Text("Example \(Int(chatFontSize))pt")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: chatFontSize))
                            }
                            .frame(maxWidth: .infinity)
                        }

                        Divider()

                        GridRow {
                            HStack {
                                Text("Theme")
                                Spacer()
                            }
                            .frame(width: 120)
                            .gridCellAnchor(.top)

                            HStack(spacing: 12) {
                                ThemeButton(
                                    title: "macOS",
                                    isSelected: selectedColorSchemeRaw == 0,
                                    mode: .system
                                ) {
                                    preferredColorScheme.wrappedValue = nil
                                }

                                ThemeButton(
                                    title: "Light",
                                    isSelected: selectedColorSchemeRaw == 1,
                                    mode: .light
                                ) {
                                    preferredColorScheme.wrappedValue = .light
                                }

                                ThemeButton(
                                    title: "Dark",
                                    isSelected: selectedColorSchemeRaw == 2,
                                    mode: .dark
                                ) {
                                    preferredColorScheme.wrappedValue = .dark
                                }
                            }
                            .gridColumnAlignment(.trailing)
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(8)
                }
            }

            HStack {
                Toggle("Automatically check for updates", isOn: $autoCheckForUpdates)
                    .onChange(of: autoCheckForUpdates) { newValue in
                        updaterController.updater.automaticallyChecksForUpdates = newValue
                    }

                Spacer()

                Button("Check for Updates Now") {
                    updaterController.checkForUpdates(nil)
                }
            }

        }
        .padding()
        .onAppear {
            self.selectedColorSchemeRaw = self.preferredColorSchemeRaw
        }
    }
}
