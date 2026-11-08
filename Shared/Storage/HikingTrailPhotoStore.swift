//
//  HikingTrailPhotoStore.swift
//  Shared
//

#if os(iOS)

import UIKit

enum HikingTrailPhotoStore {
    static func sessionDirectory(for sessionID: UUID) -> URL {
        guard let root = UserDataPaths.activeUserRoot else {
            return UserDataPaths.photosRootDirectory.appendingPathComponent(sessionID.uuidString, isDirectory: true)
        }
        return HikingStorageLayout.photosDirectory(recordID: sessionID, in: root)
    }

    static func fileURL(sessionID: UUID, filename: String) -> URL {
        guard let root = UserDataPaths.activeUserRoot else {
            return sessionDirectory(for: sessionID).appendingPathComponent(filename)
        }
        return HikingStorageLayout.resolvedPhotoURL(recordID: sessionID, filename: filename, in: root)
    }

    @discardableResult
    static func saveJPEG(_ image: UIImage, sessionID: UUID, filename: String, compressionQuality: CGFloat = 0.85) throws -> URL {
        guard let root = UserDataPaths.activeUserRoot else {
            throw StoreError.encodingFailed
        }
        let directory = HikingStorageLayout.photosDirectory(recordID: sessionID, in: root)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let normalized = HikingStorageLayout.normalizedPhotoFilename(filename)
        let url = directory.appendingPathComponent(normalized)
        guard let data = image.jpegData(compressionQuality: compressionQuality) else {
            throw StoreError.encodingFailed
        }
        try data.write(to: url, options: [.atomic])
        HikingRecordAssetCleaner.purgeNumberedConflictCopies(of: normalized, in: directory)
        return url
    }

    static func loadImage(sessionID: UUID, filename: String) -> UIImage? {
        let url = fileURL(sessionID: sessionID, filename: filename)
        return UIImage(contentsOfFile: url.path)
    }

    static func deletePhoto(sessionID: UUID, filename: String) {
        let url = fileURL(sessionID: sessionID, filename: filename)
        try? FileManager.default.removeItem(at: url)
    }

    static func deleteAll(for sessionID: UUID) {
        guard let root = UserDataPaths.activeUserRoot else { return }
        try? FileManager.default.removeItem(
            at: HikingStorageLayout.photosDirectory(recordID: sessionID, in: root)
        )
        let legacy = UserDataPaths.photosRootDirectory.appendingPathComponent(sessionID.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: legacy)
    }

    enum StoreError: Error {
        case encodingFailed
    }
}

#endif
