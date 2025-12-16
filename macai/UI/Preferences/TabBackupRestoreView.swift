//
//  TabBackupRestoreView.swift
//  macai
//
//  Created by Renat Notfullin on 11.11.2023.
//

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

// MARK: - Backup Discovery

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

                // Check if it contains sqlite files
                let sqliteFile = folderURL.appendingPathComponent("macaiDataModel.sqlite")
                guard fm.fileExists(atPath: sqliteFile.path) else { continue }

                // Calculate total size of backup
                var totalSize: Int64 = 0
                if let enumerator = fm.enumerator(at: folderURL, includingPropertiesForKeys: [.fileSizeKey]) {
                    for case let fileURL as URL in enumerator {
                        if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                            totalSize += Int64(fileSize)
                        }
                    }
                }

                // Parse date from folder name or use creation date
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

            // Sort by date, newest first
            return backups.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        } catch {
            print("Error discovering backups: \(error)")
            return []
        }
    }

    private static func parseBackupDate(from folderName: String) -> Date? {
        // Format: Before-macaiDataModel 3-2024-01-15T10-30-00Z
        let components = folderName.components(separatedBy: "-")
        guard components.count >= 4 else { return nil }

        // Find the ISO8601 date part (starts after the model version name)
        // The date part starts with a 4-digit year
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

        // Convert from "2024-01-15T10-30-00Z" to "2024-01-15T10:30:00Z"
        var isoString = dateString
        if let tIndex = isoString.firstIndex(of: "T") {
            let timePart = isoString[isoString.index(after: tIndex)...]
            let fixedTime = timePart.replacingOccurrences(of: "-", with: ":")
            isoString = String(isoString[...tIndex]) + fixedTime
        }

        let formatter = ISO8601DateFormatter()
        return formatter.date(from: isoString)
    }

    static func revealInFinder(url: URL) {
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
    }

    static func revealBackupsFolder() {
        guard let backupsDir = backupsDirectoryURL() else { return }
        if FileManager.default.fileExists(atPath: backupsDir.path) {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: backupsDir.path)
        } else {
            // Open the parent directory if Backups folder doesn't exist
            let parentDir = backupsDir.deletingLastPathComponent()
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: parentDir.path)
        }
    }

    // MARK: - Create Backup

    static func createBackup(named customName: String? = nil) throws -> URL {
        let fm = FileManager.default
        guard let backupsDir = backupsDirectoryURL() else {
            throw BackupError.backupsDirectoryNotFound
        }

        // Get the current store URL
        let base = NSPersistentContainer.defaultDirectoryURL()
        let storeBaseURL = base.appendingPathComponent("macaiDataModel")
        let sqliteURL = storeBaseURL.appendingPathExtension("sqlite")

        guard fm.fileExists(atPath: sqliteURL.path) else {
            throw BackupError.sourceNotFound
        }

        // Create backup folder name
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let folderName = customName ?? "Manual-Backup-\(timestamp)"
        let backupFolder = backupsDir.appendingPathComponent(folderName, isDirectory: true)

        // Create directories if needed
        try fm.createDirectory(at: backupFolder, withIntermediateDirectories: true)

        // Copy all store files
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

    // MARK: - Delete Backup

    static func deleteBackup(_ backup: DatabaseBackupInfo) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: backup.url.path) else {
            throw BackupError.backupNotFound
        }
        try fm.removeItem(at: backup.url)
    }

    // MARK: - Restore Backup

    static func restoreBackup(_ backup: DatabaseBackupInfo, createSafetyBackup: Bool = true) throws {
        let fm = FileManager.default
        let base = NSPersistentContainer.defaultDirectoryURL()
        let storeBaseURL = base.appendingPathComponent("macaiDataModel")

        // Create a safety backup before restore
        if createSafetyBackup {
            let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            _ = try? createBackup(named: "Before-Restore-\(timestamp)")
        }

        // Copy backup files to store location
        for ext in ["sqlite", "sqlite-wal", "sqlite-shm"] {
            let source = backup.url.appendingPathComponent("macaiDataModel.\(ext)")
            let destination = storeBaseURL.appendingPathExtension(ext)

            if fm.fileExists(atPath: source.path) {
                if fm.fileExists(atPath: destination.path) {
                    try fm.removeItem(at: destination)
                }
                try fm.copyItem(at: source, to: destination)
            }
        }
    }

    // MARK: - Export Backup as ZIP

    static func exportBackupAsZip(_ backup: DatabaseBackupInfo, to destinationURL: URL) throws {
        let fm = FileManager.default

        // Create a temporary directory for the zip contents
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? fm.removeItem(at: tempDir)
        }

        // Copy backup contents to temp directory
        let backupContentsDir = tempDir.appendingPathComponent(backup.name)
        try fm.copyItem(at: backup.url, to: backupContentsDir)

        // Create zip archive
        let coordinator = NSFileCoordinator()
        var error: NSError?

        coordinator.coordinate(readingItemAt: backupContentsDir, options: .forUploading, error: &error) { zipURL in
            do {
                if fm.fileExists(atPath: destinationURL.path) {
                    try fm.removeItem(at: destinationURL)
                }
                try fm.copyItem(at: zipURL, to: destinationURL)
            } catch {
                print("Error creating zip: \(error)")
            }
        }

        if let error = error {
            throw error
        }
    }

    // MARK: - Import Backup from ZIP

    static func importBackupFromZip(at sourceURL: URL) throws -> DatabaseBackupInfo {
        let fm = FileManager.default
        guard let backupsDir = backupsDirectoryURL() else {
            throw BackupError.backupsDirectoryNotFound
        }

        // Create backups directory if it doesn't exist
        if !fm.fileExists(atPath: backupsDir.path) {
            try fm.createDirectory(at: backupsDir, withIntermediateDirectories: true)
        }

        // Create a temporary directory for extraction
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? fm.removeItem(at: tempDir)
        }

        // Unzip the file
        let coordinator = NSFileCoordinator()
        var error: NSError?

        coordinator.coordinate(readingItemAt: sourceURL, options: .forUploading, error: &error) { _ in
            // This is for zipping, we need different approach for unzipping
        }

        // Use Process to unzip (macOS has built-in unzip)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", sourceURL.path, "-d", tempDir.path]
        process.standardOutput = nil
        process.standardError = nil
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw BackupError.unzipFailed
        }

        // Find the extracted backup folder
        let contents = try fm.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
        guard let extractedFolder = contents.first(where: { url in
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }) else {
            throw BackupError.invalidBackupArchive
        }

        // Verify it contains sqlite files
        let sqliteFile = extractedFolder.appendingPathComponent("macaiDataModel.sqlite")
        guard fm.fileExists(atPath: sqliteFile.path) else {
            throw BackupError.invalidBackupArchive
        }

        // Generate unique name for the imported backup
        let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let importedName = "Imported-\(timestamp)"
        let destinationFolder = backupsDir.appendingPathComponent(importedName, isDirectory: true)

        // Move to backups directory
        try fm.copyItem(at: extractedFolder, to: destinationFolder)

        // Calculate size
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

    // MARK: - Errors

    enum BackupError: LocalizedError {
        case backupsDirectoryNotFound
        case sourceNotFound
        case backupNotFound
        case unzipFailed
        case invalidBackupArchive
        case restoreFailed

        var errorDescription: String? {
            switch self {
            case .backupsDirectoryNotFound:
                return "Could not find or create backups directory"
            case .sourceNotFound:
                return "Database files not found"
            case .backupNotFound:
                return "Backup not found"
            case .unzipFailed:
                return "Failed to extract backup archive"
            case .invalidBackupArchive:
                return "Invalid backup archive - no valid database files found"
            case .restoreFailed:
                return "Failed to restore backup"
            }
        }
    }
}

