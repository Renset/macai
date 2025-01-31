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
    @State private var lampColor: Color = .gray

    var body: some View {
        TabView {

            TabGeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }

            TabAPIServicesView()
                .tabItem {
                    Label("API Services", systemImage: "network")
                }

            TabAIPersonasView()
                .tabItem {
                    Label("AI Assistants", systemImage: "person.2")
                }

            BackupRestoreView(store: store)
                .tabItem {
                    Label("Backup & Restore", systemImage: "externaldrive")
                }

            DangerZoneView(store: store)
                .tabItem {
                    Label("Danger Zone", systemImage: "flame.fill")
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
