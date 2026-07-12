//
//  RequestMessagesTransformerTests.swift
//  macaiTests
//
//  Created by Renat Notfullin on 07.07.2026.
//

import XCTest

@testable import macai

final class RequestMessagesTransformerTests: XCTestCase {

    private let transformer = RequestMessagesTransformer()

    func testRoundTripPreservesMessages() {
        let messages: [[String: String]] = [
            ["role": "system", "content": "You are a helpful assistant."],
            ["role": "user", "content": "Hello, world! Ünïcödé 🚀"],
            ["role": "assistant", "content": "Hi there."],
        ]

        let archived = transformer.transformedValue(messages)
        XCTAssertNotNil(archived)

        let restored = transformer.reverseTransformedValue(archived) as? [[String: String]]
        XCTAssertEqual(restored, messages)
    }

    func testRoundTripPreservesEmptyArray() {
        let archived = transformer.transformedValue([[String: String]]())
        let restored = transformer.reverseTransformedValue(archived) as? [[String: String]]
        XCTAssertEqual(restored, [])
    }

    func testTransformedValueReturnsNilForUnsupportedInput() {
        XCTAssertNil(transformer.transformedValue("not an array"))
        XCTAssertNil(transformer.transformedValue(nil))
    }

    func testReverseTransformedValueReturnsNilForInvalidData() {
        XCTAssertNil(transformer.reverseTransformedValue("not data"))
        XCTAssertNil(transformer.reverseTransformedValue(nil))
        XCTAssertNil(transformer.reverseTransformedValue(Data([0x00, 0x01, 0x02])))
    }
}
