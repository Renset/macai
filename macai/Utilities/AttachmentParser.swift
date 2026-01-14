//
//  AttachmentParser.swift
//  macai
//
//  Created by Renat on 08.01.2026.
//

import Foundation

struct AttachmentParser {
    static let imagePattern = "<image-uuid>(.*?)</image-uuid>"
    static let filePattern = "<file-uuid>(.*?)</file-uuid>"

    static func stripAttachments(from text: String) -> String {
        var cleaned = text
        cleaned = cleaned.replacingOccurrences(of: imagePattern, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: filePattern, with: "", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func extractImageUUIDs(from text: String) -> [UUID] {
        extractUUIDs(from: text, pattern: imagePattern)
    }

    static func extractFileUUIDs(from text: String) -> [UUID] {
        extractUUIDs(from: text, pattern: filePattern)
    }

    private static func extractUUIDs(from text: String, pattern: String) -> [UUID] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let nsString = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))

        return matches.compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            let uuidRange = match.range(at: 1)
            let uuidString = nsString.substring(with: uuidRange)
            return UUID(uuidString: uuidString)
        }
    }
}
