//
//  BackupRestoreView+iOS.swift
//  macai
//
//  iOS backup & restore view (local backups + JSON import/export).
//

#if os(iOS)

import CoreData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Database Backup Info

struct DatabaseBackupInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
    let date: Date?
    let sizeBytes: Int64

    init(name: String, url: URL, date: Date?, sizeBytes: Int64) {
        self.id = url.path
        self.name = name
        self.url = url
        self.date = date
        self.sizeBytes = sizeBytes
    }

    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: sizeBytes)
    }

    var formattedDate: String {
        guard let date = date else { return "Unknown date" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: DatabaseBackupInfo, rhs: DatabaseBackupInfo) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Backup Manager (iOS)

enum DatabaseBackupManager {
    static func backupsDirectoryURL() -> URL? {
        let base = NSPersistentContainer.defaultDirectoryURL()
        let bundleID = Bundle.main.bundleIdentifier ?? "macai"
        let backupsURL = base
            .appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Backups", isDirectory: true)
        return backupsURL
    }

    static func discoverBackups() -> [DatabaseBackupInfo] {
        guard let backupsDir = backupsDirectoryURL() else { return [] }

        let fm = FileManager.default
        guard fm.fileExists(atPath: backupsDir.path) else { return [] }

        do {
            let contents = try fm.contentsOfDirectory(
                at: backupsDir,
                includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey],
                options: [.skipsHiddenFiles]
            )

            var backups: [DatabaseBackupInfo] = []

            for folderURL in contents {
                var isDirectory: ObjCBool = false
                guard fm.fileExists(atPath: folderURL.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else { continue }

                let sqliteFile = folderURL.appendingPathComponent("macaiDataModel.sqlite")
                guard fm.fileExists(atPath: sqliteFile.path) else { continue }

                var totalSize: Int64 = 0
                if let enumerator = fm.enumerator(at: folderURL, includingPropertiesForKeys: [.fileSizeKey]) {
                    for case let fileURL as URL in enumerator {
                        if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                            totalSize += Int64(fileSize)
                        }
                    }
                }

                let date = parseBackupDate(from: folderURL.lastPathComponent)
                    ?? (try? folderURL.resourceValues(forKeys: [.creationDateKey]).creationDate)

                let backup = DatabaseBackupInfo(
                    name: folderURL.lastPathComponent,
                    url: folderURL,
                    date: date,
                    sizeBytes: totalSize
                )
                backups.append(backup)
            }

            return backups.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        } catch {
            print("Error discovering backups: \(error)")
            return []
        }
    }

    private static func parseBackupDate(from folderName: String) -> Date? {
        let components = folderName.components(separatedBy: "-")
        guard components.count >= 4 else { return nil }

        var dateString = ""
        var foundYear = false

        for component in components {
            if !foundYear && component.count == 4, Int(component) != nil, Int(component)! > 2000 {
                foundYear = true
                dateString = component
            } else if foundYear {
                dateString += "-" + component
            }
        }

        var isoString = dateString
        if let tIndex = isoString.firstIndex(of: "T") {
            let timePart = isoString[isoString.index(after: tIndex)...]
            let fixedTime = timePart.replacingOccurrences(of: "-", with: ":")
            isoString = String(isoString[...tIndex]) + fixedTime
        }

        let formatter = ISO8601DateFormatter()
        return formatter.date(from: isoString)
    }

    static func createBackup(named customName: String? = nil) throws -> URL {
        let fm = FileManager.default
        guard let backupsDir = backupsDirectoryURL() else {
            throw BackupError.backupsDirectoryNotFound
        }

        let base = NSPersistentContainer.defaultDirectoryURL()
        let storeBaseURL = base.appendingPathComponent("macaiDataModel")
        let sqliteURL = storeBaseURL.appendingPathExtension("sqlite")

        guard fm.fileExists(atPath: sqliteURL.path) else {
            throw BackupError.sourceNotFound
        }

        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let folderName = customName ?? "Manual-Backup-\(timestamp)"
        let backupFolder = backupsDir.appendingPathComponent(folderName, isDirectory: true)

        try fm.createDirectory(at: backupFolder, withIntermediateDirectories: true)

        for ext in ["sqlite", "sqlite-wal", "sqlite-shm"] {
            let source = storeBaseURL.appendingPathExtension(ext)
            guard fm.fileExists(atPath: source.path) else { continue }
            let destination = backupFolder.appendingPathComponent(source.lastPathComponent)
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.copyItem(at: source, to: destination)
        }

        return backupFolder
    }

    static func deleteBackup(_ backup: DatabaseBackupInfo) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: backup.url.path) else {
            throw BackupError.backupNotFound
        }
        try fm.removeItem(at: backup.url)
    }

    static func restoreBackup(_ backup: DatabaseBackupInfo) throws {
        let fm = FileManager.default
        let base = NSPersistentContainer.defaultDirectoryURL()
        let storeBaseURL = base.appendingPathComponent("macaiDataModel")

        UserDefaults.standard.set(true, forKey: "CoreDataMigrationRetrySkipBackup")

        for ext in ["sqlite", "sqlite-wal", "sqlite-shm"] {
            let source = backup.url.appendingPathComponent("macaiDataModel.\(ext)")
            let destination = storeBaseURL.appendingPathExtension(ext)

            if fm.fileExists(atPath: source.path) {
                if fm.fileExists(atPath: destination.path) {
                    try fm.removeItem(at: destination)
                }
                try fm.copyItem(at: source, to: destination)
                normalizeStorePermissions(at: destination)
            }
        }
    }

    static func importBackupFolder(at sourceURL: URL) throws -> DatabaseBackupInfo {
        let fm = FileManager.default
        guard let backupsDir = backupsDirectoryURL() else {
            throw BackupError.backupsDirectoryNotFound
        }

        if !fm.fileExists(atPath: backupsDir.path) {
            try fm.createDirectory(at: backupsDir, withIntermediateDirectories: true)
        }

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: sourceURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw BackupError.invalidBackupArchive
        }

        let sqliteFile = sourceURL.appendingPathComponent("macaiDataModel.sqlite")
        guard fm.fileExists(atPath: sqliteFile.path) else {
            throw BackupError.invalidBackupArchive
        }

        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let importedName = "Imported-\(timestamp)"
        let destinationFolder = backupsDir.appendingPathComponent(importedName, isDirectory: true)

        try fm.copyItem(at: sourceURL, to: destinationFolder)

        var totalSize: Int64 = 0
        if let enumerator = fm.enumerator(at: destinationFolder, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let fileURL as URL in enumerator {
                if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(fileSize)
                }
            }
        }

        return DatabaseBackupInfo(
            name: importedName,
            url: destinationFolder,
            date: Date(),
            sizeBytes: totalSize
        )
    }

    private static func normalizeStorePermissions(at url: URL) {
        let fm = FileManager.default
        let attributes: [FileAttributeKey: Any] = [
            .posixPermissions: NSNumber(value: 0o600),
            .immutable: false,
            .appendOnly: false
        ]
        do {
            try fm.setAttributes(attributes, ofItemAtPath: url.path)
        } catch {
            print("Failed to normalize store permissions for \(url.lastPathComponent): \(error)")
        }
    }

    enum BackupError: LocalizedError {
        case backupsDirectoryNotFound
        case sourceNotFound
        case backupNotFound
        case invalidBackupArchive
        case restoreFailed

        var errorDescription: String? {
            switch self {
            case .backupsDirectoryNotFound:
                return "Could not find or create backups directory"
            case .sourceNotFound:
                return "Source database not found"
            case .backupNotFound:
                return "Backup not found"
            case .invalidBackupArchive:
                return "Invalid backup folder - no valid database files found"
            case .restoreFailed:
                return "Failed to restore backup"
            }
        }
    }
}

