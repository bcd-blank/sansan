//
//  HikingStorageMigrator.swift
//  Shared
//

#if os(iOS)

import Foundation

enum HikingStorageMigrator: Sendable {
    /// JSON 이름만 먼저 맞춰 기록 로드가 빈 목록으로 떨어지지 않게 합니다.
    nonisolated static func migrateJSONFiles(at userRoot: URL) {
        moveIfNeeded(
            from: userRoot.appendingPathComponent(HikingStorageLayout.Legacy.recordsJSONName),
            to: HikingStorageLayout.recordsJSONURL(in: userRoot)
        )
        moveIfNeeded(
            from: userRoot.appendingPathComponent(HikingStorageLayout.Legacy.tombstonesJSONName),
            to: HikingStorageLayout.tombstonesJSONURL(in: userRoot)
        )
    }

    /// Documents 루트에 남은 프로필 사진·아바타를 사용자 폴더로 옮깁니다.
    nonisolated static func migrateProfileAssets(from documentsDirectory: URL, to userRoot: URL) {
        moveIfNeeded(
            from: documentsDirectory.appendingPathComponent(HikingStorageLayout.profilePhotoFilename),
            to: HikingStorageLayout.profilePhotoURL(in: userRoot)
        )
        moveIfNeeded(
            from: documentsDirectory.appendingPathComponent(HikingStorageLayout.avatarFilename),
            to: HikingStorageLayout.avatarURL(in: userRoot)
        )
        moveIfNeeded(
            from: documentsDirectory.appendingPathComponent(HikingStorageLayout.Legacy.avatarFilename),
            to: HikingStorageLayout.avatarURL(in: userRoot)
        )
        migrateAvatar(at: userRoot)
    }

    /// 구 폴더(`hiking_snapshots` 등)를 `records/{id}/` 패키지로 옮깁니다.
    nonisolated static func migrateLegacyLayout(at userRoot: URL) {
        migrateJSONFiles(at: userRoot)
        migrateAvatar(at: userRoot)
        migrateSnapshots(at: userRoot)
        migratePhotos(at: userRoot)
        removeEmptyDirectory(
            userRoot.appendingPathComponent(HikingStorageLayout.Legacy.snapshotsDirectoryName, isDirectory: true)
        )
        removeEmptyDirectory(
            userRoot.appendingPathComponent(HikingStorageLayout.Legacy.photosDirectoryName, isDirectory: true)
        )
    }

    nonisolated static func removeLegacyJSONFiles(at userRoot: URL) {
        let fileManager = FileManager.default
        let legacyRecords = userRoot.appendingPathComponent(HikingStorageLayout.Legacy.recordsJSONName)
        let canonicalRecords = HikingStorageLayout.recordsJSONURL(in: userRoot)
        if fileManager.fileExists(atPath: canonicalRecords.path) {
            try? fileManager.removeItem(at: legacyRecords)
        }
        let legacyTombstones = userRoot.appendingPathComponent(HikingStorageLayout.Legacy.tombstonesJSONName)
        let canonicalTombstones = HikingStorageLayout.tombstonesJSONURL(in: userRoot)
        if fileManager.fileExists(atPath: canonicalTombstones.path) {
            try? fileManager.removeItem(at: legacyTombstones)
        }
    }

