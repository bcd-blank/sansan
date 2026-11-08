//
//  ICloudRecordSync.swift
//  Shared
//

#if os(iOS)

import Combine
import Foundation

/// 등산 기록 폴더(JSON·스냅샷·사진)를 iCloud Drive에 미러링합니다.
@MainActor
final class ICloudRecordSync: ObservableObject {
    static let shared = ICloudRecordSync()
    static let containerIdentifier = "iCloud.com.jw.sansan"

    @Published private(set) var isAvailable = false
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncDate: Date?
    @Published private(set) var statusMessage = "확인 중…"

    private var pushTask: Task<Void, Never>?

    private init() {}

    var statusLabel: String {
        if isSyncing { return "동기화 중" }
        return statusMessage
    }

    func refreshAvailability() async {
        guard StorageCapabilities.isICloudSyncEnabled else {
            isAvailable = false
            statusMessage = "iCloud 동기화가 비활성화되어 있습니다"
            return
        }
        let url = await resolveContainerURL()
        isAvailable = url != nil
        statusMessage = isAvailable ? "사용 가능" : "iCloud를 사용할 수 없음"
    }

    /// iCloud → 로컬 병합 후, 로컬 변경분을 iCloud에 업로드합니다.
    func pullAndMerge() async {
        guard StorageCapabilities.isICloudSyncEnabled else { return }
        guard let localRoot = UserDataPaths.activeUserRoot else { return }
        await refreshAvailability()
        guard isAvailable, let remoteRoot = await iCloudUserRoot() else { return }

        isSyncing = true
        defer {
            isSyncing = false
            lastSyncDate = Date()
        }

        let message = await Task.detached(priority: .utility) {
            await Self.performPullAndMerge(localRoot: localRoot, remoteRoot: remoteRoot)
        }.value
        statusMessage = message
    }

