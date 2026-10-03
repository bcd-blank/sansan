//
//  KMSCCourseGPXStore.swift
//  Shared
//
//  번들 → 캐시 → HTTPS 순으로 KMSC GPX를 준비합니다.
//

#if os(iOS)

import Foundation

actor KMSCCourseGPXStore {
    static let shared = KMSCCourseGPXStore()

    private var inFlight: [String: Task<URL, Error>] = [:]

    func fileURL(for entry: KMSCCourseEntry) async throws -> URL {
        if let local = Self.existingLocalURL(for: entry) {
            return local
        }
        if let existing = inFlight[entry.id] {
            return try await existing.value
        }

        let task = Task.detached(priority: .userInitiated) {
            try await Self.downloadAndCache(entry)
        }
        inFlight[entry.id] = task
        defer { inFlight[entry.id] = nil }
        return try await task.value
    }

    nonisolated private static func existingLocalURL(for entry: KMSCCourseEntry) -> URL? {
        let fileManager = FileManager.default
        if let bundled = bundledURL(for: entry), fileManager.fileExists(atPath: bundled.path) {
            return bundled
        }
        let cached = cacheURL(for: entry)
        if fileManager.fileExists(atPath: cached.path) {
            return cached
        }
        return nil
    }

    nonisolated private static func downloadAndCache(_ entry: KMSCCourseEntry) async throws -> URL {
        if let local = existingLocalURL(for: entry) {
            return local
        }
        guard let remoteURL = KMSCCourseRemote.fileURL(forRelativePath: entry.relativePath) else {
            throw KMSCCourseImportError.remoteNotConfigured
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(from: remoteURL)
        } catch {
            throw KMSCCourseImportError.downloadFailed
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw KMSCCourseImportError.downloadFailed
        }
        guard looksLikeGPX(data) else {
            throw KMSCCourseImportError.downloadFailed
        }

        let destination = cacheURL(for: entry)
        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: destination, options: .atomic)
        } catch {
            throw KMSCCourseImportError.unreadable
        }
        return destination
    }

    nonisolated private static func looksLikeGPX(_ data: Data) -> Bool {
        guard let prefix = String(data: data.prefix(512), encoding: .utf8) else { return false }
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.contains("<gpx") || trimmed.hasPrefix("<?xml")
    }

    nonisolated private static func cacheURL(for entry: KMSCCourseEntry) -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches
            .appendingPathComponent("KMSCCourses", isDirectory: true)
            .appendingPathComponent(entry.relativePath)
    }

    nonisolated private static func bundledURL(for entry: KMSCCourseEntry) -> URL? {
        guard let root = kmscRootURL() else { return nil }
        let nfc = root.appendingPathComponent(entry.relativePath)
        if FileManager.default.fileExists(atPath: nfc.path) {
            return nfc
        }
        let nfdPath = entry.relativePath.decomposedStringWithCanonicalMapping
        let nfd = root.appendingPathComponent(nfdPath)
        if FileManager.default.fileExists(atPath: nfd.path) {
            return nfd
        }
        return nfc
    }

    nonisolated private static func kmscRootURL() -> URL? {
        let candidates: [URL?] = [
            Bundle.main.url(forResource: "KMSC", withExtension: nil),
            Bundle.main.url(forResource: "KMSC", withExtension: nil, subdirectory: "Resources"),
            Bundle.main.resourceURL?.appendingPathComponent("KMSC", isDirectory: true),
            Bundle.main.resourceURL?.appendingPathComponent("Resources/KMSC", isDirectory: true),
        ]
        let fileManager = FileManager.default
        for candidate in candidates {
            guard let url = candidate else { continue }
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
                return url
            }
        }
        return nil
    }
}

#endif
