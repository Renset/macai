//
//  macaiApp.swift
//  macai
//
//  Created by Renat Notfullin on 11.03.2023.
//

import AppKit
import CloudKit
import CoreData
import Sparkle
import SQLite3
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
    static let iCloudSyncEnabledKey = "iCloudSyncEnabled"

    let container: NSPersistentContainer
    let isCloudKitEnabled: Bool
    private let migrator = ProgrammaticMigrator(containerName: "macaiDataModel")

    init(inMemory: Bool = false) {
        let iCloudEnabled = UserDefaults.standard.bool(forKey: PersistenceController.iCloudSyncEnabledKey)
        self.isCloudKitEnabled = iCloudEnabled && !inMemory

        if isCloudKitEnabled {
            container = NSPersistentCloudKitContainer(name: "macaiDataModel")
        } else {
            container = NSPersistentContainer(name: "macaiDataModel")
        }

        // We handle migration manually by exporting/importing data, so no Core Data migration needed
        // Set to true for any future lightweight migrations that Core Data can handle automatically
        for description in container.persistentStoreDescriptions {
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
        }

        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }

        // Configure for CloudKit if enabled
        if isCloudKitEnabled, let description = container.persistentStoreDescriptions.first {
            description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                containerIdentifier: "iCloud.notfullin.com.macai"
            )

            // Enable history tracking for CloudKit sync
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        }

        // Programmatic migration (export/import) only
        let migrationState = migrator.prepareIfNeeded()

        print("Starting to load persistent stores...")
        let startTime = Date()
        var migrationError: Error?

        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            let elapsed = Date().timeIntervalSince(startTime)
            if let error = error {
                print("Failed to load persistent store after \(elapsed)s: \(error)")
                migrationError = error
            } else {
                print("Successfully loaded persistent store in \(elapsed)s: \(storeDescription.url?.lastPathComponent ?? "unknown")")
            }
        })

        // Handle any store loading errors
        if let error = migrationError {
            migrator.handleStoreLoadError(error, state: migrationState)
        }

        // Import exported data if we have it (migration scenario)
        migrator.importIfNeeded(state: migrationState, into: container)

        print("Persistent stores loaded, scheduling WAL checkpoint...")

        // Perform WAL checkpoint on background thread to avoid blocking app launch
        // For large databases (>100MB), this can take seconds
        DispatchQueue.global(qos: .utility).async { [weak container] in
            self.performWALCheckpoint(container: container)
        }

        print("Migration complete")

        // Configure view context
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        // Initialize CloudSyncManager if CloudKit is enabled
        if isCloudKitEnabled, let cloudKitContainer = container as? NSPersistentCloudKitContainer {
            CloudSyncManager.shared.configure(with: cloudKitContainer)
        }
    }

    private func performWALCheckpoint(container: NSPersistentContainer?) {
        guard let container = container else {
            print("WAL checkpoint skipped: container deallocated")
            return
        }
        
        let storeCoordinator = container.persistentStoreCoordinator
        guard let store = storeCoordinator.persistentStores.first,
              let storeURL = store.url else {
            return
        }

        // Perform WAL checkpoint using raw SQL
        var db: OpaquePointer?

        if sqlite3_open(storeURL.path, &db) == SQLITE_OK {
            var errMsg: UnsafeMutablePointer<CChar>?
            let result = sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, &errMsg)
            if result != SQLITE_OK {
                if let errMsg = errMsg {
                    print("WAL checkpoint failed: \(String(cString: errMsg))")
                    sqlite3_free(errMsg)
                }
            } else {
                print("WAL checkpoint completed successfully")
            }
            sqlite3_close(db)
        }
    }

    static func requiresRestart(forNewSyncState newState: Bool) -> Bool {
        let currentState = UserDefaults.standard.bool(forKey: iCloudSyncEnabledKey)
        return currentState != newState
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
        TokenManager.reconcileTokensWithCurrentSyncSetting()
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