// MARK: - View

struct BackupRestoreView: View {
    @ObservedObject var store: ChatStore
    @State private var databaseBackups: [DatabaseBackupInfo] = []
    @State private var selectedBackup: DatabaseBackupInfo?
    @State private var showDeleteConfirmation = false
    @State private var showRestoreConfirmation = false
    @State private var showCreateBackupAlert = false
    @State private var isCreatingBackup = false
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var showRestartAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Database Backups Section
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Database Backups")
                            .fontWeight(.medium)

                        Button {
                        } label: {
                            Image(systemName: "info.circle")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Full database backups contain ALL your data including chats, messages, images, API services, personas, and settings. These are created automatically before major database updates, or can be created manually.")

                        Spacer()

                        Button {
                            createBackup()
                        } label: {
                            HStack(spacing: 4) {
                                if isCreatingBackup {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                        .frame(width: 12, height: 12)
                                } else {
                                    Image(systemName: "plus")
                                }
                                Text("Create Backup")
                            }
                        }
                        .disabled(isCreatingBackup)

                        Button {
                            importBackupFromZip()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "square.and.arrow.down")
                                Text("Import")
                            }
                        }
                        .help("Import a backup from a .zip file")
                    }

                    Text("Full backups are created automatically before database migrations")
                        .foregroundColor(.secondary)
                        .font(.callout)

                    if databaseBackups.isEmpty {
                        HStack {
                            Spacer()
                            Text("No database backups found")
                                .foregroundColor(.secondary)
                                .font(.callout)
                                .padding(.vertical, 8)
                            Spacer()
                        }
                    } else {
                        Divider()

                        ForEach(databaseBackups) { backup in
                            BackupRowView(
                                backup: backup,
                                onReveal: {
                                    DatabaseBackupManager.revealInFinder(url: backup.url)
                                },
                                onExport: {
                                    exportBackupAsZip(backup)
                                },
                                onRestore: {
                                    selectedBackup = backup
                                    showRestoreConfirmation = true
                                },
                                onDelete: {
                                    selectedBackup = backup
                                    showDeleteConfirmation = true
                                }
                            )

                            if backup.id != databaseBackups.last?.id {
                                Divider()
                            }
                        }
                    }

                    Divider()

                    HStack {
                        Button("Open Backups Folder") {
                            DatabaseBackupManager.revealBackupsFolder()
                        }
                        .buttonStyle(.link)

                        Spacer()
                    }
                }
                .padding(8)
            }

            // JSON Export/Import Section
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("JSON Export & Import")
                            .fontWeight(.medium)

                        Button {
                        } label: {
                            Image(systemName: "info.circle")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("JSON export contains only chat text and basic metadata. It does NOT include:\n• Images and attachments\n• API service configurations\n• API tokens/credentials\n• Personas\n• App settings\n\nUse this for sharing chats or lightweight backups. For complete backups, use Database Backups above.")
                    }

                    Text("Export chats as JSON (text only, no images or settings)")
                        .foregroundColor(.secondary)
                        .font(.callout)

                    Divider()

                    HStack {
                        Text("Export chats history")
                        Spacer()
                        Button("Export to JSON...") {
                            exportToJSON()
                        }
                    }

                    HStack {
                        Text("Import chats history")
                        Spacer()
                        Button("Import from JSON...") {
                            importFromJSON()
                        }
                    }
                }
                .padding(8)
            }
        }
        .padding()
        .onAppear {
            refreshBackups()
        }
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
            Text("Restoring this backup will replace your current database. A safety backup will be created automatically. The app will need to restart after restoration.")
        }
        .alert("Backup", isPresented: $showAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
        .alert("Restart Required", isPresented: $showRestartAlert) {
            Button("Restart Now") {
                restartApp()
            }
            Button("Later", role: .cancel) { }
        } message: {
            Text("The backup has been restored. Please restart the app to load the restored data.")
        }
    }

    // MARK: - Actions

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
                    alertMessage = "Backup created successfully at:\n\(backupURL.lastPathComponent)"
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
                    showRestartAlert = true
                }
            } catch {
                DispatchQueue.main.async {
                    alertMessage = "Failed to restore backup: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }

    private func exportBackupAsZip(_ backup: DatabaseBackupInfo) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.zip]
        savePanel.nameFieldStringValue = "\(backup.name).zip"
        savePanel.begin { result in
            if result == .OK, let url = savePanel.url {
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try DatabaseBackupManager.exportBackupAsZip(backup, to: url)
                        DispatchQueue.main.async {
                            alertMessage = "Backup exported successfully"
                            showAlert = true
                        }
                    } catch {
                        DispatchQueue.main.async {
                            alertMessage = "Failed to export backup: \(error.localizedDescription)"
                            showAlert = true
                        }
                    }
                }
            }
        }
    }

    private func importBackupFromZip() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.zip]
        openPanel.begin { result in
            if result == .OK, let url = openPanel.url {
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let importedBackup = try DatabaseBackupManager.importBackupFromZip(at: url)
                        DispatchQueue.main.async {
                            refreshBackups()
                            alertMessage = "Backup imported successfully: \(importedBackup.name)"
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
                    let savePanel = NSSavePanel()
                    savePanel.allowedContentTypes = [.json]
                    savePanel.nameFieldStringValue = "chats_\(getCurrentFormattedDate()).json"
                    savePanel.begin { result in
                        if result == .OK, let url = savePanel.url {
                            do {
                                try data.write(to: url)
                            } catch {
                                alertMessage = "Failed to save file: \(error.localizedDescription)"
                                showAlert = true
                            }
                        }
                    }
                } catch {
                    alertMessage = "Failed to encode chats: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }

    private func importFromJSON() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        openPanel.begin { result in
            if result == .OK, let url = openPanel.url {
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
    }

    private func restartApp() {
        let url = URL(fileURLWithPath: Bundle.main.resourcePath!)
        let path = url.deletingLastPathComponent().deletingLastPathComponent().absoluteString
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = [path]
        task.launch()
        NSApp.terminate(nil)
    }
}

// MARK: - Backup Row View

struct BackupRowView: View {
    let backup: DatabaseBackupInfo
    let onReveal: () -> Void
    let onExport: () -> Void
    let onRestore: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
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

            HStack(spacing: 4) {
                Button {
                    onReveal()
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("Reveal in Finder")

                Button {
                    onExport()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
                .help("Export as ZIP")

                Button {
                    onRestore()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .help("Restore this backup")

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
                .help("Delete backup")
            }
        }
        .padding(.vertical, 4)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
