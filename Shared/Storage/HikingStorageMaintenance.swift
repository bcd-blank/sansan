//
//  HikingStorageMaintenance.swift
//  Shared
//

#if os(iOS)

import Foundation

/// 중복 사본 정리·레이아웃 이전·고아 삭제를 백그라운드에서 한 번만 실행합니다.
enum HikingStorageMaintenance: Sendable {
    nonisolated private static let lock = NSLock()
    nonisolated(unsafe) private static var isRunning = false

    nonisolated static func run(
        at userRoot: URL,
        recordIDs: Set<UUID> = [],
        photoIDsByRecord: [UUID: Set<UUID>] = [:],
        extraProtectedIDs: Set<UUID> = [],
        deleteOrphans: Bool = false
    ) {
        lock.lock()
        if isRunning {
            lock.unlock()
            return
        }
        isRunning = true
        lock.unlock()
        defer {
            lock.lock()
            isRunning = false
            lock.unlock()
        }

        HikingRecordAssetCleaner.purgeNumberedConflictCopies(at: userRoot)
        HikingStorageMigrator.migrateLegacyLayout(at: userRoot)
        if deleteOrphans {
            HikingStorageMigrator.reconcile(
                at: userRoot,
                recordIDs: recordIDs,
                photoIDsByRecord: photoIDsByRecord,
                extraProtectedIDs: extraProtectedIDs
            )
        }
    }
}

#endif
