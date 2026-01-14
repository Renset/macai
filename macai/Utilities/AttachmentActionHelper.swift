//
//  AttachmentActionHelper.swift
//  macai
//
//  Created by Renat Notfullin on 10.01.2026.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

enum AttachmentActionHelper {
    static func copyImage(_ image: NSImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
    }

    static func saveImage(_ image: NSImage, suggestedName: String = "Image.jpg") {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png, .jpeg]
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = PreviewFileHelper.sanitizeFilename(suggestedName)
        savePanel.title = "Save Image"
        savePanel.message = "Choose where to save the image"

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            let ext = url.pathExtension.lowercased()
            let isPNG = ext == "png"

            guard
                let tiffData = image.tiffRepresentation,
                let bitmap = NSBitmapImageRep(data: tiffData),
                let imageData = isPNG
                    ? bitmap.representation(using: .png, properties: [:])
                    : bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
            else {
                return
            }

            let destinationURL: URL
            if url.pathExtension.isEmpty {
                destinationURL = url.appendingPathExtension(isPNG ? "png" : "jpg")
            } else {
                destinationURL = url
            }

            try? imageData.write(to: destinationURL)
        }
    }

    static func copyPDF(id: UUID, filename: String, data: Data) {
        let suggestedName = filename.isEmpty ? "Document.pdf" : filename
        let sanitized = PreviewFileHelper.sanitizeFilename(suggestedName)
        let baseName = URL(fileURLWithPath: sanitized).deletingPathExtension().lastPathComponent
        let name = "\(baseName).pdf"

        guard let url = PreviewFileHelper.previewURL(
            for: id,
            data: data,
            filename: name,
            defaultExtension: "pdf"
        ) else {
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
    }

    static func savePDF(filename: String, data: Data) {
        let suggestedName = filename.isEmpty ? "Document.pdf" : filename
        let sanitized = PreviewFileHelper.sanitizeFilename(suggestedName)
        let name = sanitized.lowercased().hasSuffix(".pdf") ? sanitized : "\(sanitized).pdf"

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pdf]
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = name
        savePanel.title = "Save PDF"
        savePanel.message = "Choose where to save the document"

        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            let destinationURL: URL
            if url.pathExtension.isEmpty {
                destinationURL = url.appendingPathExtension("pdf")
            } else {
                destinationURL = url
            }

            try? data.write(to: destinationURL, options: [.atomic])
        }
    }
}
