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
                switch newValue {
                case .light: preferredColorSchemeRaw = 1
                case .dark: preferredColorSchemeRaw = 2
                case .none: preferredColorSchemeRaw = 0
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
                                    title: "Auto",
                                    isSelected: preferredColorScheme.wrappedValue == nil,
                                    mode: .system
                                ) {
                                    preferredColorScheme.wrappedValue = nil
                                }

                                ThemeButton(
                                    title: "Light",
                                    isSelected: preferredColorScheme.wrappedValue == .light,
                                    mode: .light
                                ) {
                                    preferredColorScheme.wrappedValue = .light
                                }

                                ThemeButton(
                                    title: "Dark",
                                    isSelected: preferredColorScheme.wrappedValue == .dark,
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
    }
}