    /// JSON에 없는 기록 폴더·사진·구 경로 고아 파일을 삭제합니다.
    nonisolated static func reconcile(
        at userRoot: URL,
        recordIDs: Set<UUID>,
        photoIDsByRecord: [UUID: Set<UUID>],
        extraProtectedIDs: Set<UUID>
    ) {
        let kept = recordIDs.union(extraProtectedIDs)
        let fileManager = FileManager.default
        let recordsRoot = HikingStorageLayout.recordsDirectory(in: userRoot)

        if let packages = try? fileManager.contentsOfDirectory(
            at: recordsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for package in packages {
                let isDirectory = (try? package.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                guard isDirectory, let recordID = UUID(uuidString: package.lastPathComponent) else {
                    continue
                }
                if !kept.contains(recordID) {
                    try? fileManager.removeItem(at: package)
                    continue
                }
                let allowedPhotos = photoIDsByRecord[recordID] ?? []
                reconcilePhotos(
                    in: HikingStorageLayout.photosDirectory(recordID: recordID, in: userRoot),
                    allowedIDs: extraProtectedIDs.contains(recordID) ? nil : allowedPhotos
                )
            }
        }

        reconcileLegacySnapshots(at: userRoot, keptIDs: kept)
        reconcileLegacyPhotoSessions(at: userRoot, keptIDs: kept)
    }

    nonisolated private static func migrateAvatar(at userRoot: URL) {
        moveIfNeeded(
            from: userRoot.appendingPathComponent(HikingStorageLayout.Legacy.avatarFilename),
            to: HikingStorageLayout.avatarURL(in: userRoot)
        )
    }

    nonisolated private static func migrateSnapshots(at userRoot: URL) {
        let legacy = userRoot.appendingPathComponent(
            HikingStorageLayout.Legacy.snapshotsDirectoryName,
            isDirectory: true
        )
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: legacy,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for item in items {
            if (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { continue }
            if HikingRecordAssetCleaner.shouldSkipDuringSync(item.lastPathComponent),
               !HikingRecordAssetCleaner.isNumberedConflictCopy(item.lastPathComponent) {
                continue
            }
            guard let recordID = HikingStorageLayout.uuid(fromFilename: item.lastPathComponent) else {
                continue
            }
            let destination = HikingStorageLayout.snapshotURL(recordID: recordID, in: userRoot)
            moveIfNeeded(from: item, to: destination)
        }
    }

    nonisolated private static func migratePhotos(at userRoot: URL) {
        let legacyRoot = userRoot.appendingPathComponent(
            HikingStorageLayout.Legacy.photosDirectoryName,
            isDirectory: true
        )
        guard let sessions = try? FileManager.default.contentsOfDirectory(
            at: legacyRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for session in sessions {
            let isDirectory = (try? session.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            guard isDirectory, let recordID = UUID(uuidString: session.lastPathComponent) else { continue }
            guard let photos = try? FileManager.default.contentsOfDirectory(
                at: session,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for photo in photos {
                if (try? photo.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { continue }
                if HikingRecordAssetCleaner.shouldSkipDuringSync(photo.lastPathComponent),
                   !HikingRecordAssetCleaner.isNumberedConflictCopy(photo.lastPathComponent) {
                    continue
                }
                let destination = HikingStorageLayout.photoURL(
                    recordID: recordID,
                    filename: photo.lastPathComponent,
                    in: userRoot
                )
                moveIfNeeded(from: photo, to: destination)
            }
            removeEmptyDirectory(session)
        }
    }

    nonisolated private static func reconcilePhotos(in directory: URL, allowedIDs: Set<UUID>?) {
        guard let allowedIDs else { return }
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        for item in items {
            guard let photoID = HikingStorageLayout.uuid(fromFilename: item.lastPathComponent) else {
                try? FileManager.default.removeItem(at: item)
                continue
            }
            if !allowedIDs.contains(photoID) {
                try? FileManager.default.removeItem(at: item)
            }
        }
        removeEmptyDirectory(directory)
    }

    nonisolated private static func reconcileLegacySnapshots(at userRoot: URL, keptIDs: Set<UUID>) {
        let legacy = userRoot.appendingPathComponent(
            HikingStorageLayout.Legacy.snapshotsDirectoryName,
            isDirectory: true
        )
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: legacy,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for item in items {
            if (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { continue }
            guard let recordID = HikingStorageLayout.uuid(fromFilename: item.lastPathComponent) else {
                try? FileManager.default.removeItem(at: item)
                continue
            }
            if !keptIDs.contains(recordID) {
                try? FileManager.default.removeItem(at: item)
            }
        }
        removeEmptyDirectory(legacy)
    }

    nonisolated private static func reconcileLegacyPhotoSessions(at userRoot: URL, keptIDs: Set<UUID>) {
        let legacy = userRoot.appendingPathComponent(
            HikingStorageLayout.Legacy.photosDirectoryName,
            isDirectory: true
        )
        guard let sessions = try? FileManager.default.contentsOfDirectory(
            at: legacy,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for session in sessions {
            let isDirectory = (try? session.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            guard isDirectory else {
                try? FileManager.default.removeItem(at: session)
                continue
            }
            guard let recordID = UUID(uuidString: session.lastPathComponent), keptIDs.contains(recordID) else {
                try? FileManager.default.removeItem(at: session)
                continue
            }
        }
        removeEmptyDirectory(legacy)
    }

    nonisolated private static func moveIfNeeded(from source: URL, to destination: URL) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: source.path) else { return }
        if source.standardizedFileURL == destination.standardizedFileURL { return }

        try? fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: destination.path) {
            try? fileManager.removeItem(at: source)
            return
        }
        try? fileManager.moveItem(at: source, to: destination)
    }

    nonisolated private static func removeEmptyDirectory(_ directory: URL) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path),
              let items = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              ),
              items.isEmpty else { return }
        try? fileManager.removeItem(at: directory)
    }
}

#endif
