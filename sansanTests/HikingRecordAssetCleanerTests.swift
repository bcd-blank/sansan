//
//  HikingRecordAssetCleanerTests.swift
//  sansanTests
//

import XCTest
@testable import sansan

final class HikingRecordAssetCleanerTests: XCTestCase {
    func testDetectsNumberedICloudCopies() {
        let uuid = "3AD14476-2650-4199-BB72-597981DC9CA8"
        XCTAssertTrue(HikingRecordAssetCleaner.isNumberedConflictCopy("\(uuid) 2.png"))
        XCTAssertTrue(HikingRecordAssetCleaner.isNumberedConflictCopy("\(uuid) 98.jpg"))
        XCTAssertTrue(HikingRecordAssetCleaner.isNumberedConflictCopy("\(uuid) 10.jpg.icloud"))
        XCTAssertTrue(HikingRecordAssetCleaner.isNumberedConflictCopy("saved_hiking_sessions 2.json"))
        XCTAssertTrue(HikingRecordAssetCleaner.isNumberedConflictCopy("records 2.json"))
        XCTAssertTrue(HikingRecordAssetCleaner.isNumberedConflictCopy("snapshot 2.png"))
        XCTAssertFalse(HikingRecordAssetCleaner.isNumberedConflictCopy("\(uuid).png"))
        XCTAssertFalse(HikingRecordAssetCleaner.isNumberedConflictCopy("\(uuid).jpg"))
        XCTAssertFalse(HikingRecordAssetCleaner.isNumberedConflictCopy("saved_hiking_sessions.json"))
        XCTAssertFalse(HikingRecordAssetCleaner.isNumberedConflictCopy("records.json"))
        XCTAssertFalse(HikingRecordAssetCleaner.isNumberedConflictCopy("snapshot.png"))
        XCTAssertFalse(HikingRecordAssetCleaner.isNumberedConflictCopy("profile.jpg"))
    }

    func testCanonicalFilenameStripsCopyIndex() {
        let uuid = "3AD14476-2650-4199-BB72-597981DC9CA8"
        XCTAssertEqual(
            HikingRecordAssetCleaner.canonicalFilename(from: "\(uuid) 2.png"),
            "\(uuid).png"
        )
        XCTAssertEqual(
            HikingRecordAssetCleaner.canonicalFilename(from: "saved_hiking_sessions 3.json.icloud"),
            "saved_hiking_sessions.json"
        )
        XCTAssertNil(HikingRecordAssetCleaner.canonicalFilename(from: "\(uuid).png"))
    }

    func testPurgeRemovesNumberedCopiesWhenCanonicalExists() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sansan-conflict-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let uuid = UUID().uuidString
        let canonical = directory.appendingPathComponent("\(uuid).png")
        let copy2 = directory.appendingPathComponent("\(uuid) 2.png")
        let copy3 = directory.appendingPathComponent("\(uuid) 3.png")
        try Data("canonical".utf8).write(to: canonical)
        try Data("copy2".utf8).write(to: copy2)
        try Data("copy3".utf8).write(to: copy3)

        HikingRecordAssetCleaner.purgeNumberedConflictCopies(of: "\(uuid).png", in: directory)

        XCTAssertTrue(FileManager.default.fileExists(atPath: canonical.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy2.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy3.path))
        XCTAssertEqual(try String(contentsOf: canonical, encoding: .utf8), "canonical")
    }

    func testPurgePromotesLargestCopyWhenCanonicalIsMissing() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sansan-promote-\(UUID().uuidString)", isDirectory: true)
        let snapshots = root.appendingPathComponent("hiking_snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let uuid = UUID().uuidString
        let small = snapshots.appendingPathComponent("\(uuid) 2.png")
        let large = snapshots.appendingPathComponent("\(uuid) 5.png")
        try Data("tiny".utf8).write(to: small)
        try Data(repeating: 0x61, count: 4096).write(to: large)

        HikingRecordAssetCleaner.purgeNumberedConflictCopies(at: root)

        let canonical = snapshots.appendingPathComponent("\(uuid).png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: canonical.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: small.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: large.path))
        XCTAssertEqual(try Data(contentsOf: canonical).count, 4096)
    }
}
