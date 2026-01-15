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
    private let migrator = ProgrammaticMigrator(containerName: "macaiDataModel")
    private var contextMergeObserver: NSObjectProtocol?
    private var remoteChangeObserver: NSObjectProtocol?
    private var remoteChangeWorkItem: DispatchWorkItem?
    private var refreshWorkItem: DispatchWorkItem?
    private let refreshEntityNames: Set<String> = ["APIServiceEntity", "PersonaEntity"]
    private let draftEntityName = "ChatEntity"
    private let draftPropertyNames: Set<String> = ["draftMessage", "draftImageIDs", "draftFileIDs"]
    private let historyTokenKey = "macai.persistentHistoryToken"

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

        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            let elapsed = Date().timeIntervalSince(startTime)
            if let error = error {
                print("Failed to load persistent store after \(elapsed)s: \(error)")
                loadError = error
            } else {
                print("Successfully loaded persistent store in \(elapsed)s: \(storeDescription.url?.lastPathComponent ?? "unknown")")
                
                // Configure view context only after store is loaded
                self.container.viewContext.automaticallyMergesChangesFromParent = false
                self.container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
                self.configureContextMerging()
                self.configureRemoteChangeHandling()
                CoreDataBackupManager.clearMigrationRetrySkipBackupFlag()
            }
            semaphore.signal()
        })

        // Wait for persistent stores to load (with timeout)
        _ = semaphore.wait(timeout: .now() + 10)

        // Handle any store loading errors
        if let error = loadError {
            if !migrator.recoverFromLoadFailure(container: container) {
                migrator.handleStoreLoadError(error, state: migrationState)
            } else {
                loadError = nil
            }
        }

        // Import exported data if we have it (migration scenario)
        migrator.importIfNeeded(state: migrationState, into: container)

        print("Initialization complete")

        // Initialize CloudSyncManager if CloudKit is enabled
        if isCloudKitEnabled, let cloudKitContainer = container as? NSPersistentCloudKitContainer {
            CloudSyncManager.shared.configure(with: cloudKitContainer)
        }

        // Apply database patches and migrations after store is loaded
        DatabasePatcher.initializeDatabaseIfNeeded(context: container.viewContext, persistence: self)
        DatabasePatcher.applyPatches(context: container.viewContext, persistence: self)
        DatabasePatcher.migrateExistingConfiguration(context: container.viewContext, persistence: self)
        TokenManager.reconcileTokensWithCurrentSyncSetting()
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

    private func configureContextMerging() {
        if contextMergeObserver != nil {
            return
        }

        contextMergeObserver = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let self,
                  let context = notification.object as? NSManagedObjectContext else {
                return
            }

            let viewContext = self.container.viewContext
            guard context !== viewContext else { return }

            if context.transactionAuthor == AppConstants.draftTransactionAuthor {
                return
            }

            let refreshObjectIDs = self.refreshObjectIDs(in: notification)
            let filteredUserInfo = self.filteredRemoteSaveUserInfo(from: notification)
            viewContext.perform {
                if let userInfo = filteredUserInfo {
                    NSManagedObjectContext.mergeChanges(fromRemoteContextSave: userInfo, into: [viewContext])
                }

                if !refreshObjectIDs.isEmpty {
                    self.scheduleViewContextRefresh(objectIDs: refreshObjectIDs)
                }
            }
        }
    }

    private func configureRemoteChangeHandling() {
        if remoteChangeObserver != nil {
            return
        }

        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator,
            queue: nil
        ) { [weak self] _ in
            self?.scheduleRemoteChangeProcessing()
        }
    }

    private func refreshObjectIDs(in notification: Notification) -> Set<NSManagedObjectID> {
        let keys: [String] = [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey]
        var objectIDs = Set<NSManagedObjectID>()
        for key in keys {
            guard let objects = notification.userInfo?[key] as? Set<NSManagedObject> else { continue }
            for object in objects {
                guard let name = object.entity.name, refreshEntityNames.contains(name) else { continue }
                objectIDs.insert(object.objectID)
            }
        }
        return objectIDs
    }

    private func scheduleRemoteChangeProcessing() {
        remoteChangeWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.processRemoteChanges()
        }
        remoteChangeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    private func processRemoteChanges() {
        let taskContext = container.newBackgroundContext()
        taskContext.perform { [weak self] in
            guard let self else { return }
            let request = NSPersistentHistoryChangeRequest.fetchHistory(after: self.loadHistoryToken())
            request.resultType = .transactionsAndChanges
            let historyFetchRequest: NSFetchRequest<NSFetchRequestResult>
            if let baseRequest = NSPersistentHistoryTransaction.fetchRequest {
                historyFetchRequest = baseRequest
            } else {
                historyFetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "NSPersistentHistoryTransaction")
            }
            historyFetchRequest.predicate = NSPredicate(
                format: "author != %@",
                AppConstants.draftTransactionAuthor
            )
            request.fetchRequest = historyFetchRequest

            let result = try? taskContext.execute(request) as? NSPersistentHistoryResult
            guard let transactions = result?.result as? [NSPersistentHistoryTransaction],
                  transactions.isEmpty == false else {
                return
            }

            let viewContext = self.container.viewContext
            let lastToken = transactions.last?.token
            viewContext.perform {
                for transaction in transactions {
                    guard let changes = transaction.changes, !changes.isEmpty else { continue }
                    var inserted = Set<NSManagedObjectID>()
                    var updated = Set<NSManagedObjectID>()
                    var deleted = Set<NSManagedObjectID>()

                    for change in changes where self.shouldMergeRemoteChange(change) {
                        switch change.changeType {
                        case .insert:
                            inserted.insert(change.changedObjectID)
                        case .update:
                            updated.insert(change.changedObjectID)
                        case .delete:
                            deleted.insert(change.changedObjectID)
                        @unknown default:
                            break
                        }
                    }

                    guard !(inserted.isEmpty && updated.isEmpty && deleted.isEmpty) else { continue }
                    let userInfo: [AnyHashable: Any] = [
                        NSInsertedObjectsKey: inserted,
                        NSUpdatedObjectsKey: updated,
                        NSDeletedObjectsKey: deleted
                    ]

                    NSManagedObjectContext.mergeChanges(
                        fromRemoteContextSave: userInfo,
                        into: [viewContext]
                    )
                }

                if let lastToken {
                    self.storeHistoryToken(lastToken)
                }
            }

            if let lastToken {
                let deleteRequest = NSPersistentHistoryChangeRequest.deleteHistory(before: lastToken)
                _ = try? taskContext.execute(deleteRequest)
            }
        }
    }

    private func shouldMergeRemoteChange(_ change: NSPersistentHistoryChange) -> Bool {
        guard change.changeType == .update else { return true }
        guard change.changedObjectID.entity.name == draftEntityName else { return true }
        guard let updatedProperties = change.updatedProperties else { return true }
        let propertyNames = Set(updatedProperties.map { $0.name })
        guard propertyNames.isEmpty == false else { return true }
        return !propertyNames.isSubset(of: draftPropertyNames)
    }

    private func filteredRemoteSaveUserInfo(from notification: Notification) -> [AnyHashable: Any]? {
        guard let userInfo = notification.userInfo else { return nil }
        let inserted = (userInfo[NSInsertedObjectsKey] as? Set<NSManagedObject>) ?? []
        let updated = (userInfo[NSUpdatedObjectsKey] as? Set<NSManagedObject>) ?? []
        let deleted = (userInfo[NSDeletedObjectsKey] as? Set<NSManagedObject>) ?? []

        let filteredUpdated = updated.filter { object in
            guard object.entity.name == draftEntityName else { return true }
            let changedKeys = Set(object.changedValuesForCurrentEvent().keys)
            guard changedKeys.isEmpty == false else { return true }
            return !changedKeys.isSubset(of: draftPropertyNames)
        }

        let insertedIDs = Set(inserted.map(\.objectID))
        let updatedIDs = Set(filteredUpdated.map(\.objectID))
        let deletedIDs = Set(deleted.map(\.objectID))

        if insertedIDs.isEmpty && updatedIDs.isEmpty && deletedIDs.isEmpty {
            return nil
        }

        return [
            NSInsertedObjectsKey: insertedIDs,
            NSUpdatedObjectsKey: updatedIDs,
            NSDeletedObjectsKey: deletedIDs
        ]
    }

    private func scheduleViewContextRefresh(objectIDs: Set<NSManagedObjectID>) {
        refreshWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let viewContext = self.container.viewContext
            viewContext.perform {
                guard objectIDs.isEmpty == false else { return }
                do {
                    try viewContext.setQueryGenerationFrom(.current)
                }
                catch {
                    print("Failed to update query generation after refresh: \(error)")
                }
                let updatedIDs = Set(viewContext.updatedObjects.map(\.objectID))
                for objectID in objectIDs {
                    guard updatedIDs.contains(objectID) == false,
                          let object = try? viewContext.existingObject(with: objectID),
                          object.isDeleted == false else {
                        continue
                    }
                    viewContext.refresh(object, mergeChanges: true)
                }
            }
        }
        refreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    private func loadHistoryToken() -> NSPersistentHistoryToken? {
        guard let data = UserDefaults.standard.data(forKey: historyTokenKey) else {
            return nil
        }
        return try? NSKeyedUnarchiver.unarchivedObject(
            ofClass: NSPersistentHistoryToken.self,
            from: data
        )
    }

    private func storeHistoryToken(_ token: NSPersistentHistoryToken) {
        guard let data = try? NSKeyedArchiver.archivedData(
            withRootObject: token,
            requiringSecureCoding: true
        ) else {
            return
        }
        UserDefaults.standard.set(data, forKey: historyTokenKey)
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
