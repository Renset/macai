//
//  MessageManagerTests.swift
//  macaiTests
//
//  Created by Renat Notfullin on 07.07.2026.
//

import XCTest

@testable import macai

final class MessageManagerTests: XCTestCase {

    // MARK: - sanitizeChatName

    func testSanitizeChatNameExtractsBoldMarkdownName() {
        XCTAssertEqual(MessageManager.sanitizeChatName("**Trip Planning**"), "Trip Planning")
        XCTAssertEqual(
            MessageManager.sanitizeChatName("Here is a name:\n**Swift Questions**\nHope you like it"),
            "Swift Questions"
        )
    }

    func testSanitizeChatNameUsesLastNonEmptyLine() {
        let reasoningStyleReply = """
            Let me think of a good name.

            Weather Chat
            """
        XCTAssertEqual(MessageManager.sanitizeChatName(reasoningStyleReply), "Weather Chat")
    }

    func testSanitizeChatNameTrimsWhitespace() {
        XCTAssertEqual(MessageManager.sanitizeChatName("  Simple Name  "), "Simple Name")
    }

    func testSanitizeChatNamePlainSingleLine() {
        XCTAssertEqual(MessageManager.sanitizeChatName("Grocery List Help"), "Grocery List Help")
    }
}
