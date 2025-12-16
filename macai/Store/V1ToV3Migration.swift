import AppKit
import CoreData
import SQLite3

struct MigrationState {
    let needsMigration: Bool
    let exportedData: MigrationDataExport?
    let progressWindow: MigrationProgressWindow?
}

/// Handles programmatic Core Data migration by exporting data from the legacy store and re-importing it
/// into a freshly created store. Built-in mapping-model based migration is intentionally avoided.
final class ProgrammaticMigrator {
    private let containerName: String
    private static let restoreURL = URL(string: "https://renset.dev/macai/v2.3.0-update-problem")!
    private static var restoreLinkOpened = false

    init(containerName: String) {
        self.containerName = containerName
    }

    func prepareIfNeeded() -> MigrationState {
        guard CoreDataBackupManager.needsMigrationBackup(containerName: containerName) else {
            return MigrationState(needsMigration: false, exportedData: nil, progressWindow: nil)
        }

        CoreDataBackupManager.createPreMigrationBackup(containerName: containerName)

        let window = MigrationProgressWindow()
        window.show()

        let storeURL = Self.storeURL(for: containerName)
        guard let export = MigrationDataExport.exportFromStore(at: storeURL) else {
            window.close()
            Self.presentFatalAlert(
                messageText: "Database Migration Failed",
                informativeText: "Failed to export your data for migration. Your data backup is available in the Backups folder.",
                includeBackupsButton: true
            )
        }

        Self.deleteLegacyStores(for: containerName)
        return MigrationState(needsMigration: true, exportedData: export, progressWindow: window)
    }

    func handleStoreLoadError(_ error: Error?, state: MigrationState) {
        guard let error = error else { return }
        state.progressWindow?.close()
        Self.presentFatalAlert(
            messageText: "Database Error",
            informativeText: "Failed to load the database. Your data backup is available in the Backups folder.\n\nError: \(error.localizedDescription)",
            includeBackupsButton: true
        )
    }

    func importIfNeeded(state: MigrationState, into container: NSPersistentContainer) {
        guard let data = state.exportedData else {
            state.progressWindow?.close()
            return
        }

        let importSuccess = data.importIntoContext(container.viewContext)
        state.progressWindow?.close()

        if importSuccess {
            if state.needsMigration {
                CoreDataBackupManager.markMigrationCompleted()
            }
        } else {
            Self.presentFatalAlert(
                messageText: "Data Import Failed",
                informativeText: "Failed to import your data after migration. Your data backup is available in the Backups folder.",
                includeBackupsButton: true
            )
        }
    }

    private static func storeURL(for containerName: String) -> URL {
        NSPersistentContainer.defaultDirectoryURL().appendingPathComponent("\(containerName).sqlite")
    }

    private static func deleteLegacyStores(for containerName: String) {
        let fm = FileManager.default
        let base = NSPersistentContainer.defaultDirectoryURL().appendingPathComponent(containerName)
        for ext in ["sqlite", "sqlite-wal", "sqlite-shm"] {
            let url = base.appendingPathExtension(ext)
            try? fm.removeItem(at: url)
        }
    }

    @discardableResult
    private static func presentFatalAlert(messageText: String, informativeText: String, includeBackupsButton: Bool) -> Never {
        let work = {
            if !restoreLinkOpened {
                NSWorkspace.shared.open(restoreURL)
                restoreLinkOpened = true
            }
            let alert = NSAlert()
            alert.messageText = messageText
            alert.informativeText = informativeText
            alert.alertStyle = .critical

            if includeBackupsButton {
                alert.addButton(withTitle: "Open Backups Folder")
            }

            alert.addButton(withTitle: "Open Restore Instructions")
            alert.addButton(withTitle: "Quit")

            let response = alert.runModal()
            if includeBackupsButton && response == .alertFirstButtonReturn {
                CoreDataBackupManager.revealBackupsFolder()
            } else if (includeBackupsButton && response == .alertSecondButtonReturn)
                        || (!includeBackupsButton && response == .alertFirstButtonReturn) {
                NSWorkspace.shared.open(restoreURL)
            }

            NSApp.terminate(nil)
        }

        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.sync(execute: work)
        }

        RunLoop.current.run(until: Date(timeIntervalSinceNow: 60))
        fatalError("Migration aborted")
    }
}

// MARK: - Migration Progress Window

final class MigrationProgressWindow {
    private var window: NSWindow?
    private var progressIndicator: NSProgressIndicator?

    func show() {
        DispatchQueue.main.async { [weak self] in
            self?.createAndShowWindow()
        }
        // Small delay to ensure window is displayed before migration starts
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    }

