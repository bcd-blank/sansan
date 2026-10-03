//
//  UserDataPaths.swift
//  Shared
//

#if os(iOS)

import Foundation

/// 로그인 사용자별 Documents 하위 경로. 로그인 비활성 시 `localUserID` 를 사용합니다.
enum UserDataPaths: Sendable {
    nonisolated static var localUserID: String { "local" }

    nonisolated(unsafe) private(set) static var currentUserID: String?

    /// 로그인 없이 이 기기에 데이터를 저장합니다.
    static func activateLocalUser() {
        setActiveUser(localUserID)
        migrateLegacyDataIfNeeded(for: localUserID)
    }

    nonisolated static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }

    nonisolated static var isUserSelected: Bool { currentUserID != nil }

    static func setActiveUser(_ userID: String) {
        currentUserID = userID
        let root = userRoot(userID: userID)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(
            at: HikingStorageLayout.recordsDirectory(in: root),
            withIntermediateDirectories: true
        )
        HikingStorageMigrator.migrateJSONFiles(at: root)
    }

    static func clearActiveUser() {
        currentUserID = nil
    }

    nonisolated static func userRoot(userID: String) -> URL {
        documentsDirectory
            .appendingPathComponent("users", isDirectory: true)
            .appendingPathComponent(userID, isDirectory: true)
    }

    nonisolated static var activeUserRoot: URL? {
        guard let currentUserID else { return nil }
        return userRoot(userID: currentUserID)
    }

    nonisolated static var recordsFileURL: URL {
        guard let root = activeUserRoot else {
            fatalError("UserDataPaths: no active user")
        }
        return HikingStorageLayout.recordsJSONURL(in: root)
    }

    nonisolated static var existingRecordsFileURL: URL? {
        guard let root = activeUserRoot else { return nil }
        return HikingStorageLayout.existingRecordsJSONURL(in: root)
    }

    nonisolated static var tombstonesFileURL: URL {
        guard let root = activeUserRoot else {
            fatalError("UserDataPaths: no active user")
        }
        return HikingStorageLayout.tombstonesJSONURL(in: root)
    }

    nonisolated static var existingTombstonesFileURL: URL? {
        guard let root = activeUserRoot else { return nil }
        return HikingStorageLayout.existingTombstonesJSONURL(in: root)
    }

    nonisolated static var snapshotsDirectory: URL {
        guard let root = activeUserRoot else {
            fatalError("UserDataPaths: no active user")
        }
        return root.appendingPathComponent(
            HikingStorageLayout.Legacy.snapshotsDirectoryName,
            isDirectory: true
        )
    }

    nonisolated static var photosRootDirectory: URL {
        guard let root = activeUserRoot else {
            fatalError("UserDataPaths: no active user")
        }
        return root.appendingPathComponent(
            HikingStorageLayout.Legacy.photosDirectoryName,
            isDirectory: true
        )
    }

    nonisolated static var profilePhotoFileURL: URL? {
        guard let root = activeUserRoot else { return nil }
        return HikingStorageLayout.profilePhotoURL(in: root)
    }

    /// 업데이트 전 단일 사용자용 파일 → 첫 로그인 계정 폴더로 이동.
    static func migrateLegacyDataIfNeeded(for userID: String) {
        let fileManager = FileManager.default
        let userRoot = userRoot(userID: userID)
        try? fileManager.createDirectory(at: userRoot, withIntermediateDirectories: true)

        moveIntoUserFolderIfNeeded(
            documentsDirectory.appendingPathComponent(HikingStorageLayout.recordsJSONName),
            userRoot.appendingPathComponent(HikingStorageLayout.recordsJSONName)
        )
        moveIntoUserFolderIfNeeded(
            documentsDirectory.appendingPathComponent(HikingStorageLayout.Legacy.recordsJSONName),
            userRoot.appendingPathComponent(HikingStorageLayout.Legacy.recordsJSONName)
        )
        moveIntoUserFolderIfNeeded(
            documentsDirectory.appendingPathComponent(HikingStorageLayout.tombstonesJSONName),
            userRoot.appendingPathComponent(HikingStorageLayout.tombstonesJSONName)
        )
        moveIntoUserFolderIfNeeded(
            documentsDirectory.appendingPathComponent(HikingStorageLayout.Legacy.snapshotsDirectoryName, isDirectory: true),
            userRoot.appendingPathComponent(HikingStorageLayout.Legacy.snapshotsDirectoryName, isDirectory: true)
        )
        moveIntoUserFolderIfNeeded(
            documentsDirectory.appendingPathComponent(HikingStorageLayout.Legacy.photosDirectoryName, isDirectory: true),
            userRoot.appendingPathComponent(HikingStorageLayout.Legacy.photosDirectoryName, isDirectory: true)
        )

        HikingStorageMigrator.migrateProfileAssets(from: documentsDirectory, to: userRoot)
        HikingStorageMigrator.migrateJSONFiles(at: userRoot)
    }

    private static func moveIntoUserFolderIfNeeded(_ source: URL, _ destination: URL) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: source.path),
              !fileManager.fileExists(atPath: destination.path) else { return }
        try? fileManager.moveItem(at: source, to: destination)
    }
}

#endif
