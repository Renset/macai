//
//  macaiApp.swift
//  macai
//
//  Created by Renat Notfullin on 11.03.2023.
//

import SwiftUI
import Sparkle

// This view model class publishes when new updates can be checked by the user
final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

// This is the view for the Check for Updates menu item
// Note this intermediate view is necessary for the disabled state on the menu item to work properly before Monterey.
// See https://stackoverflow.com/questions/68553092/menu-not-updating-swiftui-bug for more info
struct CheckForUpdatesView: View {
    @ObservedObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel
    private let updater: SPUUpdater
    
    init(updater: SPUUpdater) {
        self.updater = updater
        
        // Create our view model for our CheckForUpdatesView
        self.checkForUpdatesViewModel = CheckForUpdatesViewModel(updater: updater)
    }
    
    var body: some View {
        Button("Check for Updates…", action: updater.checkForUpdates)
            .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
    }
}

@main
struct macaiApp: App {
    @AppStorage("gptModel") var gptModel: String = "gpt-3.5-turbo"
    @StateObject private var store = ChatStore()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) var systemColorScheme
    
    private let updaterController: SPUStandardUpdaterController
    
    init() {
        // If you want to start the updater manually, pass false to startingUpdater and call .startUpdater() later
        // This is where you can also pass an updater delegate if you need one
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(chats: $store.chats) {
                saveState()
            }
            .onAppear {
                ChatStore.load { result in
                    
                    switch result {
                        
                    case .failure(let error):
                        print("error")
                        // Remove data from store
//                        store.chats = []
//                        saveState()
//                        fatalError(error.localizedDescription)
                        
                    case .success(let chats):
                        
                        store.chats = chats
                        
                    }
                    
                }
                
            }


        }
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }
        
        
        Settings {
            PreferencesView()
        }
    }
    
    func saveState() {
        ChatStore.save(chats: store.chats) { result in
            print("State saved");
            if case .failure(let error) = result {
                fatalError(error.localizedDescription)
            }
        }
    }
}
