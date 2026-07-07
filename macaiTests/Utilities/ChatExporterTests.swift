//
//  ChatExporterTests.swift
//  macaiTests
//
//  Created by Renat Notfullin on 07.07.2026.
//

import XCTest

@testable import macai

class ChatExporterTests: XCTestCase {

    private func message(_ body: String, isUser: Bool, timestamp: Date = Date(timeIntervalSince1970: 0))
        -> ChatExporter.ExportMessage
    {
        ChatExporter.ExportMessage(isUser: isUser, timestamp: timestamp, body: body)
    }

    // MARK: - Thinking block removal

    func testRemovingThinkingBlocksStripsClosedBlock() {
        let input = "<think>internal reasoning</think>\nThe answer is 42."
        let result = ChatExporter.removingThinkingBlocks(from: input)
        XCTAssertEqual(result.trimmingCharacters(in: .whitespacesAndNewlines), "The answer is 42.")
    }

    func testRemovingThinkingBlocksStripsMultilineBlock() {
        let input = "<think>line one\nline two\nline three</think>Answer"
        let result = ChatExporter.removingThinkingBlocks(from: input)
        XCTAssertEqual(result, "Answer")
    }

    func testRemovingThinkingBlocksStripsUnterminatedBlock() {
        let input = "Answer first.\n<think>streaming was cut off here"
        let result = ChatExporter.removingThinkingBlocks(from: input)
        XCTAssertEqual(result.trimmingCharacters(in: .whitespacesAndNewlines), "Answer first.")
    }

    func testRemovingThinkingBlocksLeavesPlainTextUntouched() {
        let input = "Nothing to strip here."
        XCTAssertEqual(ChatExporter.removingThinkingBlocks(from: input), input)
    }

    // MARK: - Attachment placeholders

    func testExportableBodyReplacesImagePlaceholder() {
        let uuid = UUID().uuidString
        let input = "Look at this:\n<image-uuid>\(uuid)</image-uuid>\nNice, right?"

        let markdown = ChatExporter.exportableBody(input, format: .markdown)
        XCTAssertEqual(markdown, "Look at this:\n*[Attached image]*\nNice, right?")

        let plain = ChatExporter.exportableBody(input, format: .plainText)
        XCTAssertEqual(plain, "Look at this:\n[Attached image]\nNice, right?")
    }

    func testExportableBodyReplacesFilePlaceholderWithResolvedName() {
        let uuid = UUID()
        let input = "<file-uuid>\(uuid.uuidString)</file-uuid>\nSummarize this document."

        let result = ChatExporter.exportableBody(input, format: .plainText) { resolvedUUID in
            XCTAssertEqual(resolvedUUID, uuid)
            return "report.pdf"
        }
        XCTAssertEqual(result, "[Attached file: report.pdf]\nSummarize this document.")
    }

    func testExportableBodyReplacesFilePlaceholderWithoutResolvedName() {
        let input = "<file-uuid>\(UUID().uuidString)</file-uuid> Question"
        let result = ChatExporter.exportableBody(input, format: .plainText) { _ in nil }
        XCTAssertEqual(result, "[Attached file] Question")
    }

    func testExportableBodyEmbedsImageAsDataURIInMarkdown() {
        let uuid = UUID()
        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let input = "Check this out:\n<image-uuid>\(uuid.uuidString)</image-uuid>"

        let result = ChatExporter.exportableBody(input, format: .markdown, imageResolver: { resolvedUUID in
            XCTAssertEqual(resolvedUUID, uuid)
            return ChatExporter.ExportImage(data: imageData, mimeType: "image/jpeg")
        })

        let expectedURI = "data:image/jpeg;base64,\(imageData.base64EncodedString())"
        XCTAssertEqual(result, "Check this out:\n![Attached image](\(expectedURI))")
    }

    func testExportableBodyDoesNotEmbedImageInPlainText() {
        let input = "<image-uuid>\(UUID().uuidString)</image-uuid> What is this?"
        let result = ChatExporter.exportableBody(input, format: .plainText, imageResolver: { _ in
            ChatExporter.ExportImage(data: Data([0x01]), mimeType: "image/png")
        })
        XCTAssertEqual(result, "[Attached image] What is this?")
    }

