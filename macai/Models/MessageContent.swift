//
//  MessageContent.swift
//  macai
//
//  Created by Renat on 03.04.2025
//

import CoreData
import Foundation
import SwiftUI

struct MessageContent {
    let content: String
    var imageAttachment: ImageAttachment?
    var fileAttachment: DocumentAttachment?

    init(text: String) {
        self.content = text
        self.imageAttachment = nil
        self.fileAttachment = nil
    }

    init(imageUUID: UUID) {
        self.content = "<image-uuid>\(imageUUID.uuidString)</image-uuid>"
        self.imageAttachment = nil
        self.fileAttachment = nil
    }

    init(imageAttachment: ImageAttachment) {
        self.content = "<image-uuid>\(imageAttachment.id.uuidString)</image-uuid>"
        self.imageAttachment = imageAttachment
        self.fileAttachment = nil
    }

    init(fileAttachment: DocumentAttachment) {
        self.content = "<file-uuid>\(fileAttachment.id.uuidString)</file-uuid>"
        self.imageAttachment = nil
        self.fileAttachment = fileAttachment
    }
}

/// Extension to convert between MessageContent array and string representation
extension Array where Element == MessageContent {
    func toString() -> String {
        map { $0.content }.joined(separator: "\n")
    }

    var textContent: String {
        map { AttachmentParser.stripAttachments(from: $0.content) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var imageUUIDs: [UUID] {
        compactMap { AttachmentParser.extractImageUUIDs(from: $0.content).first }
    }

    var fileUUIDs: [UUID] {
        compactMap { AttachmentParser.extractFileUUIDs(from: $0.content).first }
    }
}
extension String {
    func toMessageContents() -> [MessageContent] {
        [MessageContent(text: self)]
    }

    func extractImageUUIDs() -> [UUID] {
        AttachmentParser.extractImageUUIDs(from: self)
    }

    func extractFileUUIDs() -> [UUID] {
        AttachmentParser.extractFileUUIDs(from: self)
    }
}
