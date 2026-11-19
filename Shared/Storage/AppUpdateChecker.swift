//
//  AppUpdateChecker.swift
//  Shared
//
//  설정 「정보」 — App Store lookup으로 업데이트 여부 확인 (iOS 1.0.6).
//

#if os(iOS)

import Combine
import Foundation
import UIKit

enum AppUpdateStatus: Equatable, Sendable {
    case checking
    case upToDate
    case available(version: String, url: URL)
    case failed
}

enum AppUpdateChecker {
    nonisolated static let appStoreLookupURL = URL(string: "https://itunes.apple.com/lookup?id=6800198509&country=kr")!
    nonisolated static let fallbackStoreURL = URL(string: "https://apps.apple.com/kr/app/id6800198509")!
    nonisolated static let cacheTTL: TimeInterval = 6 * 60 * 60
    nonisolated static let requestTimeout: TimeInterval = 10

    nonisolated private static let storeVersionKey = "versionCheck.storeVersion"
    nonisolated private static let storeURLKey = "versionCheck.storeURL"
    nonisolated private static let checkedAtKey = "versionCheck.checkedAt"

    struct LookupResult: Equatable, Sendable {
        var version: String
        var trackViewURL: URL?
        var minimumOSVersion: String?
    }

    struct CacheEntry: Equatable, Sendable {
        var storeVersion: String
        var storeURL: URL
        var checkedAt: Date
    }

    // MARK: - Version compare

    /// 숫자 세그먼트 비교. 짧은 쪽은 0 패딩. 파싱 실패 시 nil.
    nonisolated static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult? {
        let left = versionComponents(lhs)
        let right = versionComponents(rhs)
        guard !left.contains(where: { $0 == nil }), !right.contains(where: { $0 == nil }) else {
            return nil
        }
        let leftValues = left.compactMap { $0 }
        let rightValues = right.compactMap { $0 }
        let count = max(leftValues.count, rightValues.count)
        for index in 0..<count {
            let a = index < leftValues.count ? leftValues[index] : 0
            let b = index < rightValues.count ? rightValues[index] : 0
            if a < b { return .orderedAscending }
            if a > b { return .orderedDescending }
        }
        return .orderedSame
    }

    nonisolated private static func versionComponents(_ version: String) -> [Int?] {
        version
            .split(separator: ".", omittingEmptySubsequences: false)
            .map { Int($0) }
    }

    // MARK: - Parse

    nonisolated static func parseLookupResponse(_ data: Data) -> LookupResult? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let resultCount = json["resultCount"] as? Int,
            resultCount >= 1,
            let results = json["results"] as? [[String: Any]],
            let first = results.first,
            let version = first["version"] as? String,
            !version.isEmpty
        else {
            return nil
        }

        let trackViewURL: URL? = {
            guard let raw = first["trackViewUrl"] as? String, !raw.isEmpty else { return nil }
            return URL(string: raw)
        }()
        let minimumOSVersion = first["minimumOsVersion"] as? String
        return LookupResult(
            version: version,
            trackViewURL: trackViewURL,
            minimumOSVersion: minimumOSVersion
        )
    }

    // MARK: - Evaluate

    nonisolated static func status(
        storeVersion: String,
        storeURL: URL,
        minimumOSVersion: String?,
        localVersion: String,
        systemVersion: String
    ) -> AppUpdateStatus? {
        if let minimumOSVersion,
           let osCompare = compareVersions(systemVersion, minimumOSVersion),
           osCompare == .orderedAscending {
            // 기기 OS가 스토어 요구보다 낮으면 안내하지 않음.
            return .upToDate
        }

        guard let compare = compareVersions(localVersion, storeVersion) else {
            return nil
        }
        if compare == .orderedAscending {
            return .available(version: storeVersion, url: storeURL)
        }
        return .upToDate
    }

    // MARK: - Cache

    nonisolated static func loadCache(
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) -> CacheEntry? {
        guard
            let storeVersion = defaults.string(forKey: storeVersionKey),
            !storeVersion.isEmpty,
            let urlString = defaults.string(forKey: storeURLKey),
            let storeURL = URL(string: urlString),
            defaults.object(forKey: checkedAtKey) != nil
        else {
            return nil
        }
        let checkedAt = Date(timeIntervalSince1970: defaults.double(forKey: checkedAtKey))
        return CacheEntry(storeVersion: storeVersion, storeURL: storeURL, checkedAt: checkedAt)
    }

    nonisolated static func isCacheFresh(
        _ entry: CacheEntry,
        now: Date = Date(),
        ttl: TimeInterval = cacheTTL
    ) -> Bool {
        now.timeIntervalSince(entry.checkedAt) <= ttl
    }

    nonisolated static func saveCache(
        storeVersion: String,
        storeURL: URL,
        checkedAt: Date = Date(),
        defaults: UserDefaults = .standard
    ) {
        defaults.set(storeVersion, forKey: storeVersionKey)
        defaults.set(storeURL.absoluteString, forKey: storeURLKey)
        defaults.set(checkedAt.timeIntervalSince1970, forKey: checkedAtKey)
    }

    nonisolated static func clearCache(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storeVersionKey)
        defaults.removeObject(forKey: storeURLKey)
        defaults.removeObject(forKey: checkedAtKey)
    }

    nonisolated static func statusFromCache(
        _ entry: CacheEntry,
        localVersion: String,
        systemVersion: String
    ) -> AppUpdateStatus {
        status(
            storeVersion: entry.storeVersion,
            storeURL: entry.storeURL,
            minimumOSVersion: nil,
            localVersion: localVersion,
            systemVersion: systemVersion
        ) ?? .failed
    }

    // MARK: - Network

    nonisolated static func makeSession(timeout: TimeInterval = requestTimeout) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    nonisolated static func fetchLookup(
        url: URL = appStoreLookupURL,
        session: URLSession
    ) async throws -> LookupResult {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = session.configuration.timeoutIntervalForRequest
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard let result = parseLookupResponse(data) else {
            throw URLError(.cannotParseResponse)
        }
        return result
    }

    nonisolated static func resolveStatus(
        lookup: LookupResult,
        localVersion: String,
        systemVersion: String
    ) -> AppUpdateStatus {
        let storeURL = lookup.trackViewURL ?? fallbackStoreURL
        return status(
            storeVersion: lookup.version,
            storeURL: storeURL,
            minimumOSVersion: lookup.minimumOSVersion,
            localVersion: localVersion,
            systemVersion: systemVersion
        ) ?? .failed
    }

    nonisolated static var localMarketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    nonisolated static var localBuildVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    nonisolated static var localVersionLabel: String {
        "\(localMarketingVersion) (\(localBuildVersion))"
    }
}

