//
//  HikingStorageLayout.swift
//  Shared
//
//  사용자 데이터 파일명·폴더 규칙의 단일 출처.
//  공백·임의 문자열을 쓰지 않아 iCloud 충돌 사본(`이름 2.ext`)과 구분합니다.
//

#if os(iOS)

import Foundation

enum HikingStorageLayout: Sendable {
    /// `users/{userID}/records/{recordID}/`
    nonisolated static var recordsDirectoryName: String { "records" }
    nonisolated static var recordsJSONName: String { "records.json" }
    nonisolated static var tombstonesJSONName: String { "tombstones.json" }
    nonisolated static var snapshotFilename: String { "snapshot.png" }
    nonisolated static var photosDirectoryName: String { "photos" }
    nonisolated static var profilePhotoFilename: String { "profile.jpg" }
    nonisolated static var avatarFilename: String { "avatar.png" }
    nonisolated static var photoExtension: String { "jpg" }

    enum Legacy: Sendable {
        nonisolated static var recordsJSONName: String { "saved_hiking_sessions.json" }
        nonisolated static var tombstonesJSONName: String { "deleted_hiking_record_tombstones.json" }
        nonisolated static var snapshotsDirectoryName: String { "hiking_snapshots" }
        nonisolated static var photosDirectoryName: String { "hiking_photos" }
        nonisolated static var avatarFilename: String { "dicebear_avatar.png" }
    }

    nonisolated static var managedJSONBasenames: [String] {
        [
            recordsJSONName,
            tombstonesJSONName,
            Legacy.recordsJSONName,
            Legacy.tombstonesJSONName
        ]
    }

    nonisolated static var syncedAssetDirectoryNames: [String] {
        [
            recordsDirectoryName,
            Legacy.snapshotsDirectoryName,
            Legacy.photosDirectoryName
        ]
    }

    nonisolated static func recordsJSONURL(in userRoot: URL) -> URL {
        userRoot.appendingPathComponent(recordsJSONName)
    }

    nonisolated static func tombstonesJSONURL(in userRoot: URL) -> URL {
        userRoot.appendingPathComponent(tombstonesJSONName)
    }

    nonisolated static func existingRecordsJSONURL(in userRoot: URL) -> URL? {
        firstExistingFile(in: userRoot, names: [recordsJSONName, Legacy.recordsJSONName])
    }

    nonisolated static func existingTombstonesJSONURL(in userRoot: URL) -> URL? {
        firstExistingFile(in: userRoot, names: [tombstonesJSONName, Legacy.tombstonesJSONName])
    }

    nonisolated static func recordsDirectory(in userRoot: URL) -> URL {
        userRoot.appendingPathComponent(recordsDirectoryName, isDirectory: true)
    }

    nonisolated static func recordDirectory(recordID: UUID, in userRoot: URL) -> URL {
        recordsDirectory(in: userRoot).appendingPathComponent(recordID.uuidString, isDirectory: true)
    }

    nonisolated static func snapshotURL(recordID: UUID, in userRoot: URL) -> URL {
        recordDirectory(recordID: recordID, in: userRoot).appendingPathComponent(snapshotFilename)
    }

    nonisolated static func photosDirectory(recordID: UUID, in userRoot: URL) -> URL {
        recordDirectory(recordID: recordID, in: userRoot)
            .appendingPathComponent(photosDirectoryName, isDirectory: true)
    }

    nonisolated static func photoFilename(photoID: UUID) -> String {
        "\(photoID.uuidString).\(photoExtension)"
    }

    nonisolated static func photoURL(recordID: UUID, photoID: UUID, in userRoot: URL) -> URL {
        photosDirectory(recordID: recordID, in: userRoot)
            .appendingPathComponent(photoFilename(photoID: photoID))
    }

    nonisolated static func photoURL(recordID: UUID, filename: String, in userRoot: URL) -> URL {
        photosDirectory(recordID: recordID, in: userRoot)
            .appendingPathComponent(normalizedPhotoFilename(filename))
    }

    nonisolated static func profilePhotoURL(in userRoot: URL) -> URL {
        userRoot.appendingPathComponent(profilePhotoFilename)
    }

    nonisolated static func avatarURL(in userRoot: URL) -> URL {
        userRoot.appendingPathComponent(avatarFilename)
    }