    func testExportableBodyFallsBackToMarkerWhenImageMissing() {
        let input = "<image-uuid>\(UUID().uuidString)</image-uuid>"
        let result = ChatExporter.exportableBody(input, format: .markdown, imageResolver: { _ in nil })
        XCTAssertEqual(result, "*[Attached image]*")
    }

    func testExportableBodyHandlesMultiplePlaceholdersInOneLine() {
        let input = "<image-uuid>\(UUID().uuidString)</image-uuid><image-uuid>\(UUID().uuidString)</image-uuid>Compare"
        let result = ChatExporter.exportableBody(input, format: .plainText)
        XCTAssertEqual(result, "[Attached image][Attached image]Compare")
    }

    func testExportableBodyReturnsNilForEmptyResult() {
        XCTAssertNil(ChatExporter.exportableBody("", format: .markdown))
        XCTAssertNil(ChatExporter.exportableBody("   \n  ", format: .markdown))
        XCTAssertNil(ChatExporter.exportableBody("<think>only reasoning</think>", format: .markdown))
    }

    func testExportableBodyKeepsMarkdownContentIntact() {
        let input = "```swift\nlet x = 1\n```\n**bold** and | a | table |"
        XCTAssertEqual(ChatExporter.exportableBody(input, format: .markdown), input)
    }

    // MARK: - Full rendering

    func testRenderMarkdownTranscript() {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let formattedTimestamp = ChatExporter.timestampFormatter.string(from: timestamp)
        let result = ChatExporter.render(
            chatName: "Test Chat",
            systemMessage: "You are a helpful assistant.",
            messages: [
                message("Hello!", isUser: true, timestamp: timestamp),
                message("Hi, how can I help?", isUser: false, timestamp: timestamp),
            ],
            format: .markdown
        )

        let expected = """
            # Test Chat

            **System prompt:**

            > You are a helpful assistant.

            ---

            #### User — \(formattedTimestamp)

            Hello!

            ---

            #### Assistant — \(formattedTimestamp)

            Hi, how can I help?

            """
        XCTAssertEqual(result, expected)
    }

    func testRenderPlainTextTranscript() {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let formattedTimestamp = ChatExporter.timestampFormatter.string(from: timestamp)
        let result = ChatExporter.render(
            chatName: "Test Chat",
            systemMessage: nil,
            messages: [
                message("Question?", isUser: true, timestamp: timestamp),
                message("Answer.", isUser: false, timestamp: timestamp),
            ],
            format: .plainText
        )

        let separator = String(repeating: "-", count: 40)
        let expected = """
            Test Chat
            =========

            \(separator)

            User — \(formattedTimestamp):
            Question?

            \(separator)

            Assistant — \(formattedTimestamp):
            Answer.

            """
        XCTAssertEqual(result, expected)
    }

    func testRenderSkipsEmptyMessages() {
        let result = ChatExporter.render(
            chatName: "Chat",
            systemMessage: nil,
            messages: [
                message("<think>reasoning only</think>", isUser: false),
                message("Visible", isUser: true),
            ],
            format: .plainText
        )
        XCTAssertFalse(result.contains("reasoning only"))
        XCTAssertTrue(result.contains("Visible"))
    }

    func testRenderMultilineSystemMessageIsFullyQuotedInMarkdown() {
        let result = ChatExporter.render(
            chatName: "Chat",
            systemMessage: "Line one\nLine two",
            messages: [],
            format: .markdown
        )
        XCTAssertTrue(result.contains("> Line one\n> Line two"))
    }

    func testRenderWithEmptyChatNameOmitsTitle() {
        let result = ChatExporter.render(
            chatName: "  ",
            systemMessage: nil,
            messages: [message("Hi", isUser: true)],
            format: .markdown
        )
        XCTAssertTrue(result.hasPrefix("#### User"))
        XCTAssertTrue(result.contains("Hi"))
    }
}
