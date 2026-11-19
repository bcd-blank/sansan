//
//  MountainSummitCatalog.swift
//  Shared
//
//  OpenStreetMap natural=peak (한국, 이름 있음) — 앱 번들 JSON.
//

import Foundation

enum MountainSummitCatalog {
    nonisolated private static let lock = NSLock()
    nonisolated(unsafe) private static var loadedSummits: [MountainSummit]?
    nonisolated(unsafe) private static var isLoading = false

    nonisolated static var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return loadedSummits != nil
    }

    /// 아직 로드 전이면 빈 배열을 바로 돌려 메인 스레드를 막지 않습니다.
    nonisolated static var allSummits: [MountainSummit] {
        lock.lock()
        let loaded = loadedSummits
        let loading = isLoading
        lock.unlock()
        if let loaded { return loaded }
        if !loading { preload() }
        return []
    }

    /// 백그라운드 로드가 끝날 때까지 기다립니다. 메인 스레드를 잠그지 않습니다.
    nonisolated static func waitUntilReady(timeout: Duration = .seconds(8)) async {
        if isReady { return }
        preload()
        let deadline = ContinuousClock.now + timeout
        while !isReady, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    /// 앱 부팅 시 백그라운드에서 JSON을 미리 읽습니다. 호출 스레드는 기다리지 않습니다.
    nonisolated static func preload() {
        lock.lock()
        if loadedSummits != nil || isLoading {
            lock.unlock()
            return
        }
        isLoading = true
        lock.unlock()

        Task.detached(priority: .utility) {
            let decoded = loadFromDisk()
            storeLoaded(decoded)
        }
    }

    nonisolated private static func storeLoaded(_ decoded: [MountainSummit]) {
        lock.lock()
        loadedSummits = decoded
        isLoading = false
        lock.unlock()
    }

    nonisolated private static func loadFromDisk() -> [MountainSummit] {
        guard let url = bundleResourceURL() else { return [] }
        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([MountainSummit].self, from: data)
            return decoded.map(MountainSummitNameCorrections.applyingPreferredName)
        } catch {
            return []
        }
    }

    nonisolated private static func bundleResourceURL() -> URL? {
        if let url = Bundle.main.url(
            forResource: "mountain_summits",
            withExtension: "json",
            subdirectory: "Resources"
        ) {
            return url
        }
        return Bundle.main.url(forResource: "mountain_summits", withExtension: "json")
    }
}
