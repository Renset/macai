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
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    var body: some View {
        VStack {
            HStack {
                Toggle("Automatically check for updates", isOn: $autoCheckForUpdates)
                    .onChange(of: autoCheckForUpdates) { newValue in
                        updaterController.updater.automaticallyChecksForUpdates = newValue
                    }
                
                Spacer()

                Button("Check for Updates Now") {
                    updaterController.updater.checkForUpdates()
                }
            }
        }
        .padding()
    }
}
