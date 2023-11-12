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
    @AppStorage("gptToken") var gptToken: String = ""
    @AppStorage("gptModel") var gptModel: String = AppConstants.chatGptDefaultModel
    @AppStorage("systemMessage") var systemMessage = AppConstants.chatGptSystemMessage
    @AppStorage("chatContext") var chatContext: Double = AppConstants.chatGptContextSize
    @AppStorage("isCustomGptModel") var isCustomGptModel: Bool = false
    @AppStorage("apiUrl") var apiUrl: String = AppConstants.apiUrlChatCompletions
    @StateObject private var store = ChatStore(persistenceController: PersistenceController.shared)
    @State private var lampColor: Color = .gray

    var body: some View {
        TabView {
            GeneralSettingsView(gptToken: $gptToken, apiUrl: $apiUrl, chatContext: $chatContext, lampColor: $lampColor)
                .tabItem {
                    Label("ChatGPT API", systemImage: "gearshape")
                }

            ChatSettingsView(lampColor: $lampColor)
                .tabItem {
                    Label("New Chat", systemImage: "message")
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
        .frame(width: 600, height: 380)
        .padding()
        .onAppear(perform: {
            store.saveInCoreData()
            
            if let window = NSApp.mainWindow {
                window.standardWindowButton(.zoomButton)?.isEnabled = false
            }
        })
    }
}
