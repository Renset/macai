//
//  macaiApp.swift
//  macai
//
//  Created by Renat Notfullin on 11.03.2023.
//

import Sparkle
import SwiftUI
import UserNotifications

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

class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "macaiDataModel")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
    }
}

@main
struct macaiApp: App {
    @AppStorage("gptModel") var gptModel: String = AppConstants.defaultPrimaryModel
    @AppStorage("preferredColorScheme") private var preferredColorSchemeRaw: Int = 0
    @StateObject private var store = ChatStore(persistenceController: PersistenceController.shared)

    var preferredColorScheme: ColorScheme? {
        switch preferredColorSchemeRaw {
        case 1: return .light
        case 2: return .dark
        default: return nil
        }
    }
    @Environment(\.scenePhase) private var scenePhase

    private let updaterController: SPUStandardUpdaterController
    let persistenceController = PersistenceController.shared

    init() {
        ValueTransformer.setValueTransformer(
            RequestMessagesTransformer(),
            forName: RequestMessagesTransformer.name
        )

        NotificationPresenter.shared.configure()
        NotificationPresenter.shared.onAuthorizationGranted = {
            DatabasePatcher.deliverPendingGeminiMigrationNotificationIfNeeded()
        }
        NotificationPresenter.shared.requestAuthorizationIfNeeded()

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        DatabasePatcher.applyPatches(context: persistenceController.container.viewContext)
        DatabasePatcher.migrateExistingConfiguration(context: persistenceController.container.viewContext)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .preferredColorScheme(preferredColorScheme)

        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                if UserDefaults.standard.bool(forKey: "autoCheckForUpdates") {
                    updaterController.updater.checkForUpdatesInBackground()
                }
            }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }

            CommandMenu("Chat") {
                Button("Find in Chat") {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("ActivateSearch"),
                        object: nil
                    )
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("Retry Last Message") {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("RetryMessage"),
                        object: nil
                    )
                }
                .keyboardShortcut("r", modifiers: .command)
            }

            CommandGroup(replacing: .newItem) {
                Button("New Chat") {
                    NotificationCenter.default.post(
                        name: AppConstants.newChatNotification,
                        object: nil,
                        userInfo: ["windowId": NSApp.keyWindow?.windowNumber ?? 0]
                    )
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("New Window") {
                    NSApplication.shared.sendAction(Selector(("newWindowForTab:")), to: nil, from: nil)
                }
                .keyboardShortcut("n", modifiers: [.command, .option])
            }

            CommandGroup(after: .sidebar) {
                Button("Toggle Sidebar") {
                    NSApp.keyWindow?.firstResponder?.tryToPerform(
                        #selector(NSSplitViewController.toggleSidebar(_:)),
                        with: nil
                    )
                }
                .keyboardShortcut("s", modifiers: [.command])
            }
        }

        Settings {
            PreferencesView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .preferredColorScheme(preferredColorScheme)
        }
    }
}