@MainActor
final class AppUpdateStatusObserver: ObservableObject {
    static let shared = AppUpdateStatusObserver()

    @Published private(set) var status: AppUpdateStatus = .checking

    private var inFlightTask: Task<Void, Never>?
    private var suppressAutomaticRefresh = false
    private let session: URLSession
    private let defaults: UserDefaults
    private let nowProvider: () -> Date
    private let localVersionProvider: () -> String
    private let systemVersionProvider: () -> String
    private let isRecordingProvider: () -> Bool

    init(
        session: URLSession? = nil,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = { Date() },
        localVersion: (() -> String)? = nil,
        systemVersion: (() -> String)? = nil,
        isRecording: (() -> Bool)? = nil
    ) {
        self.session = session ?? AppUpdateChecker.makeSession()
        self.defaults = defaults
        self.nowProvider = now
        self.localVersionProvider = localVersion ?? { AppUpdateChecker.localMarketingVersion }
        self.systemVersionProvider = systemVersion ?? { UIDevice.current.systemVersion }
        self.isRecordingProvider = isRecording ?? {
            let state = WorkoutManager.shared.sessionData.state
            return state == .recording || state == .paused
        }
    }

    /// 설정 진입 시. 캐시가 신선하면 네트워크 생략. 기록 중이면 네트워크 생략.
    func refreshOnAppear() {
        guard !suppressAutomaticRefresh else { return }
        refresh(forceNetwork: false)
    }

    /// 「다시 확인」— 캐시 무시하고 네트워크 재시도.
    func retry() {
        suppressAutomaticRefresh = false
        refresh(forceNetwork: true)
    }

    func setStatusForTesting(_ status: AppUpdateStatus) {
        inFlightTask?.cancel()
        inFlightTask = nil
        suppressAutomaticRefresh = true
        self.status = status
    }

    private func refresh(forceNetwork: Bool) {
        let localVersion = localVersionProvider()
        let systemVersion = systemVersionProvider()
        let now = nowProvider()
        let cache = AppUpdateChecker.loadCache(now: now, defaults: defaults)

        if !forceNetwork, let cache, AppUpdateChecker.isCacheFresh(cache, now: now) {
            status = AppUpdateChecker.statusFromCache(
                cache,
                localVersion: localVersion,
                systemVersion: systemVersion
            )
            return
        }

        // 기록 중 자동 확인은 네트워크를 치지 않음. 유효/만료 캐시가 있으면 표시.
        if !forceNetwork, isRecordingProvider() {
            if let cache {
                status = AppUpdateChecker.statusFromCache(
                    cache,
                    localVersion: localVersion,
                    systemVersion: systemVersion
                )
            } else {
                status = .failed
            }
            return
        }

        status = .checking
        inFlightTask?.cancel()
        inFlightTask = Task { [weak self] in
            await self?.performNetworkCheck(
                localVersion: localVersion,
                systemVersion: systemVersion,
                fallbackCache: cache
            )
        }
    }

    private func performNetworkCheck(
        localVersion: String,
        systemVersion: String,
        fallbackCache: AppUpdateChecker.CacheEntry?
    ) async {
        do {
            let lookup = try await AppUpdateChecker.fetchLookup(session: session)
            guard !Task.isCancelled else { return }
            let storeURL = lookup.trackViewURL ?? AppUpdateChecker.fallbackStoreURL
            AppUpdateChecker.saveCache(
                storeVersion: lookup.version,
                storeURL: storeURL,
                checkedAt: nowProvider(),
                defaults: defaults
            )
            let resolved = AppUpdateChecker.resolveStatus(
                lookup: lookup,
                localVersion: localVersion,
                systemVersion: systemVersion
            )
            status = resolved
        } catch {
            guard !Task.isCancelled else { return }
            if let fallbackCache {
                status = AppUpdateChecker.statusFromCache(
                    fallbackCache,
                    localVersion: localVersion,
                    systemVersion: systemVersion
                )
            } else {
                status = .failed
            }
        }
    }
}

#endif
