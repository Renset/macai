//
//  PreferencesView.swift
//  macai
//
//  Created by Renat Notfullin on 11.03.2023.
//

import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#endif

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
                    #if os(iOS)
                    Label("Services", systemImage: "network")
                    #else
                    Label("API Services", systemImage: "network")
                    #endif
                }

            TabAIPersonasView()
                .tabItem {
                    #if os(iOS)
                    Label("Personas", systemImage: "person.2")
                    #else
                    Label("AI Assistants", systemImage: "person.2")
                    #endif
                }

            BackupRestoreView(store: store)
                .tabItem {
                    #if os(iOS)
                    Label("Backup", systemImage: "externaldrive")
                    #else
                    Label("Backup & Restore", systemImage: "externaldrive")
                    #endif
                }

            DangerZoneView(store: store)
                .tabItem {
                    Label("Danger Zone", systemImage: "flame.fill")
                }
        }
        #if os(macOS)
        .frame(width: 480)
        .padding()
        #endif
        .onAppear(perform: {
            store.saveInCoreData()
            #if os(macOS)
            if let window = NSApp.mainWindow {
                window.standardWindowButton(.zoomButton)?.isEnabled = false
            }
            #endif
        })
    }
}