    private func createAndShowWindow() {
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 120))

        let titleLabel = NSTextField(labelWithString: "Updating Database")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 14)
        titleLabel.frame = NSRect(x: 20, y: 80, width: 300, height: 20)
        contentView.addSubview(titleLabel)

        let descLabel = NSTextField(labelWithString: "Please wait while your data is being migrated.\nDo not close the application.")
        descLabel.font = NSFont.systemFont(ofSize: 12)
        descLabel.textColor = .secondaryLabelColor
        descLabel.frame = NSRect(x: 20, y: 45, width: 300, height: 35)
        descLabel.maximumNumberOfLines = 2
        contentView.addSubview(descLabel)

        let progress = NSProgressIndicator(frame: NSRect(x: 20, y: 15, width: 300, height: 20))
        progress.style = .bar
        progress.isIndeterminate = true
        progress.startAnimation(nil)
        contentView.addSubview(progress)
        self.progressIndicator = progress

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "macai"
        window.contentView = contentView
        window.center()
        window.level = .modalPanel
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)

        self.window = window
    }

    func close() {
        let closeWork = { [weak self] in
            self?.progressIndicator?.stopAnimation(nil)
            self?.window?.close()
            self?.window = nil
        }

        if Thread.isMainThread {
            closeWork()
        } else {
            DispatchQueue.main.sync(execute: closeWork)
        }
    }
}

// MARK: - Migration Data Export/Import

struct MigrationDataExport {
    var apiServices: [[String: Any]] = []
    var personas: [[String: Any]] = []
    var chats: [[String: Any]] = []
    var messages: [[String: Any]] = []
    var images: [[String: Any]] = []

    /// Export data from an old SQLite store using raw SQL queries
    static func exportFromStore(at storeURL: URL) -> MigrationDataExport? {
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            print("Store not found at \(storeURL.path)")
            return nil
        }

        var db: OpaquePointer?
        guard sqlite3_open(storeURL.path, &db) == SQLITE_OK else {
            print("Could not open database")
            return nil
        }
        defer { sqlite3_close(db) }

        var export = MigrationDataExport()

        print("Reading API services...")
        if let results = executeQuery(db: db, query: "SELECT * FROM ZAPISERVICEENTITY") {
            export.apiServices = results
            print("Found \(export.apiServices.count) API services")
        }

        print("Reading personas...")
        if let results = executeQuery(db: db, query: "SELECT * FROM ZPERSONAENTITY") {
            export.personas = results
            print("Found \(export.personas.count) personas")
        }

        print("Reading chats...")
        if let results = executeQuery(db: db, query: "SELECT * FROM ZCHATENTITY") {
            export.chats = results
            print("Found \(export.chats.count) chats")
        }

        print("Reading messages...")
        if let results = executeQuery(db: db, query: """
            SELECT m.*, o.Z_FOK_MESSAGES as ZORDER_INDEX
            FROM ZMESSAGEENTITY m
            LEFT JOIN Z_1MESSAGES o ON m.Z_PK = o.Z_2MESSAGES
            ORDER BY m.ZCHAT, COALESCE(o.Z_FOK_MESSAGES, m.ZTIMESTAMP)
        """) {
            export.messages = results
            print("Found \(export.messages.count) messages")
        } else if let results = executeQuery(db: db, query: "SELECT * FROM ZMESSAGEENTITY ORDER BY ZCHAT, ZTIMESTAMP") {
            export.messages = results
            print("Found \(export.messages.count) messages (ordered by timestamp)")
        }

        print("Reading images...")
        if let results = executeQuery(db: db, query: "SELECT * FROM ZIMAGEENTITY") {
            export.images = results
            print("Found \(export.images.count) images")
        }

