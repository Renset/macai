//
//  TabBackupRestoreView.swift
//  macai
//
//  Created by Renat Notfullin on 11.11.2023.
//

import CoreData
import SwiftUI

// MARK: - Database Backup Info

struct DatabaseBackupInfo: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    let date: Date?
    let sizeBytes: Int64

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
}

// MARK: - View

struct BackupRestoreView: View {
    @ObservedObject var store: ChatStore
    @State private var databaseBackups: [DatabaseBackupInfo] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Database Backups Section
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Database Backups")
                            .fontWeight(.medium)
                        Spacer()
                        Button("Reveal in Finder") {
                            DatabaseBackupManager.revealBackupsFolder()
                        }
                    }

                    Text("Automatic backups are created before major database migrations.")
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

                                Button {
                                    DatabaseBackupManager.revealInFinder(url: backup.url)
                                } label: {
                                    Image(systemName: "folder")
                                }
                                .buttonStyle(.borderless)
                                .help("Reveal in Finder")
                            }
                            .padding(.vertical, 4)

                            if backup.id != databaseBackups.last?.id {
                                Divider()
                            }
                        }
                    }
                }
                .padding(8)
            }

            // Export/Import Section
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Export & Import")
                        .fontWeight(.medium)

                    Text("Chats are exported into plaintext, unencrypted JSON file. You can import them back later.")
                        .foregroundColor(.secondary)
                        .font(.callout)

                    Divider()

                    HStack {
                        Text("Export chats history")
                        Spacer()
                        Button("Export to file...") {
                            store.loadFromCoreData { result in
                                switch result {
                                case .failure(let error):
                                    fatalError(error.localizedDescription)
                                case .success(let chats):
                                    let encoder = JSONEncoder()
                                    encoder.outputFormatting = .prettyPrinted
                                    let data = try! encoder.encode(chats)
                                    let savePanel = NSSavePanel()
                                    savePanel.allowedContentTypes = [.json]
                                    savePanel.nameFieldStringValue = "chats_\(getCurrentFormattedDate()).json"
                                    savePanel.begin { result in
                                        if result == .OK {
                                            do {
                                                try data.write(to: savePanel.url!)
                                            }
                                            catch {
                                                print(error)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    HStack {
                        Text("Import chats history")
                        Spacer()
                        Button("Import from file...") {
                            let openPanel = NSOpenPanel()
                            openPanel.allowedContentTypes = [.json]
                            openPanel.begin { result in
                                if result == .OK {
                                    do {
                                        let data = try Data(contentsOf: openPanel.url!)
                                        let decoder = JSONDecoder()
                                        let chats = try decoder.decode([Chat].self, from: data)

                                        store.saveToCoreData(chats: chats) { result in
                                            print("State saved")
                                            if case .failure(let error) = result {
                                                fatalError(error.localizedDescription)
                                            }
                                        }
                                    }
                                    catch {
                                        print(error)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(8)
            }
        }
        .padding()
        .onAppear {
            databaseBackups = DatabaseBackupManager.discoverBackups()
        }
    }
}
