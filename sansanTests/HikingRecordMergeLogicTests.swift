//
//  HikingRecordMergeLogicTests.swift
//  sansanTests
//

import XCTest
@testable import sansan

final class HikingRecordMergeLogicTests: XCTestCase {
    private let older = Date(timeIntervalSince1970: 1_700_000_000)
    private let newer = Date(timeIntervalSince1970: 1_800_000_000)
    private let newest = Date(timeIntervalSince1970: 1_900_000_000)

    func testKeepsNewerEndedAtForSameID() {
        let id = UUID()
        let local = [makeRecord(id: id, endedAt: older, displayName: "local")]
        let remote = [makeRecord(id: id, endedAt: newer, displayName: "remote")]

        let merged = HikingRecordMergeLogic.mergedRecords(local: local, remote: remote)

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].endedAt, newer)
        XCTAssertEqual(merged[0].displayName, "remote")
    }

    func testCombinesUniqueIDsAndSortsByEndedAtDescending() {
        let idA = UUID()
        let idB = UUID()
        let local = [makeRecord(id: idA, endedAt: older)]
        let remote = [makeRecord(id: idB, endedAt: newest)]

        let merged = HikingRecordMergeLogic.mergedRecords(local: local, remote: remote)

        XCTAssertEqual(merged.map(\.id), [idB, idA])
    }

    func testEmptyInputsReturnEmpty() {
        XCTAssertTrue(HikingRecordMergeLogic.mergedRecords(local: [], remote: []).isEmpty)
    }

    func testMergedTombstonesKeepNewerDeletedAt() {
        let id = UUID()
        let olderTombstone = HikingRecordTombstone(id: id, deletedAt: older)
        let newerTombstone = HikingRecordTombstone(id: id, deletedAt: newer)

        let merged = HikingRecordMergeLogic.mergedTombstones(
            local: [olderTombstone],
            remote: [newerTombstone]
        )

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].deletedAt, newer)
    }

    func testMergedRecordsExcludeTombstonedIDs() {
        let deletedID = UUID()
        let activeID = UUID()
        let local = [makeRecord(id: deletedID, endedAt: older)]
        let remote = [makeRecord(id: activeID, endedAt: newest)]
        let tombstones = [HikingRecordTombstone(id: deletedID, deletedAt: newer)]

        let merged = HikingRecordMergeLogic.mergedRecords(
            local: local,
            remote: remote,
            tombstones: tombstones
        )

        XCTAssertEqual(merged.map(\.id), [activeID])
    }

    func testMergedRecordsExcludeTombstoneEvenWhenRemoteStillHasRecord() {
        let id = UUID()
        let local: [SavedHikingSession] = []
        let remote = [makeRecord(id: id, endedAt: newest)]
        let tombstones = [HikingRecordTombstone(id: id, deletedAt: newer)]

        let merged = HikingRecordMergeLogic.mergedRecords(
            local: local,
            remote: remote,
            tombstones: tombstones
        )

        XCTAssertTrue(merged.isEmpty)
    }

    private func makeRecord(id: UUID, endedAt: Date, displayName: String? = nil) -> SavedHikingSession {
        let session = HikingSessionData(sessionID: id, lastUpdated: endedAt)
        return SavedHikingSession(session: session, endedAt: endedAt, displayName: displayName)
    }
}
