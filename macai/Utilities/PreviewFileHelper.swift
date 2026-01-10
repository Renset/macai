//
//  PreviewFileHelper.swift
//  macai
//
//  Created by Codex on 2026-01-09
//

import Foundation

enum PreviewFileHelper {
    private static let previewDirectoryName = "macai-previews"
    private static let urlCache = NSCache<NSUUID, NSURL>()

    static func writeTemporaryFile(data: Data, filename: String, defaultExtension: String) -> URL? {
        guard !data.isEmpty else { return nil }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(previewDirectoryName, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        catch {
            return nil
        }

        let sanitizedName = sanitizeFilename(filename.isEmpty ? "file" : filename)
        var fileURL = directory.appendingPathComponent(sanitizedName)

        if fileURL.pathExtension.isEmpty {
            fileURL.appendPathExtension(defaultExtension)
        }

        if FileManager.default.fileExists(atPath: fileURL.path) {
            let base = fileURL.deletingPathExtension().lastPathComponent
            let ext = fileURL.pathExtension
            fileURL = directory
                .appendingPathComponent("\(base)-\(UUID().uuidString)")
                .appendingPathExtension(ext)
        }

        do {
            try data.write(to: fileURL, options: [.atomic])
        }
        catch {
            return nil
        }

        return fileURL
    }

    static func cachedPreviewURL(for id: UUID) -> URL? {
        guard let url = urlCache.object(forKey: id as NSUUID) as URL? else { return nil }
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func previewURL(
        for id: UUID,
        data: Data,
        filename: String,
        defaultExtension: String
    ) -> URL? {
        if let cached = cachedPreviewURL(for: id) {
            return cached
        }

        guard let url = writeTemporaryFile(
            data: data,
            filename: filename,
            defaultExtension: defaultExtension
        ) else {
            return nil
        }

        urlCache.setObject(url as NSURL, forKey: id as NSUUID)
        return url
    }

    static func sanitizeFilename(_ name: String) -> String {
        var sanitized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.isEmpty {
            return "file"
        }

        let forbidden = CharacterSet(charactersIn: "/:")
            .union(.controlCharacters)
        sanitized.unicodeScalars.removeAll { forbidden.contains($0) }
        return sanitized.isEmpty ? "file" : sanitized
    }
}
