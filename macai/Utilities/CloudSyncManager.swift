//
//  CloudSyncManager.swift
//  macai
//
//  Created by Renat Notfullin on 25.11.2025.
//

import CoreData
import CloudKit
import Combine
import os.log

enum CloudSyncStatus: Equatable {
    case inactive
    case syncing
    case synced
    case error(String)

    var displayText: String {
        switch self {
        case .inactive:
            return "Sync disabled"
        case .syncing:
            return "Syncing..."
        case .synced:
            return "Synced"
        case .error(let message):
            return "Error: \(message)"
        }
    }

    var indicatorColor: String {
        switch self {
        case .inactive:
            return "gray"
        case .syncing:
            return "blue"
        case .synced:
            return "green"
        case .error:
            return "red"
        }
    }
}

class CloudSyncManager: ObservableObject {
    static let shared = CloudSyncManager()

    @Published private(set) var syncStatus: CloudSyncStatus = .inactive
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var syncLogs: [SyncLogEntry] = []

    private var eventSubscription: AnyCancellable?
    private var container: NSPersistentCloudKitContainer?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "macai", category: "CloudSync")
    private let cloudContainerIdentifier = AppConstants.cloudKitContainerIdentifier

    struct SyncLogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let type: String
        let message: String
        let isError: Bool

        var formattedTimestamp: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            return formatter.string(from: timestamp)
        }
    }

    private init() {}

    func configure(with container: NSPersistentCloudKitContainer) {
        self.container = container

        log("CloudSyncManager configured with container", type: "Setup")

        // Subscribe to CloudKit sync events
        eventSubscription = NotificationCenter.default
            .publisher(for: NSPersistentCloudKitContainer.eventChangedNotification, object: container)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleCloudKitEvent(notification)
            }

        // Also subscribe to remote change notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRemoteChange),
            name: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator
        )

        // Check initial iCloud account status
        checkiCloudAccountStatus()

        // Log container info
        logContainerInfo()
    }

    func disable() {
        log("CloudSyncManager disabled", type: "Setup")
        eventSubscription?.cancel()
        eventSubscription = nil
        container = nil
        syncStatus = .inactive
    }

    func clearLogs() {
        syncLogs.removeAll()
    }

    func exportLogsAsText() -> String {
        var output = "=== macai iCloud Sync Debug Log ===\n"
        output += "Export time: \(Date())\n"
        output += "Sync status: \(syncStatus.displayText)\n"
        if let lastSync = lastSyncDate {
            output += "Last sync: \(lastSync)\n"
        }
        output += "\n=== Log Entries ===\n\n"

        for entry in syncLogs {
            let errorMarker = entry.isError ? "[ERROR]" : "[INFO]"
            output += "[\(entry.formattedTimestamp)] \(errorMarker) [\(entry.type)] \(entry.message)\n"
        }

        return output
    }

    /// Deletes the Core Data CloudKit zone in the user's private database.
    /// Leaves local data intact so the user can keep a copy on this device.
    func purgeCloudData(completion: @escaping (Result<Void, Error>) -> Void) {
        guard container != nil else {
            completion(.failure(NSError(domain: "CloudSync", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cloud container unavailable"])))
            return
        }

        // Core Data mirrors into a dedicated zone named below.
        let zoneID = CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName)

        syncStatus = .syncing
        log("Starting CloudKit purge for zone \(zoneID.zoneName)", type: "Setup")

        let ckContainer = cloudContainerIdentifier.map { CKContainer(identifier: $0) } ?? CKContainer.default()
        let privateDB = ckContainer.privateCloudDatabase
        privateDB.delete(withRecordZoneID: zoneID) { [weak self] (_: CKRecordZone.ID?, error: Error?) in
            DispatchQueue.main.async {
                if let error = error {
                    // Treat zone-not-found as success so the UI doesn't block.
                    let nsError = error as NSError
                    if nsError.domain == CKErrorDomain, CKError.Code(rawValue: nsError.code) == .zoneNotFound {
                        self?.log("CloudKit zone already missing; treating as purged", type: "Setup")
                        self?.syncStatus = .inactive
                        completion(.success(()))
                        return
                    }

                    self?.logError(error)
                    self?.syncStatus = .error(self?.simplifyErrorMessage(error) ?? error.localizedDescription)
                    completion(.failure(error))
                } else {
                    self?.log("CloudKit zone deleted successfully", type: "Setup")
                    self?.syncStatus = .inactive
                    completion(.success(()))
                }
            }
        }
    }

    private func log(_ message: String, type: String, isError: Bool = false) {
        let entry = SyncLogEntry(timestamp: Date(), type: type, message: message, isError: isError)
        DispatchQueue.main.async {
            self.syncLogs.append(entry)
            // Keep only last 300 entries (reduced from 500 for memory efficiency)
            // Using suffix is more efficient than removeFirst for large arrays
            if self.syncLogs.count > 300 {
                self.syncLogs = Array(self.syncLogs.suffix(300))
            }
        }

        if isError {
            logger.error("[\(type)] \(message)")
        } else {
            logger.info("[\(type)] \(message)")
        }

        #if DEBUG
        print("[CloudSync] [\(type)] \(message)")
        #endif
    }

    private func logContainerInfo() {
        guard let container = container else { return }

        log("Persistent stores count: \(container.persistentStoreCoordinator.persistentStores.count)", type: "Setup")

        for (index, store) in container.persistentStoreCoordinator.persistentStores.enumerated() {
            log("Store \(index): \(store.url?.lastPathComponent ?? "unknown") - Type: \(store.type)", type: "Setup")

            if let options = store.options {
                for (key, value) in options {
                    log("  Option: \(key) = \(value)", type: "Setup")
                }
            }
        }
    }

    @objc private func handleRemoteChange(_ notification: Notification) {
        log("Remote change notification received", type: "RemoteChange")

        if let storeURL = notification.userInfo?["storeURL"] as? URL {
            log("Store URL: \(storeURL.lastPathComponent)", type: "RemoteChange")
        }

        if let historyToken = notification.userInfo?["historyToken"] {
            log("History token received: \(String(describing: type(of: historyToken)))", type: "RemoteChange")
        }
    }

    private func handleCloudKitEvent(_ notification: Notification) {
        guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else {
            log("Received notification without valid event", type: "Event", isError: true)
            return
        }

        let eventTypeString = eventTypeToString(event.type)
        let storeIdentifier = event.storeIdentifier

        if event.endDate == nil {
            // Event started
            log("Event STARTED: \(eventTypeString) for store: \(storeIdentifier)", type: "Event")
            syncStatus = .syncing
        } else {
            // Event ended
            let duration = event.endDate!.timeIntervalSince(event.startDate)
            let durationStr = String(format: "%.2fs", duration)

            if event.succeeded {
                log("Event COMPLETED: \(eventTypeString) for store: \(storeIdentifier) (duration: \(durationStr))", type: "Event")

                if event.type == .import || event.type == .export {
                    lastSyncDate = Date()
                }
                syncStatus = .synced
            } else {
                log("Event FAILED: \(eventTypeString) for store: \(storeIdentifier) (duration: \(durationStr))", type: "Event", isError: true)

                if let error = event.error {
                    logError(error)
                    syncStatus = .error(simplifyErrorMessage(error))
                }
            }
        }
    }

    private func logError(_ error: Error) {
        log("Error: \(error.localizedDescription)", type: "Error", isError: true)

        let nsError = error as NSError
        log("Error domain: \(nsError.domain), code: \(nsError.code)", type: "Error", isError: true)
        if let containerId = cloudContainerIdentifier {
            log("CloudKit container: \(containerId)", type: "Error", isError: false)
        }

        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            log("Underlying error: \(underlying.domain), code: \(underlying.code)", type: "Error", isError: true)
            log("Underlying description: \(underlying.localizedDescription)", type: "Error", isError: true)
        }

        // Log CloudKit specific errors
        if nsError.domain == CKErrorDomain {
            logCloudKitError(nsError)
        }

        // Log all user info keys for debugging
        for (key, value) in nsError.userInfo {
            if key != NSUnderlyingErrorKey {
                log("Error info [\(key)]: \(value)", type: "Error", isError: true)
            }
        }

        logPartialErrors(from: nsError, label: "Direct")
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            logPartialErrors(from: underlying, label: "Underlying")
        }
    }

    private func logPartialErrors(from error: NSError, label: String) {
        guard let partialErrors = error.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] else {
            return
        }
        log("\(label) partial errors count: \(partialErrors.count)", type: "Error", isError: true)
        for (itemID, itemError) in partialErrors.prefix(20) {
            let nsItemError = itemError as NSError
            var itemDescription = "\(itemID)"
            if let recordID = itemID as? CKRecord.ID {
                itemDescription = "\(recordID.recordName)"
            } else if let zoneID = itemID as? CKRecordZone.ID {
                itemDescription = "\(zoneID.zoneName)"
            }
            log("Partial error for \(itemDescription): \(itemError.localizedDescription)", type: "Error", isError: true)
            log("Partial error domain: \(nsItemError.domain), code: \(nsItemError.code)", type: "Error", isError: true)
        }
        if partialErrors.count > 20 {
            log("... and \(partialErrors.count - 20) more partial errors", type: "Error", isError: true)
        }
    }

    private func logCloudKitError(_ error: NSError) {
        let errorCode = CKError.Code(rawValue: error.code)

        // Log the error code name for clarity
        let errorName = ckErrorCodeName(error.code)
        log("CloudKit error: \(errorName) (code: \(error.code))", type: "CloudKit", isError: true)

        switch errorCode {
        case .internalError: // 1
            log("CloudKit: Internal error - a CloudKit internal error occurred", type: "CloudKit", isError: true)

        case .partialFailure: // 2
            log("CloudKit: Partial failure - some operations in a batch failed", type: "CloudKit", isError: true)
            // This is important - partial failures contain nested errors
            if let partialErrors = error.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error] {
                log("Partial failure contains \(partialErrors.count) individual errors", type: "CloudKit", isError: true)
                for (itemID, itemError) in partialErrors.prefix(20) {
                    let nsItemError = itemError as NSError
                    let itemErrorName = ckErrorCodeName(nsItemError.code)
                    log("  - Item \(itemID): \(itemErrorName) (code: \(nsItemError.code)) - \(itemError.localizedDescription)", type: "CloudKit", isError: true)

                    // Recursively log nested CloudKit errors
                    if nsItemError.domain == CKErrorDomain {
                        logCloudKitErrorDetails(nsItemError, indent: "    ")
                    }
                }
                if partialErrors.count > 20 {
                    log("  ... and \(partialErrors.count - 20) more errors", type: "CloudKit", isError: true)
                }
            }

        case .networkUnavailable: // 3
            log("CloudKit: Network unavailable - check internet connection", type: "CloudKit", isError: true)

        case .networkFailure: // 4
            log("CloudKit: Network failure - request failed due to network issue", type: "CloudKit", isError: true)

        case .badContainer: // 5
            log("CloudKit: Bad container - container identifier may be wrong", type: "CloudKit", isError: true)

        case .serviceUnavailable: // 6
            log("CloudKit: Service unavailable - iCloud service is temporarily down", type: "CloudKit", isError: true)

        case .requestRateLimited: // 7
            log("CloudKit: Request rate limited - too many requests", type: "CloudKit", isError: true)
            if let retryAfter = error.userInfo[CKErrorRetryAfterKey] as? TimeInterval {
                log("Retry after: \(retryAfter) seconds", type: "CloudKit", isError: true)
            }

        case .missingEntitlement: // 8
            log("CloudKit: Missing entitlement - app is missing iCloud entitlements", type: "CloudKit", isError: true)

        case .notAuthenticated: // 9
            log("CloudKit: Not authenticated - user not signed in to iCloud", type: "CloudKit", isError: true)

        case .permissionFailure: // 10
            log("CloudKit: Permission failure - user denied permission", type: "CloudKit", isError: true)

        case .unknownItem: // 11
            log("CloudKit: Unknown item - referenced record doesn't exist on server", type: "CloudKit", isError: true)

        case .invalidArguments: // 12
            log("CloudKit: Invalid arguments - bad request parameters", type: "CloudKit", isError: true)

        case .serverRecordChanged: // 14
            log("CloudKit: Server record changed (CONFLICT detected)", type: "CloudKit", isError: true)
            if let serverRecord = error.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord {
                log("  Server record: type=\(serverRecord.recordType), ID=\(serverRecord.recordID.recordName)", type: "CloudKit", isError: true)
                log("  Server modified: \(serverRecord.modificationDate?.description ?? "unknown")", type: "CloudKit", isError: true)
            }
            if let clientRecord = error.userInfo[CKRecordChangedErrorClientRecordKey] as? CKRecord {
                log("  Client record: type=\(clientRecord.recordType), ID=\(clientRecord.recordID.recordName)", type: "CloudKit", isError: true)
            }
            if let ancestorRecord = error.userInfo[CKRecordChangedErrorAncestorRecordKey] as? CKRecord {
                log("  Ancestor record: type=\(ancestorRecord.recordType), ID=\(ancestorRecord.recordID.recordName)", type: "CloudKit", isError: true)
            }

        case .serverRejectedRequest: // 15
            log("CloudKit: Server rejected request", type: "CloudKit", isError: true)

        case .assetFileNotFound: // 16
            log("CloudKit: Asset file not found", type: "CloudKit", isError: true)

        case .assetFileModified: // 17
            log("CloudKit: Asset file was modified during upload", type: "CloudKit", isError: true)

        case .incompatibleVersion: // 18
            log("CloudKit: Incompatible version - app may need update", type: "CloudKit", isError: true)

        case .constraintViolation: // 19
            log("CloudKit: Constraint violation - unique constraint failed", type: "CloudKit", isError: true)

        case .operationCancelled: // 20
            log("CloudKit: Operation was cancelled", type: "CloudKit", isError: true)

        case .changeTokenExpired: // 21
            log("CloudKit: Change token expired - need full re-sync", type: "CloudKit", isError: true)

        case .batchRequestFailed: // 22
            log("CloudKit: Batch request failed - one item caused entire batch to fail", type: "CloudKit", isError: true)

        case .zoneBusy: // 23
            log("CloudKit: Zone is busy, will retry", type: "CloudKit", isError: true)

        case .badDatabase: // 24
            log("CloudKit: Bad database - operation used wrong database", type: "CloudKit", isError: true)

        case .quotaExceeded: // 25
            log("CloudKit: iCloud storage quota exceeded", type: "CloudKit", isError: true)

        case .zoneNotFound: // 26
            log("CloudKit: Zone not found - the record zone doesn't exist", type: "CloudKit", isError: true)

        case .limitExceeded: // 27
            log("CloudKit: Limit exceeded (too many records or data too large)", type: "CloudKit", isError: true)

        case .userDeletedZone: // 28
            log("CloudKit: User deleted zone - user deleted app data from iCloud settings", type: "CloudKit", isError: true)

        default:
            log("CloudKit: Unhandled error code \(error.code)", type: "CloudKit", isError: true)
        }
    }

    private func logCloudKitErrorDetails(_ error: NSError, indent: String) {
        // Log additional details for nested errors
        if let serverRecord = error.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord {
            log("\(indent)Conflict - Server record: \(serverRecord.recordType) / \(serverRecord.recordID.recordName)", type: "CloudKit", isError: true)
        }
        if let resultErrors = error.userInfo["resultErrors"] as? [Error] {
            for resultError in resultErrors.prefix(5) {
                log("\(indent)Result error: \(resultError.localizedDescription)", type: "CloudKit", isError: true)
            }
        }
    }

    private func ckErrorCodeName(_ code: Int) -> String {
        switch code {
        case 1: return "internalError"
        case 2: return "partialFailure"
        case 3: return "networkUnavailable"
        case 4: return "networkFailure"
        case 5: return "badContainer"
        case 6: return "serviceUnavailable"
        case 7: return "requestRateLimited"
        case 8: return "missingEntitlement"
        case 9: return "notAuthenticated"
        case 10: return "permissionFailure"
        case 11: return "unknownItem"
        case 12: return "invalidArguments"
        case 13: return "resultsTruncated"
        case 14: return "serverRecordChanged"
        case 15: return "serverRejectedRequest"
        case 16: return "assetFileNotFound"
        case 17: return "assetFileModified"
        case 18: return "incompatibleVersion"
        case 19: return "constraintViolation"
        case 20: return "operationCancelled"
        case 21: return "changeTokenExpired"
        case 22: return "batchRequestFailed"
        case 23: return "zoneBusy"
        case 24: return "badDatabase"
        case 25: return "quotaExceeded"
        case 26: return "zoneNotFound"
        case 27: return "limitExceeded"
        case 28: return "userDeletedZone"
        case 29: return "tooManyParticipants"
        case 30: return "alreadyShared"
        case 31: return "referenceViolation"
        case 32: return "managedAccountRestricted"
        case 33: return "participantMayNeedVerification"
        case 34: return "serverResponseLost"
        case 35: return "assetNotAvailable"
        case 36: return "accountTemporarilyUnavailable"
        default: return "unknown(\(code))"
        }
    }

    private func eventTypeToString(_ type: NSPersistentCloudKitContainer.EventType) -> String {
        switch type {
        case .setup:
            return "Setup"
        case .import:
            return "Import"
        case .export:
            return "Export"
        @unknown default:
            return "Unknown"
        }
    }

    private func simplifyErrorMessage(_ error: Error) -> String {
        let nsError = error as NSError

        if nsError.domain == CKErrorDomain {
            switch CKError.Code(rawValue: nsError.code) {
            case .networkFailure, .networkUnavailable:
                return "Network unavailable"
            case .quotaExceeded:
                return "iCloud storage full"
            case .serverRecordChanged:
                return "Sync conflict"
            case .limitExceeded:
                return "Data too large"
            case .notAuthenticated:
                return "Not signed in to iCloud"
            default:
                break
            }
        }

        // Return shortened version of the error
        let message = error.localizedDescription
        if message.count > 50 {
            return String(message.prefix(47)) + "..."
        }
        return message
    }

    private func checkiCloudAccountStatus() {
        log("Checking iCloud account status...", type: "Setup")

        let container = cloudContainerIdentifier.map { CKContainer(identifier: $0) } ?? CKContainer.default()
        container.accountStatus { [weak self] status, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.log("iCloud account check failed: \(error.localizedDescription)", type: "Setup", isError: true)
                    self?.syncStatus = .error(error.localizedDescription)
                    return
                }

                let statusString: String
                switch status {
                case .available:
                    statusString = "Available"
                case .noAccount:
                    statusString = "No Account"
                case .restricted:
                    statusString = "Restricted"
                case .couldNotDetermine:
                    statusString = "Could Not Determine"
                case .temporarilyUnavailable:
                    statusString = "Temporarily Unavailable"
                @unknown default:
                    statusString = "Unknown"
                }

                self?.log("iCloud account status: \(statusString)", type: "Setup")

                switch status {
                case .available:
                    // iCloud is available, sync will proceed
                    break
                case .noAccount:
                    self?.syncStatus = .error("No iCloud account")
                case .restricted:
                    self?.syncStatus = .error("iCloud restricted")
                case .couldNotDetermine:
                    self?.syncStatus = .error("iCloud status unknown")
                case .temporarilyUnavailable:
                    self?.syncStatus = .error("iCloud temporarily unavailable")
                @unknown default:
                    self?.syncStatus = .error("iCloud unavailable")
                }
            }
        }
    }
}
