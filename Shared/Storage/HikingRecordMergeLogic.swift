//
//  HikingRecordMergeLogic.swift
//  Shared
//

import Foundation

enum HikingRecordMergeLogic {
    /// 로컬·원격 기록을 ID 기준으로 병합합니다. 동일 ID는 `endedAt`이 더 최신인 쪽을 유지하고, 종료 시각 내림차순으로 정렬합니다.
    nonisolated static func mergedRecords(local: [SavedHikingSession], remote: [SavedHikingSession]) -> [SavedHikingSession] {
        var merged: [UUID: SavedHikingSession] = [:]
        for record in local + remote {
            if let existing = merged[record.id] {
                merged[record.id] = record.endedAt > existing.endedAt ? record : existing
            } else {
                merged[record.id] = record
            }
        }
        return merged.values.sorted { $0.endedAt > $1.endedAt }
    }

    /// 로컬·원격 tombstone을 ID 기준으로 병합합니다. 동일 ID는 `deletedAt`이 더 최신인 쪽을 유지합니다.
    nonisolated static func mergedTombstones(
        local: [HikingRecordTombstone],
        remote: [HikingRecordTombstone]
    ) -> [HikingRecordTombstone] {
        var merged: [UUID: HikingRecordTombstone] = [:]
        for tombstone in local + remote {
            if let existing = merged[tombstone.id] {
                merged[tombstone.id] = tombstone.deletedAt > existing.deletedAt ? tombstone : existing
            } else {
                merged[tombstone.id] = tombstone
            }
        }
        return merged.values.sorted { $0.deletedAt > $1.deletedAt }
    }

    /// 기록 병합 후 tombstone에 있는 ID는 제외합니다.
    nonisolated static func mergedRecords(
        local: [SavedHikingSession],
        remote: [SavedHikingSession],
        tombstones: [HikingRecordTombstone]
    ) -> [SavedHikingSession] {
        let tombstonedIDs = Set(tombstones.map(\.id))
        return mergedRecords(local: local, remote: remote)
            .filter { !tombstonedIDs.contains($0.id) }
    }
}
