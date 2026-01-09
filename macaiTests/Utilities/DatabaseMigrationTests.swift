//
//  DatabaseMigrationTests.swift
//  macaiTests
//
//  Created by Renat Notfullin on 09.01.2026.
//

import CoreData
import XCTest
@testable import macai

final class DatabaseMigrationTests: XCTestCase {
    private let userDefaults = UserDefaults.standard
    private let migrationKeys = [
        "CoreDataMigrationToV3Completed",
        "CoreDataBackupBeforeV3Completed",
        "CoreDataBackupBeforeV3NoticeShown",
        "CoreDataMigrationRetrySkipBackup",
    ]

    override func setUpWithError() throws {
        try super.setUpWithError()
        clearMigrationDefaults()
    }

    override func tearDownWithError() throws {
        clearMigrationDefaults()
        try super.tearDownWithError()
    }

    func testNeedsMigrationBackupSkipsWhenDBVersionIsLatest() throws {
        guard let model = loadCurrentModel() else {
            throw XCTSkip("Core Data model not found in bundle")
        }

        let containerName = "MigrationTest-\(UUID().uuidString)"
        let store = try createStore(
            containerName: containerName,
            model: model,
            metadata: ["DB_VERSION": 3]
        )
        defer { removeStoreFiles(at: store.baseURL) }

        XCTAssertFalse(CoreDataBackupManager.needsMigrationBackup(containerName: containerName))
    }

    func testNeedsMigrationBackupSkipsWhenStoreCompatible() throws {
        guard let model = loadCurrentModel() else {
            throw XCTSkip("Core Data model not found in bundle")
        }

        let containerName = "MigrationTest-\(UUID().uuidString)"
        let store = try createStore(
            containerName: containerName,
            model: model
        )
        defer { removeStoreFiles(at: store.baseURL) }

        XCTAssertFalse(CoreDataBackupManager.needsMigrationBackup(containerName: containerName))
    }

    func testShouldAttemptProgrammaticRecoverySkipsWhenDBVersionIsLatest() throws {
        guard let model = loadCurrentModel() else {
            throw XCTSkip("Core Data model not found in bundle")
        }

        let containerName = "RecoveryTest-\(UUID().uuidString)"
        let store = try createStore(
            containerName: containerName,
            model: model,
            metadata: ["DB_VERSION": 3]
        )
        defer { removeStoreFiles(at: store.baseURL) }

        XCTAssertFalse(CoreDataBackupManager.shouldAttemptProgrammaticRecovery(containerName: containerName))
    }

    func testShouldNotAttemptProgrammaticRecoveryWhenMetadataMissing() throws {
        let containerName = "RecoveryTest-\(UUID().uuidString)"
        let store = try createInvalidStore(containerName: containerName)
        defer { removeStoreFiles(at: store.baseURL) }

        XCTAssertFalse(CoreDataBackupManager.shouldAttemptProgrammaticRecovery(containerName: containerName))
    }

    func testShouldAttemptProgrammaticRecoveryWhenDBVersionIsLegacy() throws {
        guard let model = loadCurrentModel() else {
            throw XCTSkip("Core Data model not found in bundle")
        }

        let containerName = "RecoveryTest-\(UUID().uuidString)"
        let store = try createStore(
            containerName: containerName,
            model: model,
            metadata: ["DB_VERSION": 2]
        )
        defer { removeStoreFiles(at: store.baseURL) }

        XCTAssertTrue(CoreDataBackupManager.shouldAttemptProgrammaticRecovery(containerName: containerName))
    }

    func testMigrationExportsAndImportsDocuments() throws {
        guard let model = loadCurrentModel() else {
            throw XCTSkip("Core Data model not found in bundle")
        }

        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("macai-migration-\(UUID().uuidString)")
        let docData = "test-pdf".data(using: .utf8) ?? Data()
        let document = DocumentSeed(
            id: UUID(),
            filename: "doc.pdf",
            mimeType: "application/pdf",
            fileData: docData
        )

        let store = try createStore(
            baseURL: tempBase,
            model: model,
            documents: [document]
        )
        defer { removeStoreFiles(at: store.baseURL) }

        guard let export = MigrationDataExport.exportFromStore(at: store.sqliteURL, progressWindow: nil) else {
            XCTFail("Expected export to succeed")
            return
        }

        XCTAssertEqual(export.documents.count, 1)

        let container = NSPersistentContainer(name: "macaiDataModel", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]

        let loadExpectation = expectation(description: "Load in-memory store")
        container.loadPersistentStores { _, error in
            XCTAssertNil(error)
            loadExpectation.fulfill()
        }
        wait(for: [loadExpectation], timeout: 5)

        let importSuccess = export.importIntoContext(container.viewContext, progressWindow: nil)
        XCTAssertTrue(importSuccess)

        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "DocumentEntity")
        let results = try container.viewContext.fetch(fetchRequest)
        XCTAssertEqual(results.count, 1)