    /// 저장·삭제 후 디바운스 업로드.
    func schedulePush() {
        guard StorageCapabilities.isICloudSyncEnabled, isAvailable else { return }
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await self?.pushOnly()
        }
    }

    private func pushOnly() async {
        guard let localRoot = UserDataPaths.activeUserRoot,
              let remoteRoot = await iCloudUserRoot() else { return }

        isSyncing = true
        defer {
            isSyncing = false
            lastSyncDate = Date()
        }

        let message = await Task.detached(priority: .utility) {
            await Self.performPush(localRoot: localRoot, remoteRoot: remoteRoot)
        }.value
        statusMessage = message
    }

    nonisolated private static func performPullAndMerge(localRoot: URL, remoteRoot: URL) async -> String {
        do {
            try FileManager.default.createDirectory(at: remoteRoot, withIntermediateDirectories: true)
            await ensureDownloaded(at: remoteRoot)
            HikingStorageMigrator.migrateLegacyLayout(at: remoteRoot)
            try mergeRecordsJSON(localRoot: localRoot, remoteRoot: remoteRoot)
            HikingRecordAssetCleaner.purgeNumberedConflictCopies(at: remoteRoot)
            try copyMissingAssets(from: remoteRoot, to: localRoot)
            HikingStorageMigrator.migrateLegacyLayout(at: localRoot)
            try pushManagedContent(from: localRoot, to: remoteRoot)
            return "동기화 완료"
        } catch {
            return "동기화 실패"
        }
    }

    nonisolated private static func performPush(localRoot: URL, remoteRoot: URL) async -> String {
        do {
            try FileManager.default.createDirectory(at: remoteRoot, withIntermediateDirectories: true)
            try pushManagedContent(from: localRoot, to: remoteRoot)
            return "iCloud에 저장됨"
        } catch {
            return "업로드 실패"
        }
    }

    private func resolveContainerURL() async -> URL? {
        let containerID = Self.containerIdentifier
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let url = FileManager.default.url(forUbiquityContainerIdentifier: containerID)
                continuation.resume(returning: url)
            }
        }
    }

    private func iCloudUserRoot() async -> URL? {
        guard let container = await resolveContainerURL(),
              let userID = UserDataPaths.currentUserID else { return nil }
        return container
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("users", isDirectory: true)
            .appendingPathComponent(userID, isDirectory: true)
    }

    nonisolated private static func mergeRecordsJSON(localRoot: URL, remoteRoot: URL) throws {
        HikingStorageMigrator.migrateJSONFiles(at: localRoot)
        HikingStorageMigrator.migrateJSONFiles(at: remoteRoot)

        let localURL = HikingStorageLayout.recordsJSONURL(in: localRoot)
        let remoteURL = HikingStorageLayout.recordsJSONURL(in: remoteRoot)
        let localTombstonesURL = HikingStorageLayout.tombstonesJSONURL(in: localRoot)
        let remoteTombstonesURL = HikingStorageLayout.tombstonesJSONURL(in: remoteRoot)

        let tombstones = HikingRecordMergeLogic.mergedTombstones(
            local: loadTombstones(from: localTombstonesURL)
                + loadTombstones(from: localRoot.appendingPathComponent(HikingStorageLayout.Legacy.tombstonesJSONName))
                + loadNumberedTombstones(in: localRoot),
            remote: loadTombstones(from: remoteTombstonesURL)
                + loadTombstones(from: remoteRoot.appendingPathComponent(HikingStorageLayout.Legacy.tombstonesJSONName))
                + loadNumberedTombstones(in: remoteRoot)
        )
        let sorted = HikingRecordMergeLogic.mergedRecords(
            local: loadRecords(from: localURL)
                + loadRecords(from: localRoot.appendingPathComponent(HikingStorageLayout.Legacy.recordsJSONName))
                + loadNumberedRecords(in: localRoot),
            remote: loadRecords(from: remoteURL)
                + loadRecords(from: remoteRoot.appendingPathComponent(HikingStorageLayout.Legacy.recordsJSONName))
                + loadNumberedRecords(in: remoteRoot),
            tombstones: tombstones
        )

        let encoder = makeEncoder()
        let recordsData = try encoder.encode(sorted)
        try recordsData.write(to: localURL, options: [.atomic])
        try writeCoordinated(recordsData, to: remoteURL)

        let tombstonesData = try encoder.encode(tombstones)
        try tombstonesData.write(to: localTombstonesURL, options: [.atomic])
        try writeCoordinated(tombstonesData, to: remoteTombstonesURL)

        removeNumberedJSONCopies(in: localRoot)
        removeNumberedJSONCopies(in: remoteRoot)
        HikingStorageMigrator.removeLegacyJSONFiles(at: localRoot)
        HikingStorageMigrator.removeLegacyJSONFiles(at: remoteRoot)

        let tombstonedIDs = Set(tombstones.map(\.id))
        HikingRecordAssetCleaner.purgeAssets(for: tombstonedIDs, at: localRoot)
        HikingRecordAssetCleaner.purgeAssets(for: tombstonedIDs, at: remoteRoot)
    }

    nonisolated private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    nonisolated private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    nonisolated private static func loadRecords(from url: URL) -> [SavedHikingSession] {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let records = try? makeDecoder().decode([SavedHikingSession].self, from: data) else {
            return []
        }
        return records
    }

    nonisolated private static func loadTombstones(from url: URL) -> [HikingRecordTombstone] {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let tombstones = try? makeDecoder().decode([HikingRecordTombstone].self, from: data) else {
            return []
        }
        return tombstones
    }

    nonisolated private static func loadNumberedRecords(in root: URL) -> [SavedHikingSession] {
        numberedJSONURLs(in: root, prefixes: [
            HikingStorageLayout.recordsJSONName,
            HikingStorageLayout.Legacy.recordsJSONName
        ]).flatMap(loadRecords(from:))
    }

    nonisolated private static func loadNumberedTombstones(in root: URL) -> [HikingRecordTombstone] {
        numberedJSONURLs(in: root, prefixes: [
            HikingStorageLayout.tombstonesJSONName,
            HikingStorageLayout.Legacy.tombstonesJSONName
        ]).flatMap(loadTombstones(from:))
    }

    nonisolated private static func numberedJSONURLs(in root: URL, prefixes: [String]) -> [URL] {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let stems = prefixes.map { ($0 as NSString).deletingPathExtension }
        return items.filter { url in
            let name = HikingRecordAssetCleaner.strippingICloudPlaceholderSuffix(url.lastPathComponent)
            return HikingRecordAssetCleaner.isNumberedConflictCopy(name)
                && stems.contains(where: { name.hasPrefix($0) })
                && name.lowercased().hasSuffix(".json")
        }
    }

    nonisolated private static func removeNumberedJSONCopies(in root: URL) {
        let urls = numberedJSONURLs(in: root, prefixes: HikingStorageLayout.managedJSONBasenames)
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }

    nonisolated private static func copyMissingAssets(from sourceRoot: URL, to destinationRoot: URL) throws {
        for folder in HikingStorageLayout.syncedAssetDirectoryNames {
            let source = sourceRoot.appendingPathComponent(folder, isDirectory: true)
            let destination = destinationRoot.appendingPathComponent(folder, isDirectory: true)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            try copyMissingContents(from: source, to: destination)
        }
    }

    nonisolated private static func copyMissingContents(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        let items = try fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for item in items {
            let name = item.lastPathComponent
            if HikingRecordAssetCleaner.shouldSkipDuringSync(name) {
                continue
            }
            let values = try item.resourceValues(forKeys: [.isDirectoryKey])
            let target = destination.appendingPathComponent(name)
            if values.isDirectory == true {
                try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
                try copyMissingContents(from: item, to: target)
            } else if !fileManager.fileExists(atPath: target.path) {
                try fileManager.copyItem(at: item, to: target)
            }
        }
    }

    nonisolated private static func pushManagedContent(from localRoot: URL, to remoteRoot: URL) throws {
        let names = [
            HikingStorageLayout.recordsJSONName,
            HikingStorageLayout.tombstonesJSONName,
            HikingStorageLayout.profilePhotoFilename,
            HikingStorageLayout.avatarFilename,
            HikingStorageLayout.recordsDirectoryName,
            HikingStorageLayout.Legacy.recordsJSONName,
            HikingStorageLayout.Legacy.tombstonesJSONName,
            HikingStorageLayout.Legacy.snapshotsDirectoryName,
            HikingStorageLayout.Legacy.photosDirectoryName,
            HikingStorageLayout.Legacy.avatarFilename
        ]
        for name in names {
            let source = localRoot.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            let destination = remoteRoot.appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory)
            if isDirectory.boolValue {
                try pushDirectory(from: source, to: destination)
            } else if !hasSameFileSize(source, destination) {
                try copyReplacing(from: source, to: destination)
            }
        }
    }

    nonisolated private static func pushDirectory(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let items = try fileManager.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        for item in items {
            let name = item.lastPathComponent
            if HikingRecordAssetCleaner.shouldSkipDuringSync(name) {
                continue
            }
            let values = try item.resourceValues(forKeys: [.isDirectoryKey])
            let target = destination.appendingPathComponent(name)
            if values.isDirectory == true {
                try pushDirectory(from: item, to: target)
            } else if !hasSameFileSize(item, target) {
                try copyReplacing(from: item, to: target)
            }
        }
    }

    nonisolated private static func hasSameFileSize(_ source: URL, _ destination: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: destination.path) else { return false }
        let keys: Set<URLResourceKey> = [.fileSizeKey, .totalFileSizeKey]
        let sourceValues = try? source.resourceValues(forKeys: keys)
        let destinationValues = try? destination.resourceValues(forKeys: keys)
        let sourceSize = sourceValues?.fileSize ?? sourceValues?.totalFileSize
        let destinationSize = destinationValues?.fileSize ?? destinationValues?.totalFileSize
        guard let sourceSize, let destinationSize else { return false }
        return sourceSize == destinationSize
    }

    nonisolated private static func copyReplacing(from source: URL, to destination: URL) throws {
        try coordinateWriting(at: destination) { writableURL in
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: writableURL.path) {
                let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try fileManager.copyItem(at: source, to: temp)
                _ = try fileManager.replaceItemAt(writableURL, withItemAt: temp)
            } else {
                try fileManager.copyItem(at: source, to: writableURL)
            }
        }
    }

    nonisolated private static func writeCoordinated(_ data: Data, to url: URL) throws {
        try coordinateWriting(at: url) { writableURL in
            try data.write(to: writableURL, options: [.atomic])
        }
    }

    nonisolated private static func coordinateWriting(at url: URL, _ body: (URL) throws -> Void) throws {
        var coordinatorError: NSError?
        var workError: Error?
        NSFileCoordinator().coordinate(
            writingItemAt: url,
            options: .forReplacing,
            error: &coordinatorError
        ) { writableURL in
            do {
                try body(writableURL)
            } catch {
                workError = error
            }
        }
        if let coordinatorError { throw coordinatorError }
        if let workError { throw workError }
    }

    nonisolated private static func ensureDownloaded(at url: URL) async {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }

        if isDirectory.boolValue {
            guard let children = try? fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .ubiquitousItemDownloadingStatusKey],
                options: [.skipsHiddenFiles]
            ) else { return }
            for child in children {
                let name = child.lastPathComponent
                if HikingRecordAssetCleaner.isNumberedConflictCopy(name) {
                    let canonical = HikingRecordAssetCleaner.canonicalFilename(from: name) ?? name
                    if canonical.lowercased().hasSuffix(".json") {
                        await ensureDownloaded(at: child)
                    }
                    continue
                }
                if name.hasPrefix(".") || name.hasSuffix(".tmp") {
                    continue
                }
                await ensureDownloaded(at: child)
            }
        } else {
            await downloadIfNeeded(url)
        }
    }

    nonisolated private static func downloadIfNeeded(_ url: URL) async {
        guard let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus,
              status == .notDownloaded else { return }

        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        for _ in 0 ..< 40 {
            try? await Task.sleep(for: .milliseconds(250))
            if let current = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus,
               current == .current {
                return
            }
        }
    }
}

#endif
