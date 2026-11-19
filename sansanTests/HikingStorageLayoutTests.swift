//
//  HikingStorageLayoutTests.swift
//  sansanTests
//

import XCTest
@testable import sansan

final class HikingStorageLayoutTests: XCTestCase {
    func testPhotoFilenameIsStableAndHasNoSpaces() {
        let photoID = UUID(uuidString: "3AD14476-2650-4199-BB72-597981DC9CA8")!
        XCTAssertEqual(
            HikingStorageLayout.photoFilename(photoID: photoID),
            "3AD14476-2650-4199-BB72-597981DC9CA8.jpg"
        )
        XCTAssertFalse(HikingStorageLayout.photoFilename(photoID: photoID).contains(" "))
        XCTAssertEqual(HikingStorageLayout.snapshotFilename, "snapshot.png")
    }

    func testNormalizedPhotoFilenameStripsConflictIndex() {
        let uuid = "3AD14476-2650-4199-BB72-597981DC9CA8"
        XCTAssertEqual(
            HikingStorageLayout.normalizedPhotoFilename("\(uuid) 2.jpg"),
            "\(uuid).jpg"
        )
    }

    func testMigratesLegacySnapshotAndPhotoIntoRecordPackage() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sansan-layout-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let recordID = UUID()
        let photoID = UUID()
        let snapshots = root.appendingPathComponent("hiking_snapshots", isDirectory: true)
        let photos = root.appendingPathComponent("hiking_photos", isDirectory: true)
            .appendingPathComponent(recordID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)

        let legacyJSON = root.appendingPathComponent("saved_hiking_sessions.json")
        try Data("[]".utf8).write(to: legacyJSON)
        try Data("snapshot".utf8).write(
            to: snapshots.appendingPathComponent("\(recordID.uuidString).png")
        )
        try Data("photo".utf8).write(
            to: photos.appendingPathComponent("\(photoID.uuidString).jpg")
        )

        HikingStorageMigrator.migrateLegacyLayout(at: root)

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: HikingStorageLayout.recordsJSONURL(in: root).path
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyJSON.path))
        XCTAssertEqual(
            try String(
                contentsOf: HikingStorageLayout.snapshotURL(recordID: recordID, in: root),
                encoding: .utf8
            ),
            "snapshot"
        )
        XCTAssertEqual(
            try String(
                contentsOf: HikingStorageLayout.photoURL(
                    recordID: recordID,
                    photoID: photoID,
                    in: root
                ),
                encoding: .utf8
            ),
            "photo"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent("hiking_snapshots").path
            )
        )
    }

    func testReconcileRemovesOrphanRecordPackage() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sansan-reconcile-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let keptID = UUID()
        let orphanID = UUID()
        try FileManager.default.createDirectory(
            at: HikingStorageLayout.recordDirectory(recordID: keptID, in: root),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: HikingStorageLayout.recordDirectory(recordID: orphanID, in: root),
            withIntermediateDirectories: true
        )
        try Data("keep".utf8).write(to: HikingStorageLayout.snapshotURL(recordID: keptID, in: root))
        try Data("drop".utf8).write(to: HikingStorageLayout.snapshotURL(recordID: orphanID, in: root))

        HikingStorageMigrator.reconcile(
            at: root,
            recordIDs: [keptID],
            photoIDsByRecord: [:],
            extraProtectedIDs: []
        )

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: HikingStorageLayout.snapshotURL(recordID: keptID, in: root).path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: HikingStorageLayout.recordDirectory(recordID: orphanID, in: root).path
            )
        )
    }

    func testMigratesProfileAssetsFromDocumentsRoot() throws {
        let documents = FileManager.default.temporaryDirectory
            .appendingPathComponent("sansan-docs-\(UUID().uuidString)", isDirectory: true)
        let userRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("sansan-user-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: documents)
            try? FileManager.default.removeItem(at: userRoot)
        }

        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: userRoot, withIntermediateDirectories: true)
        try Data("photo".utf8).write(
            to: documents.appendingPathComponent(HikingStorageLayout.profilePhotoFilename)
        )
        try Data("avatar".utf8).write(
            to: documents.appendingPathComponent(HikingStorageLayout.Legacy.avatarFilename)
        )

        HikingStorageMigrator.migrateProfileAssets(from: documents, to: userRoot)

        XCTAssertEqual(
            try String(contentsOf: HikingStorageLayout.profilePhotoURL(in: userRoot), encoding: .utf8),
            "photo"
        )
        XCTAssertEqual(
            try String(contentsOf: HikingStorageLayout.avatarURL(in: userRoot), encoding: .utf8),
            "avatar"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: documents.appendingPathComponent(HikingStorageLayout.profilePhotoFilename).path
            )
        )
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: documents.appendingPathComponent(HikingStorageLayout.Legacy.avatarFilename).path
            )
        )
    }
}