        let entity = results.first
        XCTAssertEqual(entity?.value(forKey: "filename") as? String, document.filename)
        XCTAssertEqual(entity?.value(forKey: "mimeType") as? String, document.mimeType)
        XCTAssertEqual(entity?.value(forKey: "fileData") as? Data, document.fileData)
    }

    func testLegacyStoreWithoutDocumentsExportsCleanly() throws {
        guard let legacyModel = loadModelVersion(named: "macaiDataModel 2", remapClassNames: true) else {
            throw XCTSkip("Legacy model not available in bundle")
        }

        let tempBase = FileManager.default.temporaryDirectory
            .appendingPathComponent("macai-legacy-\(UUID().uuidString)")
        let store = try createStore(baseURL: tempBase, model: legacyModel)
        defer { removeStoreFiles(at: store.baseURL) }

        guard let export = MigrationDataExport.exportFromStore(at: store.sqliteURL, progressWindow: nil) else {
            XCTFail("Expected export to succeed for legacy store")
            return
        }

        XCTAssertEqual(export.documents.count, 0)
    }

    // MARK: - Helpers

    private struct StoreURLs {
        let baseURL: URL
        let sqliteURL: URL
    }

    private struct DocumentSeed {
        let id: UUID
        let filename: String
        let mimeType: String
        let fileData: Data
    }

    private func clearMigrationDefaults() {
        for key in migrationKeys {
            userDefaults.removeObject(forKey: key)
        }
    }

    private func removeStoreFiles(at baseURL: URL) {
        let fm = FileManager.default
        for ext in ["sqlite", "sqlite-wal", "sqlite-shm"] {
            let url = baseURL.appendingPathExtension(ext)
            if fm.fileExists(atPath: url.path) {
                try? fm.removeItem(at: url)
            }
        }
    }

    private func createStore(
        containerName: String,
        model: NSManagedObjectModel,
        metadata: [String: Any]? = nil,
        documents: [DocumentSeed] = []
    ) throws -> StoreURLs {
        let baseURL = NSPersistentContainer.defaultDirectoryURL().appendingPathComponent(containerName)
        return try createStore(baseURL: baseURL, model: model, metadata: metadata, documents: documents)
    }

    private func createStore(
        baseURL: URL,
        model: NSManagedObjectModel,
        metadata: [String: Any]? = nil,
        documents: [DocumentSeed] = []
    ) throws -> StoreURLs {
        removeStoreFiles(at: baseURL)

        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let sqliteURL = baseURL.appendingPathExtension("sqlite")
        let options: [AnyHashable: Any] = [
            NSSQLitePragmasOption: ["journal_mode": "DELETE"],
        ]

        let store = try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: nil,
            at: sqliteURL,
            options: options
        )

        if !documents.isEmpty {
            let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            context.persistentStoreCoordinator = coordinator
            var saveError: Error?
            context.performAndWait {
                do {
                    for document in documents {
                        let entity = NSEntityDescription.insertNewObject(
                            forEntityName: "DocumentEntity",
                            into: context
                        )
                        entity.setValue(document.id, forKey: "id")
                        entity.setValue(document.filename, forKey: "filename")
                        entity.setValue(document.mimeType, forKey: "mimeType")
                        entity.setValue(document.fileData, forKey: "fileData")
                    }
                    try context.save()
                } catch {
                    saveError = error
                }
            }
            if let saveError = saveError {
                throw saveError
            }
        }

        if let metadata = metadata {
            var storeMetadata = coordinator.metadata(for: store)
            for (key, value) in metadata {
                storeMetadata[key] = value
            }
            coordinator.setMetadata(storeMetadata, for: store)
            try? NSPersistentStoreCoordinator.setMetadata(
                storeMetadata,
                forPersistentStoreOfType: NSSQLiteStoreType,
                at: sqliteURL,
                options: nil
            )
        }

        return StoreURLs(baseURL: baseURL, sqliteURL: sqliteURL)
    }

    private func createInvalidStore(containerName: String) throws -> StoreURLs {
        let baseURL = NSPersistentContainer.defaultDirectoryURL().appendingPathComponent(containerName)
        removeStoreFiles(at: baseURL)
        let sqliteURL = baseURL.appendingPathExtension("sqlite")
        try Data("invalid".utf8).write(to: sqliteURL, options: .atomic)
        return StoreURLs(baseURL: baseURL, sqliteURL: sqliteURL)
    }

    private func loadCurrentModel(remapClassNames: Bool = true) -> NSManagedObjectModel? {
        guard let momdURL = Bundle.main.url(forResource: "macaiDataModel", withExtension: "momd") else {
            return nil
        }
        let versionInfoURL = momdURL.appendingPathComponent("VersionInfo.plist")
        if let versionInfo = NSDictionary(contentsOf: versionInfoURL),
           let currentName = versionInfo["NSManagedObjectModel_CurrentVersionName"] as? String {
            let momURL = momdURL.appendingPathComponent(currentName).appendingPathExtension("mom")
            if FileManager.default.fileExists(atPath: momURL.path) {
                return loadModel(at: momURL, remapClassNames: remapClassNames)
            }
        }
        return loadModel(at: momdURL, remapClassNames: remapClassNames)
    }

    private func loadModelVersion(named name: String, remapClassNames: Bool) -> NSManagedObjectModel? {
        guard let momdURL = Bundle.main.url(forResource: "macaiDataModel", withExtension: "momd") else {
            return nil
        }
        let modelURL = momdURL.appendingPathComponent("\(name).mom")
        guard FileManager.default.fileExists(atPath: modelURL.path) else { return nil }
        return loadModel(at: modelURL, remapClassNames: remapClassNames)
    }

    private func loadModel(at url: URL, remapClassNames: Bool) -> NSManagedObjectModel? {
        guard let model = NSManagedObjectModel(contentsOf: url) else { return nil }
        guard remapClassNames else { return model }
        for entity in model.entities {
            entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        }
        return model
    }
}
