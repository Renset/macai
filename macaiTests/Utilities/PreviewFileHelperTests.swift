//
//  PreviewFileHelperTests.swift
//  macaiTests
//
//  Created by Codex on 2026-01-10
//

import XCTest
@testable import macai

final class PreviewFileHelperTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Clear temp directory if possible or just use unique IDs
    }
    
    func testPreviewURLWithSameIDReturnsSameFile() {
        let id = UUID()
        let data = "test data".data(using: .utf8)!
        let filename = "test.txt"
        
        guard let url1 = PreviewFileHelper.previewURL(for: id, data: data, filename: filename, defaultExtension: "txt") else {
            XCTFail("Failed to create first preview URL")
            return
        }
        
        let url2 = PreviewFileHelper.previewURL(for: id, data: data, filename: filename, defaultExtension: "txt")
        
        XCTAssertEqual(url1, url2, "Subsequent calls with the same ID should return the same URL")
        
        // Verify content
        let content = try? String(contentsOf: url1)
        XCTAssertEqual(content, "test data")
    }
    
    func testPreviewURLDoesNotOverwriteExistingFile() {
        let id = UUID()
        let data1 = "initial data".data(using: .utf8)!
        let filename = "overwrite.txt"
        
        guard let url1 = PreviewFileHelper.previewURL(for: id, data: data1, filename: filename, defaultExtension: "txt") else {
            XCTFail("Failed to create first preview URL")
            return
        }
        
        // Get modification date
        let attr1 = try? FileManager.default.attributesOfItem(atPath: url1.path)
        let date1 = attr1?[.modificationDate] as? Date
        
        // Wait a bit to ensure potential modification time difference
        Thread.sleep(forTimeInterval: 1.0)
        
        let data2 = "new data".data(using: .utf8)!
        // Use same ID, different data (simulating duplicate call)
        let url2 = PreviewFileHelper.previewURL(for: id, data: data2, filename: filename, defaultExtension: "txt")
        
        XCTAssertEqual(url1, url2)
        
        // Check that content is STILL "initial data"
        let content = try? String(contentsOf: url1)
        XCTAssertEqual(content, "initial data", "Should not overwrite existing file with same ID")
        
        let attr2 = try? FileManager.default.attributesOfItem(atPath: url1.path)
        let date2 = attr2?[.modificationDate] as? Date
        
        XCTAssertEqual(date1, date2, "Modification date should not change")
    }
    
    func testStableFilenameContainsID() {
        let id = UUID()
        let data = "data".data(using: .utf8)!
        
        guard let url = PreviewFileHelper.previewURL(for: id, data: data, filename: "myimage.jpg", defaultExtension: "jpg") else {
            XCTFail("Failed to create URL")
            return
        }
        
        XCTAssertTrue(url.lastPathComponent.contains(id.uuidString), "Filename should contain the ID to ensure uniqueness")
        XCTAssertTrue(url.pathExtension == "jpg", "Extension should be preserved")
    }
}
