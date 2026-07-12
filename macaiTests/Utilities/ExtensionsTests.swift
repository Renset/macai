//
//  ExtensionsTests.swift
//  macaiTests
//
//  Created by Renat Notfullin on 07.07.2026.
//

import XCTest

@testable import macai

final class ExtensionsTests: XCTestCase {

    // MARK: - Double.toInt16

    func testToInt16WithinBounds() {
        XCTAssertEqual(Double(0).toInt16(), 0)
        XCTAssertEqual(Double(15).toInt16(), 15)
        XCTAssertEqual(Double(-20).toInt16(), -20)
        XCTAssertEqual(Double(Int16.max).toInt16(), Int16.max)
        XCTAssertEqual(Double(Int16.min).toInt16(), Int16.min)
    }

    func testToInt16OutOfBoundsReturnsNil() {
        XCTAssertNil(Double(Int16.max) .advanced(by: 1).toInt16())
        XCTAssertNil(Double(Int16.min).advanced(by: -1).toInt16())
        XCTAssertNil(Double.greatestFiniteMagnitude.toInt16())
    }

    // MARK: - Float.roundedToOneDecimal

    func testRoundedToOneDecimal() {
        XCTAssertEqual(Float(0.749).roundedToOneDecimal(), 0.7)
        XCTAssertEqual(Float(0.75).roundedToOneDecimal(), 0.8)
        XCTAssertEqual(Float(1.0).roundedToOneDecimal(), 1.0)
        // .rounded() rounds away from zero at the midpoint
        XCTAssertEqual(Float(-0.35).roundedToOneDecimal(), -0.4, accuracy: 0.0001)
    }

    // MARK: - SHA256

    func testStringSHA256KnownVector() {
        XCTAssertEqual(
            "abc".sha256(),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        XCTAssertEqual(
            "".sha256(),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
    }
}
