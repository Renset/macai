//
//  PDFHandlingTests.swift
//  macaiTests
//
//  Created by Renat Notfullin on 10.01.2026
//

import XCTest
@testable import macai

final class PDFHandlingTests: XCTestCase {
    private func fileURL(named name: String) -> URL {
        let baseURL = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return baseURL
            .appendingPathComponent("Files")
            .appendingPathComponent(name)
    }

    private func waitForAttachment(_ attachment: DocumentAttachment, timeout: TimeInterval = 5.0) {
        let expectation = XCTestExpectation(description: "Wait for attachment load")
        let start = Date()

        func poll() {
            if !attachment.isLoading {
                expectation.fulfill()
                return
            }
            if Date().timeIntervalSince(start) > timeout {
                expectation.fulfill()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: poll)
        }

        poll()
        wait(for: [expectation], timeout: timeout + 1.0)
    }

    func testNormalPDFLoadsAndGeneratesPreview() {
        let url = fileURL(named: "lorem-ipsum.pdf")
        let attachment = DocumentAttachment(url: url)

        waitForAttachment(attachment)

        XCTAssertNil(attachment.error)
        XCTAssertTrue(attachment.isReadyForUpload)
        XCTAssertFalse(attachment.previewUnavailable)
        XCTAssertNotNil(attachment.thumbnail)
    }

    func testCorruptedPDFDoesNotCrashAndRemainsSendable() {
        let url = fileURL(named: "lorem-ipsum-corrupted.pdf")
        let attachment = DocumentAttachment(url: url)

        waitForAttachment(attachment)

        XCTAssertNil(attachment.error)
        XCTAssertTrue(attachment.isReadyForUpload)
    }

    func testEncryptedPDFDoesNotCrashAndRemainsSendable() {
        let url = fileURL(named: "lorem-ipsum-password.pdf")
        let attachment = DocumentAttachment(url: url)

        waitForAttachment(attachment)

        XCTAssertNil(attachment.error)
        XCTAssertTrue(attachment.isReadyForUpload)
    }
}