// MARK: - JSON File Document

struct JSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Backup Restore View (iOS)

struct BackupRestoreView: View {
    @ObservedObject var store: ChatStore

    @State private var databaseBackups: [DatabaseBackupInfo] = []
    @State private var isCreatingBackup = false
    @State private var selectedBackup: DatabaseBackupInfo?
    @State private var showDeleteConfirmation = false
    @State private var showRestoreConfirmation = false
    @State private var showAlert = false
    @State private var alertMessage = ""

    @State private var isImportingBackup = false
    @State private var isImportingJSON = false
    @State private var isExportingJSON = false
    @State private var exportJSONDocument: JSONDocument?

    @State private var shareItems: [Any] = []
    @State private var isSharePresented = false

    var body: some View {
        ScrollView {
            content
        }
        .padding()
        .onAppear(perform: refreshBackups)
        .alert("Delete Backup", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let backup = selectedBackup {
                    deleteBackup(backup)
                }
            }
        } message: {
            Text("Are you sure you want to delete this backup? This action cannot be undone.")
        }
        .alert("Restore Backup", isPresented: $showRestoreConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Restore", role: .destructive) {
                if let backup = selectedBackup {
                    restoreBackup(backup)
                }
            }
        } message: {
            Text("Restoring this backup will replace your current data. Restart the app to load the restored data.")
        }
        .alert("Backup", isPresented: $showAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
        .fileImporter(
            isPresented: $isImportingBackup,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleBackupImport(result)
        }
        .fileImporter(
            isPresented: $isImportingJSON,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleJSONImport(result)
        }
        .fileExporter(
            isPresented: $isExportingJSON,
            document: exportJSONDocument ?? JSONDocument(),
            contentType: .json,
            defaultFilename: "chats_\(currentFormattedDate())"
        ) { result in
            if case .failure(let error) = result {
                alertMessage = "Failed to export: \(error.localizedDescription)"
                showAlert = true
            }
        }
        .sheet(isPresented: $isSharePresented) {
            ShareSheet(activityItems: shareItems)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Backup & Restore")
                .font(.title2)
                .bold()

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Create a full backup of chats, messages, images, and settings.")
                            .foregroundColor(.secondary)
                            .font(.callout)
                        Spacer()
                    }

                    HStack {
                        Button(action: createBackup) {
                            if isCreatingBackup {
                                ProgressView()
                            } else {
                                Label("Create Backup", systemImage: "externaldrive.badge.plus")
                            }
                        }

                        Button(action: { isImportingBackup = true }) {
                            Label("Import Backup Folder", systemImage: "square.and.arrow.down")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
                .padding(4)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Available Backups")
                        .font(.headline)

                    if databaseBackups.isEmpty {
                        Text("No data backups found")
                            .foregroundColor(.secondary)
                            .font(.callout)
                    } else {
                        List {
                            ForEach(databaseBackups) { backup in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(backup.formattedDate)
                                            .font(.system(.body, design: .default))
                                        Text(backup.name)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }

                                    Spacer()

                                    Text(backup.formattedSize)
                                        .font(.callout)
                                        .foregroundColor(.secondary)

                                    Menu {
                                        Button("Share Backup") {
                                            shareBackup(backup)
                                        }
                                        Button("Restore Backup") {
                                            selectedBackup = backup
                                            showRestoreConfirmation = true
                                        }
                                        Button("Delete Backup", role: .destructive) {
                                            selectedBackup = backup
                                            showDeleteConfirmation = true
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis.circle")
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        .listStyle(.plain)
                        .frame(minHeight: 160)
                    }
                }
                .padding(4)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("JSON Export")
                        .font(.headline)

                    Text("Export chats as JSON (no images, attachments, or settings).")
                        .foregroundColor(.secondary)
                        .font(.callout)

                    HStack {
                        Button("Export to JSON") {
                            exportToJSON()
                        }
                        Button("Import from JSON") {
                            isImportingJSON = true
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
                .padding(4)
            }
        }
    }

    private func refreshBackups() {
        databaseBackups = DatabaseBackupManager.discoverBackups()
    }

    private func createBackup() {
        isCreatingBackup = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let backupURL = try DatabaseBackupManager.createBackup()
                DispatchQueue.main.async {
                    isCreatingBackup = false
                    refreshBackups()
                    alertMessage = "Backup created: \(backupURL.lastPathComponent)"
                    showAlert = true
                }
            } catch {
                DispatchQueue.main.async {
                    isCreatingBackup = false
                    alertMessage = "Failed to create backup: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }

    private func deleteBackup(_ backup: DatabaseBackupInfo) {
        do {
            try DatabaseBackupManager.deleteBackup(backup)
            refreshBackups()
        } catch {
            alertMessage = "Failed to delete backup: \(error.localizedDescription)"
            showAlert = true
        }
    }

    private func restoreBackup(_ backup: DatabaseBackupInfo) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try DatabaseBackupManager.restoreBackup(backup)
                DispatchQueue.main.async {
                    alertMessage = "Backup restored. Please restart the app to load the restored data."
                    showAlert = true
                }
            } catch {
                DispatchQueue.main.async {
                    alertMessage = "Failed to restore backup: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }

    private func shareBackup(_ backup: DatabaseBackupInfo) {
        shareItems = [backup.url]
        isSharePresented = true
    }

    private func handleBackupImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            alertMessage = "Failed to import backup: \(error.localizedDescription)"
            showAlert = true
        case .success(let urls):
            guard let url = urls.first else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer {
                if access { url.stopAccessingSecurityScopedResource() }
            }
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let importedBackup = try DatabaseBackupManager.importBackupFolder(at: url)
                    DispatchQueue.main.async {
                        refreshBackups()
                        alertMessage = "Backup imported: \(importedBackup.name)"
                        showAlert = true
                    }
                } catch {
                    DispatchQueue.main.async {
                        alertMessage = "Failed to import backup: \(error.localizedDescription)"
                        showAlert = true
                    }
                }
            }
        }
    }

    private func exportToJSON() {
        store.loadFromCoreData { result in
            switch result {
            case .failure(let error):
                alertMessage = "Failed to export: \(error.localizedDescription)"
                showAlert = true
            case .success(let chats):
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                do {
                    let data = try encoder.encode(chats)
                    exportJSONDocument = JSONDocument(data: data)
                    isExportingJSON = true
                } catch {
                    alertMessage = "Failed to encode chats: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }

    private func handleJSONImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            alertMessage = "Failed to import: \(error.localizedDescription)"
            showAlert = true
        case .success(let urls):
            guard let url = urls.first else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer {
                if access { url.stopAccessingSecurityScopedResource() }
            }
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                let chats = try decoder.decode([Chat].self, from: data)

                store.saveToCoreData(chats: chats) { result in
                    switch result {
                    case .success:
                        alertMessage = "Imported \(chats.count) chat(s) successfully"
                        showAlert = true
                    case .failure(let error):
                        alertMessage = "Failed to import: \(error.localizedDescription)"
                        showAlert = true
                    }
                }
            } catch {
                alertMessage = "Failed to read file: \(error.localizedDescription)"
                showAlert = true
            }
        }
    }

    private func currentFormattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: Date())
    }
}

#endif
