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

    init(inMemory: Bool = false) {
        let iCloudEnabled = UserDefaults.standard.bool(forKey: PersistenceController.iCloudSyncEnabledKey)
        self.isCloudKitEnabled = iCloudEnabled && !inMemory

        if isCloudKitEnabled {
            container = NSPersistentCloudKitContainer(name: "macaiDataModel")
        } else {
            container = NSPersistentContainer(name: "macaiDataModel")
        }

        for description in container.persistentStoreDescriptions {
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = false
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

        // One-time local backup before migrating to Core Data model v3
        CoreDataBackupManager.backupBeforeV3IfNeeded(
            containerName: "macaiDataModel",
            isCloudKitEnabled: isCloudKitEnabled
        )

        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error {
                print("Failed to load persistent store: \(error)")
            }
        })

        // Configure view context
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        // Initialize CloudSyncManager if CloudKit is enabled
        if isCloudKitEnabled, let cloudKitContainer = container as? NSPersistentCloudKitContainer {
            CloudSyncManager.shared.configure(with: cloudKitContainer)
        }

    }

    static func requiresRestart(forNewSyncState newState: Bool) -> Bool {
        let currentState = UserDefaults.standard.bool(forKey: iCloudSyncEnabledKey)
        return currentState != newState
    }
}

// MARK: - Core Data backup helper
private enum CoreDataBackupManager {
    private static let backupCompletedKey = "CoreDataBackupBeforeV3Completed"
    private static let backupNoticeShownKey = "CoreDataBackupBeforeV3NoticeShown"
    private static let targetModelVersionName = "macaiDataModel 3"

    static func backupBeforeV3IfNeeded(containerName: String, isCloudKitEnabled: Bool) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: backupCompletedKey) else { return }

        guard let storeBaseURL = defaultStoreURL(for: containerName) else { return }
        let sqliteURL = storeBaseURL.appendingPathExtension("sqlite")
        guard FileManager.default.fileExists(atPath: sqliteURL.path) else {
            defaults.set(true, forKey: backupCompletedKey) // nothing to back up yet
            return
        }

        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backupsFolder = backupsDirectoryURL()
            .appendingPathComponent("Before-\(targetModelVersionName)-\(timestamp)", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: backupsFolder, withIntermediateDirectories: true)
            try copyStoreFiles(from: storeBaseURL, to: backupsFolder)
            defaults.set(true, forKey: backupCompletedKey)
            defaults.set(backupsFolder.path, forKey: "CoreDataBackupBeforeV3Path")
            defaults.set(false, forKey: backupNoticeShownKey)
            print("Backup before v3 created at: \(backupsFolder.path)")
            NotificationPresenter.shared.scheduleNotification(
                identifier: "CoreDataBackupCompleted",
                title: "Database updated",
                body: "We created a local backup before migrating to \(targetModelVersionName). Location: \(backupsFolder.path)"
            )
        }
        catch {
            print("Backup before v3 failed: \(error)")
        }
    }

    /// Returns the Backups directory URL, matching DatabaseBackupManager in TabBackupRestoreView
    static func backupsDirectoryURL() -> URL {
        let base = NSPersistentContainer.defaultDirectoryURL()
        let bundleID = Bundle.main.bundleIdentifier ?? "macai"
        return base
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Backups", isDirectory: true)
    }

    private static func defaultStoreURL(for containerName: String) -> URL? {
        // Core Data stores at: <Application Support>/<containerName>.sqlite
        let base = NSPersistentContainer.defaultDirectoryURL()
        return base.appendingPathComponent(containerName)
    }

    private static func copyStoreFiles(from baseURL: URL, to backupFolder: URL) throws {
        let fm = FileManager.default
        for ext in ["sqlite", "sqlite-wal", "sqlite-shm"] {
            let source = baseURL.appendingPathExtension(ext)
            guard fm.fileExists(atPath: source.path) else { continue }
            let destination = backupFolder.appendingPathComponent(source.lastPathComponent)
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.copyItem(at: source, to: destination)
        }
    }

    private static func presentPreMigrationAlert(storeURL: URL) {
        // Only present if an AppKit application is running; otherwise log and continue.
        guard NSApp != nil else {
            print("Skipping pre-migration alert (NSApp not initialized). Backup will proceed.")
            return
        }

        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Preparing database upgrade"
            alert.informativeText = """
We will back up your chat database before migrating to the new Core Data model (v3).
Backup location: \(storeURL.deletingLastPathComponent().appendingPathComponent("Backups").path)
This happens once and keeps your data safe in case of issues.
"""
            alert.addButton(withTitle: "Proceed")
            alert.runModal()
        }
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
