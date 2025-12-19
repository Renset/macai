import AppKit
import Foundation

enum ADCCredentialsAccessError: Error {
    case noBookmark
    case userCancelled
    case accessFailed
    case invalidBookmark
    case readFailed(String)
}

final class ADCCredentialsAccess {
    static func storedBookmarkURL() -> URL {
        let fm = FileManager.default
        do {
            let appSupportURL = try fm.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let bundleId = Bundle.main.bundleIdentifier ?? "macai"
            let folderURL = appSupportURL.appendingPathComponent(bundleId, isDirectory: true)
            if !fm.fileExists(atPath: folderURL.path) {
                try fm.createDirectory(at: folderURL, withIntermediateDirectories: true)
            }
            return folderURL.appendingPathComponent("adc.bookmark")
        }
        catch {
            // fallback to ~/Library/Application Support/<bundleId>/adc.bookmark without ensuring directory
            let fallback = URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library")
                .appendingPathComponent("Application Support")
                .appendingPathComponent(Bundle.main.bundleIdentifier ?? "macai")
                .appendingPathComponent("adc.bookmark")
            return fallback
        }
    }

    static func loadCredentialsData() throws -> Data {
        let bookmarkURL = storedBookmarkURL()
        let fm = FileManager.default
        guard fm.fileExists(atPath: bookmarkURL.path) else {
            throw ADCCredentialsAccessError.noBookmark
        }
        do {
            let bookmarkData = try Data(contentsOf: bookmarkURL)
            var stale = false
            let fileURL = try URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            if stale {
                // re-save fresh bookmark
                let freshBookmark = try fileURL.bookmarkData(
                    options: [.withSecurityScope],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                try freshBookmark.write(to: bookmarkURL)
            }
            guard fileURL.startAccessingSecurityScopedResource() else {
                throw ADCCredentialsAccessError.accessFailed
            }
            defer { fileURL.stopAccessingSecurityScopedResource() }
            do {
                return try Data(contentsOf: fileURL)
            }
            catch {
                throw ADCCredentialsAccessError.readFailed(error.localizedDescription)
            }
        }
        catch {
            if let localError = error as? ADCCredentialsAccessError {
                throw localError
            }
            throw ADCCredentialsAccessError.invalidBookmark
        }
    }

    static func promptAndStoreBookmark() async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.json]
                panel.canChooseFiles = true
                panel.canChooseDirectories = false
                panel.allowsMultipleSelection = false
                panel.title = "Select Google ADC Credentials"
                panel.directoryURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/gcloud")

                panel.begin { response in
                    guard response == .OK, let url = panel.url else {
                        continuation.resume(throwing: ADCCredentialsAccessError.userCancelled)
                        return
                    }
                    do {
                        let bookmarkData = try url.bookmarkData(
                            options: [.withSecurityScope],
                            includingResourceValuesForKeys: nil,
                            relativeTo: nil
                        )
                        let bookmarkURL = storedBookmarkURL()
                        try bookmarkData.write(to: bookmarkURL)
                        guard url.startAccessingSecurityScopedResource() else {
                            throw ADCCredentialsAccessError.accessFailed
                        }
                        defer { url.stopAccessingSecurityScopedResource() }
                        let data = try Data(contentsOf: url)
                        continuation.resume(returning: data)
                    }
                    catch {
                        continuation.resume(throwing: ADCCredentialsAccessError.readFailed(error.localizedDescription))
                    }
                }
            }
        }
    }
}
