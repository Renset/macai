//
//  DocumentAttachment.swift
//  macai
//
//  Created by Renat on 08.01.2026.
//

import CoreData
import Foundation
import SwiftUI
import UniformTypeIdentifiers

class DocumentAttachment: Identifiable, ObservableObject {
    var id: UUID = UUID()
    var url: URL?
    @Published var filename: String
    @Published var mimeType: String
    @Published var fileSize: Int?
    @Published var isLoading: Bool = false
    @Published var error: Error?

    internal var documentEntity: DocumentEntity?
    private var managedObjectContext: NSManagedObjectContext?
    private(set) var originalFileType: UTType
    private var fileData: Data?

    var isReadyForUpload: Bool {
        guard !isLoading, error == nil else { return false }
        guard let data = fileData, !data.isEmpty else { return false }
        return true
    }

    init(url: URL, context: NSManagedObjectContext? = nil) {
        let resolvedFilename = url.lastPathComponent
        let resolvedType = url.getUTType() ?? .data
        let resolvedMime = resolvedType.preferredMIMEType ?? "application/octet-stream"

        self.url = url
        self.filename = resolvedFilename
        self.originalFileType = resolvedType
        self.mimeType = resolvedMime
        self.managedObjectContext = context
        self.loadDocument()
    }

    init(documentEntity: DocumentEntity) {
        let resolvedFilename = documentEntity.filename ?? "Document"
        let resolvedMime = documentEntity.mimeType ?? "application/octet-stream"
        let resolvedType = UTType(filenameExtension: URL(fileURLWithPath: resolvedFilename).pathExtension) ?? .data

        self.documentEntity = documentEntity
        self.id = documentEntity.id ?? UUID()
        self.filename = resolvedFilename
        self.mimeType = resolvedMime
        self.originalFileType = resolvedType
        self.loadFromEntity()
    }

    private func loadDocument() {
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, let url = self.url else { return }

            do {
                guard self.originalFileType.conforms(to: .pdf) else {
                    throw NSError(
                        domain: "DocumentAttachment",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Unsupported file type"]
                    )
                }

                let data = try Data(contentsOf: url)
                guard !data.isEmpty else {
                    throw NSError(
                        domain: "DocumentAttachment",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to read file data"]
                    )
                }

                self.fileData = data
                self.fileSize = data.count
                self.saveToEntity(fileData: data)

                DispatchQueue.main.async {
                    self.isLoading = false
                }
            }
            catch {
                DispatchQueue.main.async {
                    self.error = error
                    self.isLoading = false
                }
            }
        }
    }

    private func loadFromEntity() {
        isLoading = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, let documentEntity = self.documentEntity else { return }

            let data = documentEntity.fileData
            let size = data?.count

            DispatchQueue.main.async {
                self.fileData = data
                self.fileSize = size
                self.isLoading = false
            }
        }
    }

    func saveToEntity(
        fileData: Data? = nil,
        context: NSManagedObjectContext? = nil,
        waitForCompletion: Bool = false
    ) {
        guard let contextToUse = context ?? managedObjectContext else { return }

        if context != nil {
            self.managedObjectContext = context
        }

        let persist: (Data) -> Void = { [weak self] data in
            guard let self = self else { return }
            guard !data.isEmpty else { return }

            contextToUse.performAndWait {
                if self.documentEntity == nil {
                    let newEntity = DocumentEntity(context: contextToUse)
                    newEntity.id = self.id
                    self.documentEntity = newEntity
                }

                self.documentEntity?.filename = self.filename
                self.documentEntity?.mimeType = self.mimeType
                self.documentEntity?.fileData = data

                contextToUse.saveWithRetry(attempts: 1)
            }
        }

        let payload = fileData ?? self.fileData
        guard let payload else { return }

        if waitForCompletion {
            persist(payload)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            persist(payload)
        }
    }

    func toBase64DataURL() -> String? {
        guard let fileData = fileData else { return nil }
        let base64 = fileData.base64EncodedString()
        return "data:\(mimeType);base64,\(base64)"
    }
}