        return export
    }

    /// Import exported data into a fresh Core Data context
    func importIntoContext(_ context: NSManagedObjectContext) -> Bool {
        print("Starting data import...")

        var apiServiceMap: [Int64: NSManagedObject] = [:]
        var personaMap: [Int64: NSManagedObject] = [:]
        var chatMap: [Int64: NSManagedObject] = [:]

        print("Importing \(apiServices.count) API services...")
        for data in apiServices {
            let entity = NSEntityDescription.insertNewObject(forEntityName: "APIServiceEntity", into: context)
            if let pk = data["Z_PK"] as? Int64 { apiServiceMap[pk] = entity }
            Self.setAttributes(on: entity, from: data, excluding: ["Z_PK", "Z_ENT", "Z_OPT", "ZDEFAULTPERSONA"])
        }

        print("Importing \(personas.count) personas...")
        for data in personas {
            let entity = NSEntityDescription.insertNewObject(forEntityName: "PersonaEntity", into: context)
            if let pk = data["Z_PK"] as? Int64 { personaMap[pk] = entity }
            Self.setAttributes(on: entity, from: data, excluding: ["Z_PK", "Z_ENT", "Z_OPT"])
        }

        for data in apiServices {
            if let pk = data["Z_PK"] as? Int64,
               let personaPK = data["ZDEFAULTPERSONA"] as? Int64,
               let service = apiServiceMap[pk],
               let persona = personaMap[personaPK] {
                service.setValue(persona, forKey: "defaultPersona")
            }
        }

        print("Importing \(chats.count) chats...")
        for data in chats {
            let entity = NSEntityDescription.insertNewObject(forEntityName: "ChatEntity", into: context)
            if let pk = data["Z_PK"] as? Int64 { chatMap[pk] = entity }
            Self.setAttributes(on: entity, from: data, excluding: ["Z_PK", "Z_ENT", "Z_OPT", "ZAPISERVICE", "ZPERSONA"])
            entity.setValue(Int64(0), forKey: "lastSequence")

            if let servicePK = data["ZAPISERVICE"] as? Int64, let service = apiServiceMap[servicePK] {
                entity.setValue(service, forKey: "apiService")
            }
            if let personaPK = data["ZPERSONA"] as? Int64, let persona = personaMap[personaPK] {
                entity.setValue(persona, forKey: "persona")
            }
        }

        print("Importing \(messages.count) messages...")
        var chatSequences: [Int64: Int64] = [:]
        for data in messages {
            let entity = NSEntityDescription.insertNewObject(forEntityName: "MessageEntity", into: context)
            Self.setAttributes(on: entity, from: data, excluding: ["Z_PK", "Z_ENT", "Z_OPT", "ZCHAT", "ZORDER_INDEX"])

            if let chatPK = data["ZCHAT"] as? Int64, let chat = chatMap[chatPK] {
                entity.setValue(chat, forKey: "chat")

                let seq = (chatSequences[chatPK] ?? 0) + 1
                chatSequences[chatPK] = seq
                entity.setValue(seq, forKey: "sequence")
            } else {
                entity.setValue(Int64(1), forKey: "sequence")
            }
        }

        for (chatPK, lastSeq) in chatSequences {
            if let chat = chatMap[chatPK] {
                chat.setValue(lastSeq, forKey: "lastSequence")
            }
        }

        print("Importing \(images.count) images...")
        for data in images {
            let entity = NSEntityDescription.insertNewObject(forEntityName: "ImageEntity", into: context)
            Self.setAttributes(on: entity, from: data, excluding: ["Z_PK", "Z_ENT", "Z_OPT"])
        }

        print("Saving imported data...")
        do {
            try context.save()
            print("Data import completed successfully!")
            return true
        } catch {
            print("Failed to save imported data: \(error)")
            return false
        }
    }

    // MARK: - Private helpers

    private static func executeQuery(db: OpaquePointer?, query: String) -> [[String: Any]]? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            let error = String(cString: sqlite3_errmsg(db))
            print("Query failed: \(error)")
            return nil
        }
        defer { sqlite3_finalize(statement) }

        var results: [[String: Any]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: Any] = [:]
            let columnCount = sqlite3_column_count(statement)

            for i in 0..<columnCount {
                let columnName = String(cString: sqlite3_column_name(statement, i))
                let columnType = sqlite3_column_type(statement, i)

                switch columnType {
                case SQLITE_INTEGER:
                    row[columnName] = sqlite3_column_int64(statement, i)
                case SQLITE_FLOAT:
                    row[columnName] = sqlite3_column_double(statement, i)
                case SQLITE_TEXT:
                    if let text = sqlite3_column_text(statement, i) {
                        row[columnName] = String(cString: text)
                    }
                case SQLITE_BLOB:
                    if let blob = sqlite3_column_blob(statement, i) {
                        let size = sqlite3_column_bytes(statement, i)
                        row[columnName] = Data(bytes: blob, count: Int(size))
                    }
                case SQLITE_NULL:
                    break
                default:
                    break
                }
            }
            results.append(row)
        }
        return results
    }

    private static func setAttributes(on entity: NSManagedObject, from data: [String: Any], excluding: [String]) {
        let entityDescription = entity.entity

        var columnToAttr: [String: NSAttributeDescription] = [:]
        for (attrName, attrDesc) in entityDescription.attributesByName {
            let columnName = "Z" + attrName.uppercased()
            columnToAttr[columnName] = attrDesc
        }

        for (key, value) in data {
            guard !excluding.contains(key) else { continue }
            guard let attrDesc = columnToAttr[key] else { continue }
            let attributeName = attrDesc.name

            switch attrDesc.attributeType {
            case .booleanAttributeType:
                if let intValue = value as? Int64 {
                    entity.setValue(intValue != 0, forKey: attributeName)
                } else if let boolValue = value as? Bool {
                    entity.setValue(boolValue, forKey: attributeName)
                }

            case .dateAttributeType:
                if let doubleValue = value as? Double {
                    let date = Date(timeIntervalSinceReferenceDate: doubleValue)
                    entity.setValue(date, forKey: attributeName)
                } else if let intValue = value as? Int64 {
                    let date = Date(timeIntervalSinceReferenceDate: Double(intValue))
                    entity.setValue(date, forKey: attributeName)
                }

            case .URIAttributeType:
                if let stringValue = value as? String, let url = URL(string: stringValue) {
                    entity.setValue(url, forKey: attributeName)
                } else if let url = value as? URL {
                    entity.setValue(url, forKey: attributeName)
                }

            case .UUIDAttributeType:
                if let stringValue = value as? String, let uuid = UUID(uuidString: stringValue) {
                    entity.setValue(uuid, forKey: attributeName)
                } else if let dataValue = value as? Data, dataValue.count == 16 {
                    let uuid = dataValue.withUnsafeBytes { ptr -> UUID in
                        let bytes = ptr.bindMemory(to: UInt8.self)
                        return UUID(uuid: (
                            bytes[0], bytes[1], bytes[2], bytes[3],
                            bytes[4], bytes[5], bytes[6], bytes[7],
                            bytes[8], bytes[9], bytes[10], bytes[11],
                            bytes[12], bytes[13], bytes[14], bytes[15]
                        ))
                    }
                    entity.setValue(uuid, forKey: attributeName)
                } else if let uuid = value as? UUID {
                    entity.setValue(uuid, forKey: attributeName)
                }

            case .binaryDataAttributeType:
                if let dataValue = value as? Data {
                    entity.setValue(dataValue, forKey: attributeName)
                }

            case .transformableAttributeType:
                if let dataValue = value as? Data {
                    entity.setValue(dataValue, forKey: attributeName)
                }

            default:
                entity.setValue(value, forKey: attributeName)
            }
        }
    }
}

