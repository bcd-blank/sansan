//
//  HikingMapDisplayPreferences.swift
//  Shared
//

#if os(iOS)

import Combine
import Foundation

enum HikingMapDisplayPreferences {
    nonisolated private static let summitMarkersBaseKey = "sansan.hikingMapDisplayPreferences.showsSummitMarkers"
    nonisolated private static let legacyDistanceMarkersBaseKey =
        "sansan.hikingMapDisplayPreferences.showsDistanceMarkers"

    nonisolated private static func storageKey(for baseKey: String) -> String {
        guard let userID = UserDataPaths.currentUserID else { return baseKey }
        return "\(baseKey).\(userID)"
    }

    nonisolated static var showsSummitMarkers: Bool {
        get {
            let key = storageKey(for: summitMarkersBaseKey)
            if UserDefaults.standard.object(forKey: key) == nil {
                return false
            }
            return UserDefaults.standard.bool(forKey: key)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: storageKey(for: summitMarkersBaseKey))
        }
    }

    /// 이전 버전에서 저장·공유 구간 표시와 공유하던 값. `HikingShareExportPreferences` 마이그레이션용.
    nonisolated static var legacyShowsDistanceMarkers: Bool {
        let key = storageKey(for: legacyDistanceMarkersBaseKey)
        if UserDefaults.standard.object(forKey: key) == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: key)
    }
}

@MainActor
final class HikingMapDisplayPreferencesObserver: ObservableObject {
    static let shared = HikingMapDisplayPreferencesObserver()

    @Published private(set) var showsSummitMarkers: Bool

    private init() {
        showsSummitMarkers = HikingMapDisplayPreferences.showsSummitMarkers
    }

    func syncFromStorage() {
        showsSummitMarkers = HikingMapDisplayPreferences.showsSummitMarkers
    }

    func setShowsSummitMarkers(_ isOn: Bool) {
        guard showsSummitMarkers != isOn else { return }
        HikingMapDisplayPreferences.showsSummitMarkers = isOn
        showsSummitMarkers = isOn
    }
}

#endif