    /// 새 경로 → 구 경로 순으로 스냅샷 파일을 찾습니다.
    nonisolated static func resolvedSnapshotURL(
        recordID: UUID,
        storedFilename: String?,
        in userRoot: URL
    ) -> URL? {
        let candidates: [URL] = [
            snapshotURL(recordID: recordID, in: userRoot),
            userRoot
                .appendingPathComponent(Legacy.snapshotsDirectoryName, isDirectory: true)
                .appendingPathComponent("\(recordID.uuidString).png"),
            storedFilename.map {
                userRoot
                    .appendingPathComponent(Legacy.snapshotsDirectoryName, isDirectory: true)
                    .appendingPathComponent($0)
            }
        ].compactMap { $0 }

        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    nonisolated static func resolvedPhotoURL(recordID: UUID, filename: String, in userRoot: URL) -> URL {
        let normalized = normalizedPhotoFilename(filename)
        let canonical = photosDirectory(recordID: recordID, in: userRoot)
            .appendingPathComponent(normalized)
        if FileManager.default.fileExists(atPath: canonical.path) {
            return canonical
        }
        let legacy = userRoot
            .appendingPathComponent(Legacy.photosDirectoryName, isDirectory: true)
            .appendingPathComponent(recordID.uuidString, isDirectory: true)
            .appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: legacy.path) {
            return legacy
        }
        let legacyNormalized = userRoot
            .appendingPathComponent(Legacy.photosDirectoryName, isDirectory: true)
            .appendingPathComponent(recordID.uuidString, isDirectory: true)
            .appendingPathComponent(normalized)
        if FileManager.default.fileExists(atPath: legacyNormalized.path) {
            return legacyNormalized
        }
        return canonical
    }

    nonisolated static func resolvedAvatarURL(in userRoot: URL) -> URL? {
        firstExistingFile(in: userRoot, names: [avatarFilename, Legacy.avatarFilename])
            ?? avatarURL(in: userRoot)
    }

    nonisolated static func normalizedPhotoFilename(_ filename: String) -> String {
        let name = HikingRecordAssetCleaner.strippingICloudPlaceholderSuffix(filename)
        let canonical = HikingRecordAssetCleaner.canonicalFilename(from: name) ?? name
        if let uuid = uuid(fromFilename: canonical) {
            return photoFilename(photoID: uuid)
        }
        return canonical
    }

    nonisolated static func uuid(fromFilename filename: String) -> UUID? {
        let name = HikingRecordAssetCleaner.strippingICloudPlaceholderSuffix(filename)
        let stem = (HikingRecordAssetCleaner.canonicalFilename(from: name) ?? name) as NSString
        return UUID(uuidString: stem.deletingPathExtension)
    }

    nonisolated static func isManagedRootFile(_ filename: String) -> Bool {
        let name = HikingRecordAssetCleaner.strippingICloudPlaceholderSuffix(filename)
        let canonical = HikingRecordAssetCleaner.canonicalFilename(from: name) ?? name
        return managedJSONBasenames.contains(canonical)
            || canonical == profilePhotoFilename
            || canonical == avatarFilename
            || canonical == Legacy.avatarFilename
    }

    nonisolated static func removeRecordPackage(recordID: UUID, in userRoot: URL) {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: recordDirectory(recordID: recordID, in: userRoot))

        let legacySnapshot = userRoot
            .appendingPathComponent(Legacy.snapshotsDirectoryName, isDirectory: true)
            .appendingPathComponent("\(recordID.uuidString).png")
        HikingRecordAssetCleaner.purgeNumberedConflictCopies(
            of: legacySnapshot.lastPathComponent,
            in: legacySnapshot.deletingLastPathComponent()
        )
        try? fileManager.removeItem(at: legacySnapshot)

        let legacyPhotos = userRoot
            .appendingPathComponent(Legacy.photosDirectoryName, isDirectory: true)
            .appendingPathComponent(recordID.uuidString, isDirectory: true)
        try? fileManager.removeItem(at: legacyPhotos)
    }

    nonisolated private static func firstExistingFile(in directory: URL, names: [String]) -> URL? {
        let fileManager = FileManager.default
        for name in names {
            let url = directory.appendingPathComponent(name)
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }
}

#endif
