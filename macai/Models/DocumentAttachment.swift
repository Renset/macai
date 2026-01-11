//
//  DocumentAttachment.swift
//  macai
//
//  Created by Renat on 08.01.2026.
//

import CoreData
import Foundation
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

class DocumentAttachment: Identifiable, ObservableObject {
    var id: UUID = UUID()
    var url: URL?
    @Published var filename: String
    @Published var mimeType: String
    @Published var fileSize: Int?
    @Published var thumbnail: NSImage?
    @Published var isLoading: Bool = false
    @Published var isPreparingPreview: Bool = false
    @Published var previewUnavailable: Bool = false
    @Published var error: Error?

    internal var documentEntity: DocumentEntity?
    private var managedObjectContext: NSManagedObjectContext?
    private(set) var originalFileType: UTType
    private var fileData: Data?
    private var cachedPreviewURL: URL?
    private var pendingPreviewCompletions: [(URL?) -> Void] = []

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
                self.saveToEntity(fileData: data)
                self.generateThumbnail(from: data)
                self.preparePreviewURLIfNeeded(using: data)

                DispatchQueue.main.async {
                    self.fileSize = data.count
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
        guard let documentEntity = documentEntity else { return }
        guard let context = documentEntity.managedObjectContext ?? managedObjectContext else {
            DispatchQueue.main.async {
                self.error = NSError(
                    domain: "DocumentAttachment",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Missing Core Data context for document"]
                )
                self.isLoading = false
            }
            return
        }

        context.perform { [weak self] in
            guard let self else { return }
            let data = documentEntity.fileData
            let size = data?.count

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }

                if let data {
                    self.generateThumbnail(from: data)
                    self.preparePreviewURLIfNeeded(using: data)
                }

                DispatchQueue.main.async {
                    self.fileData = data
                    self.fileSize = size
                    self.isLoading = false
                }
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

    func previewURL() -> URL? {
        if let url, FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        if let cachedPreviewURL, FileManager.default.fileExists(atPath: cachedPreviewURL.path) {
            return cachedPreviewURL
        }

        if let cached = PreviewFileHelper.cachedPreviewURL(for: id) {
            cachedPreviewURL = cached
            return cached
        }

        return nil
    }

    func openPreview() {
        let title = filename.isEmpty ? "Document.pdf" : filename
        if let url = previewURL() {
            let request = QuickLookPreviewer.PreviewItemRequest(id: id, title: title, url: url)
            QuickLookPreviewer.shared.preview(requests: [request], selectedIndex: 0)
            return
        }

        let request = QuickLookPreviewer.PreviewItemRequest(id: id, title: title) { completion in
            self.fetchPreviewURL(completion: completion)
        }
        QuickLookPreviewer.shared.preview(requests: [request], selectedIndex: 0)
    }

    private func generateThumbnail(from data: Data) {
        guard let document = PDFDocument(data: data), let page = document.page(at: 0) else {
            DispatchQueue.main.async {
                self.previewUnavailable = true
            }
            return
        }
        let targetSize = NSSize(width: AppConstants.thumbnailSize, height: AppConstants.thumbnailSize)
        let image = page.thumbnail(of: targetSize, for: .mediaBox)

        DispatchQueue.main.async {
            self.thumbnail = image
            self.previewUnavailable = false
        }
    }

    private func preparePreviewURLIfNeeded(using data: Data) {
        guard cachedPreviewURL == nil else { return }
        guard url == nil else { return }
        let suggestedName = filename.isEmpty ? "Document.pdf" : filename
        let baseName = URL(fileURLWithPath: suggestedName).deletingPathExtension().lastPathComponent
        let name = "\(baseName).pdf"

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            guard let previewURL = PreviewFileHelper.previewURL(
                for: self.id,
                data: data,
                filename: name,
                defaultExtension: "pdf"
            ) else { return }

            DispatchQueue.main.async {
                self.cachedPreviewURL = previewURL
            }
        }
    }

    func fetchPreviewURL(completion: @escaping (URL?) -> Void) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in
                self?.fetchPreviewURL(completion: completion)
            }
            return
        }

        if let url = previewURL() {
            completion(url)
            return
        }

        if isPreparingPreview {
            pendingPreviewCompletions.append(completion)
            return
        }

        pendingPreviewCompletions.append(completion)

        guard let fileData else {
            let completions = pendingPreviewCompletions
            pendingPreviewCompletions.removeAll()
            completions.forEach { $0(nil) }
            return
        }

        isPreparingPreview = true

        let suggestedName = filename.isEmpty ? "Document.pdf" : filename
        let baseName = URL(fileURLWithPath: suggestedName).deletingPathExtension().lastPathComponent
        let name = "\(baseName).pdf"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let url = PreviewFileHelper.previewURL(
                for: self.id,
                data: fileData,
                filename: name,
                defaultExtension: "pdf"
            )

            DispatchQueue.main.async {
                self.isPreparingPreview = false
                if let url {
                    self.cachedPreviewURL = url
                }
                let completions = self.pendingPreviewCompletions
                self.pendingPreviewCompletions.removeAll()
                completions.forEach { $0(url) }
            }
        }
    }
}
