//
//  HikingRecordTombstoneStore.swift
//  Shared
//

#if os(iOS)

import Foundation

enum HikingRecordTombstoneStore {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func load() -> [HikingRecordTombstone] {
        guard let url = UserDataPaths.existingTombstonesFileURL,
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let tombstones = try? decoder.decode([HikingRecordTombstone].self, from: data) else {
            return []
        }
        return tombstones
    }

    static func save(_ tombstones: [HikingRecordTombstone]) {
        do {
            let data = try encoder.encode(tombstones)
            try data.write(to: UserDataPaths.tombstonesFileURL, options: [.atomic])
            if let root = UserDataPaths.activeUserRoot {
                HikingStorageMigrator.removeLegacyJSONFiles(at: root)
            }
            ICloudRecordSync.shared.schedulePush()
        } catch {
            // tombstone 저장 실패 시 기록 삭제 자체는 이미 반영됨.
        }
    }

    static func append(ids: [UUID], deletedAt: Date = Date()) {
        guard !ids.isEmpty else { return }
        let incoming = ids.map { HikingRecordTombstone(id: $0, deletedAt: deletedAt) }
        let merged = HikingRecordMergeLogic.mergedTombstones(local: load(), remote: incoming)
        save(merged)
    }
}

#endif