// MARK: - Core Data backup helper

enum CoreDataBackupManager {
    private static let backupCompletedKey = "CoreDataBackupBeforeV3Completed"
    private static let backupNoticeShownKey = "CoreDataBackupBeforeV3NoticeShown"
    private static let targetModelVersionName = "macai_v2.3.0"

    static func needsMigrationBackup(containerName: String) -> Bool {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: backupCompletedKey) {
            return false
        }

        guard let storeBaseURL = defaultStoreURL(for: containerName) else { return false }
        let sqliteURL = storeBaseURL.appendingPathExtension("sqlite")
        return FileManager.default.fileExists(atPath: sqliteURL.path)
    }

    static func createPreMigrationBackup(containerName: String) {
        guard let storeBaseURL = defaultStoreURL(for: containerName) else { return }

        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backupsFolder = backupsDirectoryURL()
            .appendingPathComponent("Before-\(targetModelVersionName)-\(timestamp)", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: backupsFolder, withIntermediateDirectories: true)
            try copyStoreFiles(from: storeBaseURL, to: backupsFolder)
            UserDefaults.standard.set(backupsFolder.path, forKey: "CoreDataBackupBeforeV3Path")
            UserDefaults.standard.set(false, forKey: backupNoticeShownKey)
            print("Pre-migration backup created at: \(backupsFolder.path)")
        }
        catch {
            print("Pre-migration backup failed: \(error)")
        }
    }

    static func markMigrationCompleted() {
        UserDefaults.standard.set(true, forKey: backupCompletedKey)
        print("Migration marked as completed")

        if let backupPath = UserDefaults.standard.string(forKey: "CoreDataBackupBeforeV3Path") {
            NotificationPresenter.shared.scheduleNotification(
                identifier: "CoreDataBackupCompleted",
                title: "Database updated",
                body: "Database migrated successfully. Backup location: \(backupPath)"
            )
        }
    }

    static func revealBackupsFolder() {
        let backupsDir = backupsDirectoryURL()
        if FileManager.default.fileExists(atPath: backupsDir.path) {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: backupsDir.path)
        } else {
            let parentDir = backupsDir.deletingLastPathComponent()
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: parentDir.path)
        }
    }

    static func backupsDirectoryURL() -> URL {
        let base = NSPersistentContainer.defaultDirectoryURL()
        let bundleID = Bundle.main.bundleIdentifier ?? "macai"
        return base
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Backups", isDirectory: true)
    }

    private static func defaultStoreURL(for containerName: String) -> URL? {
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
}
