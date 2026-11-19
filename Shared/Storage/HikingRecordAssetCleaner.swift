//
//  HikingRecordAssetCleaner.swift
//  Shared
//

#if os(iOS)

import Foundation

enum HikingRecordAssetCleaner: Sendable {
    /// Finder/iCloud 충돌 사본: `snapshot 2.png`, `UUID 2.jpg`, `records 3.json`.
    nonisolated static func isNumberedConflictCopy(_ filename: String) -> Bool {
        canonicalFilename(from: filename) != nil
    }

    /// `UUID 2.png` / `snapshot 2.png.icloud` → `UUID.png` / `snapshot.png`. 충돌 사본이 아니면 nil.
    nonisolated static func canonicalFilename(from filename: String) -> String? {
        let name = strippingICloudPlaceholderSuffix(filename)
        guard let match = name.wholeMatch(of: /^(.+) (\d+)\.([A-Za-z0-9]+)$/) else {
            return nil
        }
        return "\(match.1).\(match.3)"
    }

    nonisolated static func strippingICloudPlaceholderSuffix(_ filename: String) -> String {
        let suffix = ".icloud"
        guard filename.lowercased().hasSuffix(suffix) else { return filename }
        return String(filename.dropLast(suffix.count))
    }

    nonisolated static func purgeAssets(for recordIDs: Set<UUID>, at userRoot: URL) {
        for recordID in recordIDs {
            HikingStorageLayout.removeRecordPackage(recordID: recordID, in: userRoot)
        }
    }

    /// iCloud/Finder가 만든 `이름 N.ext` 사본을 제거하고, 원본이 없으면 하나를 승격합니다.
    nonisolated static func purgeNumberedConflictCopies(at userRoot: URL) {
        purgeNumberedConflictCopies(in: userRoot, mediaOnly: true)
        purgeNumberedConflictCopies(
            in: userRoot.appendingPathComponent(HikingStorageLayout.Legacy.snapshotsDirectoryName, isDirectory: true),
            mediaOnly: false
        )

        let legacyPhotos = userRoot.appendingPathComponent(
            HikingStorageLayout.Legacy.photosDirectoryName,
            isDirectory: true
        )
        purgeNumberedCopiesInSessionDirectories(legacyPhotos)

        let recordsRoot = HikingStorageLayout.recordsDirectory(in: userRoot)
        guard let packages = try? FileManager.default.contentsOfDirectory(
            at: recordsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for package in packages {
            let isDirectory = (try? package.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            guard isDirectory else { continue }
            purgeNumberedConflictCopies(in: package, mediaOnly: false)
            purgeNumberedConflictCopies(
                in: package.appendingPathComponent(HikingStorageLayout.photosDirectoryName, isDirectory: true),
                mediaOnly: false
            )
        }
    }

    nonisolated static func purgeNumberedConflictCopies(of filename: String, in directory: URL) {
        let canonical = canonicalFilename(from: filename) ?? filename
        removeFiles(matchingCanonical: canonical, in: directory, keepingCanonical: true)
    }

    nonisolated static func shouldSkipDuringSync(_ filename: String) -> Bool {
        if filename.lowercased().hasSuffix(".icloud") { return true }
        if filename.hasPrefix(".") { return true }
        if filename.hasSuffix(".tmp") { return true }
        return isNumberedConflictCopy(filename)
    }

    nonisolated private static func purgeNumberedCopiesInSessionDirectories(_ root: URL) {
        guard let sessions = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for session in sessions {
            let isDirectory = (try? session.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if isDirectory {
                purgeNumberedConflictCopies(in: session, mediaOnly: false)
            }
        }
    }

    nonisolated private static func purgeNumberedConflictCopies(in directory: URL, mediaOnly: Bool) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path),
              let items = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .totalFileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
              ) else { return }

        var numberedByCanonical: [String: [URL]] = [:]
        for item in items {
            if (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { continue }
            let name = item.lastPathComponent
            if mediaOnly, name.lowercased().hasSuffix(".json") { continue }
            guard let canonical = canonicalFilename(from: name) else { continue }
            numberedByCanonical[canonical, default: []].append(item)
        }

        for (canonical, numbered) in numberedByCanonical {
            let canonicalURL = directory.appendingPathComponent(canonical)
            if fileManager.fileExists(atPath: canonicalURL.path) {
                numbered.forEach { try? fileManager.removeItem(at: $0) }
                continue
            }

            guard let best = numbered.max(by: { fileSize($0) < fileSize($1) }) else { continue }
            try? fileManager.moveItem(at: best, to: canonicalURL)
            for leftover in numbered where leftover != best {
                try? fileManager.removeItem(at: leftover)
            }
        }
    }

    nonisolated private static func removeFiles(
        matchingCanonical canonical: String,
        in directory: URL,
        keepingCanonical: Bool = false
    ) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: directory.path),
              let items = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              ) else { return }

        for item in items {
            let name = item.lastPathComponent
            let base = strippingICloudPlaceholderSuffix(name)
            let isCanonical = base == canonical
            let isNumberedOfSame = canonicalFilename(from: name) == canonical
            if isCanonical && !keepingCanonical {
                try? fileManager.removeItem(at: item)
            } else if isNumberedOfSame {
                try? fileManager.removeItem(at: item)
            }
        }
    }

    nonisolated private static func fileSize(_ url: URL) -> Int {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileSizeKey])
        return values?.fileSize ?? values?.totalFileSize ?? 0
    }
}

#endif
