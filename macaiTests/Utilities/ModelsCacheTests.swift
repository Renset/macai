//
//  ModelsCacheTests.swift
//  macaiTests
//
//  Created by Renat Notfullin on 07.07.2026.
//

import XCTest

@testable import macai

final class ModelsCacheTests: XCTestCase {

    private var defaults: UserDefaults!
    private var cache: ModelsCache!
    private let suiteName = "ModelsCacheTests"

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        cache = ModelsCache(defaults: defaults)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        cache = nil
        try super.tearDownWithError()
    }

    func testReturnsNilWhenEmpty() {
        XCTAssertNil(cache.models(for: UUID()))
    }

    func testStoreAndRetrieve() {
        let serviceID = UUID()
        cache.store(["gpt-4o", "gpt-4o-mini"], for: serviceID)
        XCTAssertEqual(cache.models(for: serviceID), ["gpt-4o", "gpt-4o-mini"])
    }

    func testCachePersistsAcrossInstances() {
        let serviceID = UUID()
        cache.store(["claude-sonnet-5"], for: serviceID)

        let freshInstance = ModelsCache(defaults: defaults)
        XCTAssertEqual(freshInstance.models(for: serviceID), ["claude-sonnet-5"])
    }

    func testEmptyListIsNotStored() {
        let serviceID = UUID()
        cache.store([], for: serviceID)
        XCTAssertNil(cache.models(for: serviceID))
    }

    func testStoreOverwritesPreviousList() {
        let serviceID = UUID()
        cache.store(["old-model"], for: serviceID)
        cache.store(["new-model"], for: serviceID)
        XCTAssertEqual(cache.models(for: serviceID), ["new-model"])
    }

    func testCachesAreIsolatedPerService() {
        let first = UUID()
        let second = UUID()
        cache.store(["model-a"], for: first)
        cache.store(["model-b"], for: second)
        XCTAssertEqual(cache.models(for: first), ["model-a"])
        XCTAssertEqual(cache.models(for: second), ["model-b"])
    }

    func testRemoveModels() {
        let serviceID = UUID()
        cache.store(["model"], for: serviceID)
        cache.removeModels(for: serviceID)
        XCTAssertNil(cache.models(for: serviceID))
    }
}
