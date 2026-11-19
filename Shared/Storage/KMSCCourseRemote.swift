//
//  KMSCCourseRemote.swift
//  Shared
//
//  KMSC GPX HTTPS 루트. `{baseURL}/{relativePath}` 로 한 코스씩 받습니다.
//  Notion 공개 링크는 만료·HTML 래핑 때문에 쓰지 않습니다.
//

#if os(iOS)

import Foundation

enum KMSCCourseRemote {
    /// `Info.plist` 의 `SANSANKMSCCourseBaseURL`.
    /// 예: `https://example.com/KMSC` — 그 아래에 `100대명산/.../*.gpx` 가 있어야 합니다.
    nonisolated static var baseURL: URL? {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "SANSANKMSCCourseBaseURL") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    nonisolated static func fileURL(baseURL: URL, relativePath: String) -> URL {
        relativePath.split(separator: "/").reduce(baseURL) { url, component in
            url.appending(path: String(component), directoryHint: .notDirectory)
        }
    }

    nonisolated static func fileURL(forRelativePath relativePath: String) -> URL? {
        guard let baseURL else { return nil }
        return fileURL(baseURL: baseURL, relativePath: relativePath)
    }
}

#endif
