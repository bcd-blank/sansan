//
//  HikingRecordTombstone.swift
//  Shared
//

import Foundation

/// 삭제된 등산 기록 ID. iCloud 병합 시 동일 기록이 다시 나타나지 않도록 합니다.
nonisolated struct HikingRecordTombstone: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let deletedAt: Date

    init(id: UUID, deletedAt: Date = Date()) {
        self.id = id
        self.deletedAt = deletedAt
    }
}
