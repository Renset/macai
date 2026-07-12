//
//  PreferencesView.swift
//  macai
//
//  Created by Renat Notfullin on 11.03.2023.
//

import Foundation
import SwiftUI

struct APIRequestData: Codable {
    let model: String
    let messages = [
        [
            "role": "system",
            "content": "You are ChatGPT, a large language model trained by OpenAI. Say hi, if you're there",
        ]
    ]
}

struct PreferencesView: View {
    @StateObject private var store = ChatStore(persistenceController: PersistenceController.shared)
    @AppStorage(AppConstants.selectedPreferencesTabKey) private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("General", systemImage: "gearshape", value: 0) {
                TabGeneralSettingsView()
            }
            Tab("API Services", systemImage: "network", value: 1) {
                TabAPIServicesView()
            }
            Tab("AI Assistants", systemImage: "person.2", value: 2) {
                TabAIPersonasView()
            }
            Tab("Backup & Restore", systemImage: "externaldrive", value: 3) {
                BackupRestoreView(store: store)
            }
            Tab("Danger Zone", systemImage: "flame.fill", value: 4) {
                DangerZoneView(store: store)
            }
        }
        .frame(width: 480)
        .padding()
        .onAppear(perform: {
            store.saveInCoreData()

            if let window = NSApp.mainWindow {
                window.standardWindowButton(.zoomButton)?.isEnabled = false
            }

        })
    }
}
