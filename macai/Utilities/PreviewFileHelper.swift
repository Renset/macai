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

    static func writeTemporaryFile(data: Data, filename: String, defaultExtension: String, id: UUID) -> URL? {
        guard !data.isEmpty else { return nil }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(previewDirectoryName, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        catch {
            return nil
        }

        // Use the ID to create a stable, unique filename for this attachment
        // This ensures that subsequent previews of the same attachment reuse the same file
        // preventing unnecessary disk I/O.
        let fileExtension = !filename.isEmpty ? (filename as NSString).pathExtension : defaultExtension
        let stableFilename = "\(id.uuidString).\(fileExtension.isEmpty ? defaultExtension : fileExtension)"
        let fileURL = directory.appendingPathComponent(stableFilename)

        // If the file already exists, return it immediately
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return fileURL
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
        // First check in-memory cache
        if let url = urlCache.object(forKey: id as NSUUID) as URL?,
           FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        
        // If not in memory, check if a file with this ID exists in the temp directory
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(previewDirectoryName, isDirectory: true)
        
        // We need to find any file that starts with the UUID, regardless of extension
        // Since we don't know the extension here easily without scanning, and the scan might be slow,
        // we might rely on the extensive writeTemporaryFile check.
        // However, `cachedPreviewURL` is often called when we suspect we might have it.
        // For now, let's rely on the explicit passed-in data flow or the memory cache.
        // But to be robust:
        
        do {
             let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
             if let match = contents.first(where: { $0.lastPathComponent.hasPrefix(id.uuidString) }) {
                 // Update memory cache
                 urlCache.setObject(match as NSURL, forKey: id as NSUUID)
                 return match
             }
        } catch {
            return nil
        }

        return nil
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
            defaultExtension: defaultExtension,
            id: id
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
