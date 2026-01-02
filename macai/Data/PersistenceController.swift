//
//  PersistenceController.swift
//  macai
//
//  Shared Core Data + CloudKit stack for macOS and iOS.
//

import CloudKit
import CoreData
import Foundation
#if os(macOS)
import Security
#endif
import SQLite3

final class PersistenceController {
    static let shared = PersistenceController()
    static let iCloudSyncEnabledKey = "iCloudSyncEnabled"

    let container: NSPersistentContainer
    let isCloudKitEnabled: Bool
    private let migrator = ProgrammaticMigrator(containerName: "macaiDataModel")

    init(inMemory: Bool = false) {
        let iCloudEnabled = UserDefaults.standard.bool(forKey: PersistenceController.iCloudSyncEnabledKey)
        let containerIdentifier = AppConstants.cloudKitContainerIdentifier
        let hasCloudKitEntitlement = Self.hasCloudKitEntitlement(for: containerIdentifier)

        // Ensure CloudKit is only enabled if:
        // 1. User enabled it in settings
        // 2. Not in memory (previews/tests)
        // 3. Not disabled via compile-time flag
        // 4. CloudKit container identifier is actually present in Info.plist
        // 5. App entitlements include the container (prevents CKContainer crash on iOS)
        #if DISABLE_ICLOUD
        let canEnableCloudKit = false
        #else
        let canEnableCloudKit = iCloudEnabled && !inMemory && hasCloudKitEntitlement
        #endif

        self.isCloudKitEnabled = canEnableCloudKit

        if iCloudEnabled && !canEnableCloudKit {
            UserDefaults.standard.set(false, forKey: PersistenceController.iCloudSyncEnabledKey)
            print("CloudKit entitlements missing or invalid; disabling iCloud sync.")
        }

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
            if let containerIdentifier {
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
                self.container.viewContext.automaticallyMergesChangesFromParent = true
                self.container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
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

        print("Persistent stores loaded, scheduling WAL checkpoint...")

        // Perform WAL checkpoint on background thread to avoid blocking app launch
        // For large databases (>100MB), this can take seconds
        DispatchQueue.global(qos: .utility).async { [weak container] in
            self.performWALCheckpoint(container: container)
        }

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

    private static func hasCloudKitEntitlement(for containerIdentifier: String?) -> Bool {
        guard let containerIdentifier else { return false }

        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil) else { return false }

        let entitlementKey = "com.apple.developer.icloud-container-identifiers" as CFString
        let entitlements = SecTaskCopyValueForEntitlement(task, entitlementKey, nil)

        if let identifiers = entitlements as? [String] {
            return identifiers.contains(containerIdentifier) || identifiers.contains("*")
        }
        if let identifier = entitlements as? String {
            return identifier == containerIdentifier || identifier == "*"
        }
        return false
        #else
        guard let profileURL = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") else {
            // If there is no embedded provisioning profile, we are likely running in a
            // production environment (App Store / TestFlight) where entitlements are
            // verified by the OS. In this case, we assume we have the entitlement
            // to avoid false negatives.
            return true
        }

        guard let profileData = try? Data(contentsOf: profileURL) else {
            // If we can't read the profile, assume valid to avoid false negatives
            print("WARNING: Could not read embedded provisioning profile data. Assuming entitlements are valid.")
            return true
        }

        let profileString = String(data: profileData, encoding: .ascii)
            ?? String(data: profileData, encoding: .utf8)

        guard let content = profileString,
              let plistStart = content.range(of: "<plist"),
              let plistEnd = content.range(of: "</plist>") else {
            // Parsing failed (binary profile? wrong encoding?) -> assume valid
            print("WARNING: Could not parse embedded provisioning profile plist. Assuming entitlements are valid.")
            return true
        }

        let plistString = String(content[plistStart.lowerBound..<plistEnd.upperBound])
        guard let plistData = plistString.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any] else {
            // Plist breakdown failed -> assume valid
            print("WARNING: Could not deserialize entitlements from profile. Assuming entitlements are valid.")
            return true
        }

        let value = entitlements["com.apple.developer.icloud-container-identifiers"]
        if let identifiers = value as? [String] {
            return identifiers.contains(containerIdentifier) || identifiers.contains("*")
        }
        if let identifier = value as? String {
            return identifier == containerIdentifier || identifier == "*"
        }
        return false
        #endif
    }
}
