//
//  KMSCCourseCatalog.swift
//  Shared
//
//  번들 `kmsc_catalog.json` 목록. GPX는 코스를 열 때 내려받습니다.
//

#if os(iOS)

import CoreLocation
import Foundation

enum KMSCCourseImportError: LocalizedError, Sendable {
    case noUser
    case missingGPX
    case remoteNotConfigured
    case downloadFailed
    case parseFailed(HikingGPXImporter.ImportError)
    case unreadable

    var errorDescription: String? {
        switch self {
        case .noUser:
            return "사용자 저장 위치가 준비되지 않았습니다."
        case .missingGPX:
            return "코스 파일을 찾을 수 없습니다."
        case .remoteNotConfigured:
            return "코스 다운로드 주소가 설정되지 않았습니다."
        case .downloadFailed:
            return "코스를 내려받지 못했습니다. 네트워크를 확인해 주세요."
        case .parseFailed(let error):
            return error.errorDescription
        case .unreadable:
            return "GPX 파일을 읽을 수 없습니다."
        }
    }
}

enum KMSCCourseCatalog {
    nonisolated private struct CatalogFile: Decodable, Sendable {
        let courses: [KMSCCourseEntry]
    }

    nonisolated private static let lock = NSLock()
    nonisolated(unsafe) private static var loadedCourses: [KMSCCourseEntry]?

    nonisolated static var allCourses: [KMSCCourseEntry] {
        loadIfNeeded()
        return loadedCourses ?? []
    }

    nonisolated static var categories: [String] {
        let names = Set(allCourses.map(\.category))
        return names.sorted { lhs, rhs in
            categorySortKey(lhs) < categorySortKey(rhs)
        }
    }

    nonisolated static var isCatalogAvailable: Bool {
        !allCourses.isEmpty
    }

    nonisolated static func preload() {
        Task.detached(priority: .utility) {
            _ = allCourses
        }
    }

    nonisolated static func courses(in category: String?) -> [KMSCCourseEntry] {
        guard let category else { return allCourses }
        return allCourses.filter { $0.category == category }
    }

    nonisolated static func entry(for id: String) -> KMSCCourseEntry? {
        allCourses.first { $0.id == id }
    }

    nonisolated static func search(query: String, category: String?) -> [KMSCCourseEntry] {
        let base = courses(in: category)
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return base }
        return base.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
                || $0.groupName.localizedCaseInsensitiveContains(trimmed)
                || $0.category.localizedCaseInsensitiveContains(trimmed)
        }
    }

    nonisolated static func parseCourse(_ entry: KMSCCourseEntry) async throws -> HikingGPXImporter.ParsedTrack {
        let url = try await KMSCCourseGPXStore.shared.fileURL(for: entry)
        do {
            return try HikingGPXImporter.parse(url: url)
        } catch let error as HikingGPXImporter.ImportError {
            throw KMSCCourseImportError.parseFailed(error)
        } catch let error as KMSCCourseImportError {
            throw error
        } catch {
            throw KMSCCourseImportError.unreadable
        }
    }

    nonisolated static func loadCoordinates(for id: String) async throws -> [CLLocationCoordinate2D] {
        guard let entry = entry(for: id) else {
            throw KMSCCourseImportError.missingGPX
        }
        let parsed = try await parseCourse(entry)
        let coordinates = parsed.sessionData.points.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        guard coordinates.count >= 2 else {
            throw KMSCCourseImportError.unreadable
        }
        return coordinates
    }

    nonisolated static func decodeCatalog(from data: Data) throws -> [KMSCCourseEntry] {
        let file = try JSONDecoder().decode(CatalogFile.self, from: data)
        return file.courses.sorted {
            if $0.category != $1.category {
                return categorySortKey($0.category) < categorySortKey($1.category)
            }
            if $0.groupName != $1.groupName {
                return $0.groupName.localizedStandardCompare($1.groupName) == .orderedAscending
            }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    nonisolated private static func loadIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard loadedCourses == nil else { return }

        guard let url = catalogResourceURL() else {
            loadedCourses = []
            return
        }
        do {
            let data = try Data(contentsOf: url)
            loadedCourses = try decodeCatalog(from: data)
        } catch {
            loadedCourses = []
        }
    }

    nonisolated private static func catalogResourceURL() -> URL? {
        if let url = Bundle.main.url(
            forResource: "kmsc_catalog",
            withExtension: "json",
            subdirectory: "Resources"
        ) {
            return url
        }
        return Bundle.main.url(forResource: "kmsc_catalog", withExtension: "json")
    }

    nonisolated private static func categorySortKey(_ category: String) -> String {
        if category.contains("100") { return "1-\(category)" }
        if category.contains("9정맥") { return "2-\(category)" }
        if category.contains("백두대간") { return "3-\(category)" }
        if category.contains("오감") { return "4-\(category)" }
        return "9-\(category)"
    }
}

#endif
