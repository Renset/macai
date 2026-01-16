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
    private static let historyTokenKey = "PersistentHistoryToken"
    private static let legacyHistoryTokenKey = "PersistentHistoryTokenKey"
    private static let legacyHistoryTokenKeyV241 = "macai.persistentHistoryToken"
    private static let historyPruneKey = "PersistentHistoryLastPrune"
    private static let historyPruneInterval: TimeInterval = 6 * 60 * 60
    private static let historyPruneWindow: TimeInterval = 7 * 24 * 60 * 60

    let container: NSPersistentContainer
    let isCloudKitEnabled: Bool
    private(set) var isCloudKitActive: Bool = false
    private let migrator = ProgrammaticMigrator(containerName: "macaiDataModel")
    private let historyQueue = DispatchQueue(label: "com.macai.persistentHistory", qos: .utility)
    private var isProcessingHistory = false
    private var hasPendingHistoryProcess = false
    private var historyToken: NSPersistentHistoryToken? = PersistenceController.loadHistoryToken()

    init(inMemory: Bool = false) {
        let iCloudEnabled = UserDefaults.standard.bool(forKey: PersistenceController.iCloudSyncEnabledKey)
        
        // Ensure CloudKit is only enabled if:
        // 1. User enabled it in settings
        // 2. Not in memory (previews/tests)
        // 3. Not disabled via compile-time flag
        // 4. CloudKit container identifier is actually present in Info.plist
        #if DISABLE_ICLOUD
        let canEnableCloudKit = false
        #else
        let canEnableCloudKit = iCloudEnabled && !inMemory && AppConstants.cloudKitContainerIdentifier != nil
        #endif
        
        self.isCloudKitEnabled = canEnableCloudKit

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
            // Keep history tracking consistent to avoid Core Data forcing read-only on reopen.
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        }

        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }

        // Configure for CloudKit if enabled
        if isCloudKitEnabled, let description = container.persistentStoreDescriptions.first {
            if let containerIdentifier = AppConstants.cloudKitContainerIdentifier {
                description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                    containerIdentifier: containerIdentifier
                )
            }

            // Enable remote change notifications for CloudKit sync.
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        }

        // Programmatic migration (export/import) only
        let migrationState = migrator.prepareIfNeeded()

        print("Starting to load persistent stores...")
        let startTime = Date()
        let semaphore = DispatchSemaphore(value: 0)
        var loadError: Error?
        var storeLoaded = false

        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            let elapsed = Date().timeIntervalSince(startTime)
            if let error = error {
                print("Failed to load persistent store after \(elapsed)s: \(error)")
                loadError = error
            } else {
                print("Successfully loaded persistent store in \(elapsed)s: \(storeDescription.url?.lastPathComponent ?? "unknown")")
                
                // Configure view context only after store is loaded
                self.container.viewContext.automaticallyMergesChangesFromParent = true
                self.container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
                self.isCloudKitActive = self.isCloudKitEnabled
                storeLoaded = true
                CoreDataBackupManager.clearMigrationRetrySkipBackupFlag()
            }
            semaphore.signal()
        })

        // Wait for persistent stores to load (with timeout)
        _ = semaphore.wait(timeout: .now() + 10)

        // Handle any store loading errors
        if let error = loadError {
            if isCloudKitEnabled {
                // Avoid destructive recovery when iCloud is enabled; report error in Sync UI instead.
                CloudSyncManager.shared.reportStoreLoadError(error)
                print("Skipping destructive recovery because iCloud sync is enabled.")

                // Fallback: try to load the same store without CloudKit so local data stays available.
                if container.persistentStoreCoordinator.persistentStores.isEmpty {
                    for description in container.persistentStoreDescriptions {
                        description.cloudKitContainerOptions = nil
                    }

                    let fallbackSemaphore = DispatchSemaphore(value: 0)
                    var fallbackError: Error?
                    container.loadPersistentStores { storeDescription, error in
                        if let error = error {
                            fallbackError = error
                            print("Fallback store load failed: \(error)")
                        } else {
                            print("Loaded local fallback store: \(storeDescription.url?.lastPathComponent ?? "unknown")")
                            self.container.viewContext.automaticallyMergesChangesFromParent = true
                            self.container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
                            self.isCloudKitActive = false
                            storeLoaded = true
                        }
                        fallbackSemaphore.signal()
                    }
                    _ = fallbackSemaphore.wait(timeout: .now() + 10)

                    if fallbackError != nil {
                        return
                    }
                } else {
                    return
                }
            } else if !migrator.recoverFromLoadFailure(container: container) {
                migrator.handleStoreLoadError(error, state: migrationState)
            } else {
                loadError = nil
            }
        }

        guard storeLoaded else {
            return
        }

        // Import exported data if we have it (migration scenario)
        migrator.importIfNeeded(state: migrationState, into: container)

        print("Initialization complete")

        // Initialize CloudSyncManager if CloudKit is enabled
        if isCloudKitActive, let cloudKitContainer = container as? NSPersistentCloudKitContainer {
            CloudSyncManager.shared.configure(with: cloudKitContainer)
        }

        // Apply database patches and migrations after store is loaded
        DatabasePatcher.initializeDatabaseIfNeeded(context: container.viewContext, persistence: self)
        DatabasePatcher.applyPatches(context: container.viewContext, persistence: self)
        DatabasePatcher.migrateExistingConfiguration(context: container.viewContext, persistence: self)
        TokenManager.reconcileTokensWithCurrentSyncSetting()

        processRemoteChanges(reason: "startup")
        prunePersistentHistoryIfNeeded(reason: "startup")
    }

    func getMetadata(forKey key: String) -> Any? {
        guard let store = container.persistentStoreCoordinator.persistentStores.first else {
            return nil
        }
        let metadata = container.persistentStoreCoordinator.metadata(for: store)
        return metadata[key]
    }

    func setMetadata(value: Any?, forKey key: String) {
        guard let store = container.persistentStoreCoordinator.persistentStores.first else {
            return
        }
        guard store.isReadOnly == false else {
            print("Skipping metadata update for \(key): persistent store is read-only.")
            return
        }
        var metadata = container.persistentStoreCoordinator.metadata(for: store)
        metadata[key] = value
        container.persistentStoreCoordinator.setMetadata(metadata, for: store)
        
        // Save the context to ensure metadata is persisted to disk if it was updated
        if container.viewContext.hasChanges {
            try? container.viewContext.save()
        }
    }

    static func requiresRestart(forNewSyncState newState: Bool) -> Bool {
        let currentState = UserDefaults.standard.bool(forKey: iCloudSyncEnabledKey)
        return currentState != newState
    }

    func processRemoteChanges(reason: String = "remote-change") {
        historyQueue.async { [weak self] in
            guard let self else { return }
            guard !self.container.persistentStoreCoordinator.persistentStores.isEmpty else { return }
            self.hasPendingHistoryProcess = true
            guard !self.isProcessingHistory else { return }
            self.isProcessingHistory = true
            while self.hasPendingHistoryProcess {
                self.hasPendingHistoryProcess = false
                self.processPersistentHistory(reason: reason)
            }
            self.isProcessingHistory = false
        }
    }

    func prunePersistentHistoryIfNeeded(reason: String = "periodic") {
        historyQueue.async { [weak self] in
            guard let self else { return }
            guard !self.container.persistentStoreCoordinator.persistentStores.isEmpty else { return }
            guard self.historyToken != nil else { return }
            let lastPrune = UserDefaults.standard.object(forKey: Self.historyPruneKey) as? Date ?? .distantPast
            let now = Date()
            guard now.timeIntervalSince(lastPrune) >= Self.historyPruneInterval else { return }
            let cutoffDate = now.addingTimeInterval(-Self.historyPruneWindow)
            self.prunePersistentHistory(before: cutoffDate, reason: reason)
            UserDefaults.standard.set(now, forKey: Self.historyPruneKey)
        }
    }

    private func processPersistentHistory(reason: String) {
        let backgroundContext = container.newBackgroundContext()
        backgroundContext.name = "PersistentHistoryProcessor"
        backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        backgroundContext.undoManager = nil

        var transactions: [NSPersistentHistoryTransaction] = []
        backgroundContext.performAndWait {
            let request = NSPersistentHistoryChangeRequest.fetchHistory(after: historyToken)
            request.resultType = .transactionsAndChanges
            do {
                let result = try backgroundContext.execute(request) as? NSPersistentHistoryResult
                transactions = result?.result as? [NSPersistentHistoryTransaction] ?? []
            } catch {
                print("Persistent history fetch failed (\(reason)): \(error)")
                let nsError = error as NSError
                if nsError.domain == NSCocoaErrorDomain, nsError.code == NSPersistentHistoryTokenExpiredError {
                    historyToken = nil
                    PersistenceController.storeHistoryToken(nil)
                }
            }
        }

        guard !transactions.isEmpty else { return }

        let viewContext = container.viewContext
        viewContext.performAndWait {
            for transaction in transactions {
                viewContext.mergeChanges(fromContextDidSave: transaction.objectIDNotification())
            }
        }

        if let newToken = transactions.last?.token {
            historyToken = newToken
            PersistenceController.storeHistoryToken(newToken)
        }
    }

    private func prunePersistentHistory(before date: Date, reason: String) {
        let backgroundContext = container.newBackgroundContext()
        backgroundContext.name = "PersistentHistoryPruner"
        backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        backgroundContext.undoManager = nil
        backgroundContext.perform {
            let request = NSPersistentHistoryChangeRequest.deleteHistory(before: date)
            do {
                try backgroundContext.execute(request)
                print("Persistent history pruned (\(reason)) before \(date).")
            } catch {
                print("Persistent history prune failed (\(reason)): \(error)")
            }
        }
    }

    private static func loadHistoryToken() -> NSPersistentHistoryToken? {
        if let data = UserDefaults.standard.data(forKey: historyTokenKey) {
            return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSPersistentHistoryToken.self, from: data)
        }
        if let data = UserDefaults.standard.data(forKey: legacyHistoryTokenKey) {
            return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSPersistentHistoryToken.self, from: data)
        }
        if let data = UserDefaults.standard.data(forKey: legacyHistoryTokenKeyV241) {
            return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSPersistentHistoryToken.self, from: data)
        }
        return nil
    }

    private static func storeHistoryToken(_ token: NSPersistentHistoryToken?) {
        guard let token else {
            UserDefaults.standard.removeObject(forKey: historyTokenKey)
            UserDefaults.standard.removeObject(forKey: legacyHistoryTokenKey)
            UserDefaults.standard.removeObject(forKey: legacyHistoryTokenKeyV241)
            return
        }
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
            UserDefaults.standard.set(data, forKey: historyTokenKey)
            UserDefaults.standard.removeObject(forKey: legacyHistoryTokenKey)
            UserDefaults.standard.removeObject(forKey: legacyHistoryTokenKeyV241)
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

        // Enable badge for existing users who were authorized without .badge
        NotificationPresenter.shared.enableBadgeForExistingUsers()

        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

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

                Button("Clear Chat") {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("ClearChat"),
                        object: nil
                    )
                }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])

                Button("Retry Last Message") {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("RetryMessage"),
                        object: nil
                    )
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Stop Response") {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("StopInference"),
                        object: nil
                    )
                }
                .keyboardShortcut(".", modifiers: .command)
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
