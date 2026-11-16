//
//  HikingFlythroughPreferences.swift
//  sansan
//
//  3D 경로 영상 옵션(화면 방향·지도 스타일) 영구 저장. 일반설정에서 변경.
//

#if os(iOS)

import Combine
import Foundation

enum HikingFlythroughPreferences {
    nonisolated private static let orientationBaseKey = "sansan.flythrough.orientation"
    nonisolated private static let mapStyleBaseKey = "sansan.flythrough.mapStyle"
    nonisolated private static let showsPhotoMarkersBaseKey = "sansan.flythrough.showsPhotoMarkers"
    nonisolated private static let showsDistanceMarkersBaseKey = "sansan.flythrough.showsDistanceMarkers"
    nonisolated private static let qualityBaseKey = "sansan.flythrough.quality"
    nonisolated private static let titleSourceBaseKey = "sansan.flythrough.titleSource"

    nonisolated private static func storageKey(for baseKey: String) -> String {
        guard let userID = UserDataPaths.currentUserID else { return baseKey }
        return "\(baseKey).\(userID)"
    }

    nonisolated static var orientation: FlythroughOrientation {
        get {
            let key = storageKey(for: orientationBaseKey)
            guard let raw = UserDefaults.standard.string(forKey: key),
                  let value = FlythroughOrientation(rawValue: raw) else {
                return .portrait
            }
            return value
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey(for: orientationBaseKey))
        }
    }

    nonisolated static var mapStyle: FlythroughMapStyle {
        get {
            let key = storageKey(for: mapStyleBaseKey)
            guard let raw = UserDefaults.standard.string(forKey: key),
                  let value = FlythroughMapStyle(rawValue: raw) else {
                return .satellite
            }
            return value
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey(for: mapStyleBaseKey))
        }
    }

    /// 경로 위 사진 썸네일 팝업 표시.
    nonisolated static var showsPhotoMarkers: Bool {
        get {
            let key = storageKey(for: showsPhotoMarkersBaseKey)
            if UserDefaults.standard.object(forKey: key) == nil { return true }
            return UserDefaults.standard.bool(forKey: key)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: storageKey(for: showsPhotoMarkersBaseKey))
        }
    }

    /// 경로 위 1km 단위 거리 라벨 표시.
    nonisolated static var showsDistanceMarkers: Bool {
        get {
            let key = storageKey(for: showsDistanceMarkersBaseKey)
            if UserDefaults.standard.object(forKey: key) == nil { return false }
            return UserDefaults.standard.bool(forKey: key)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: storageKey(for: showsDistanceMarkersBaseKey))
        }
    }

    /// 화질·속도 프리셋.
    nonisolated static var quality: FlythroughQuality {
        get {
            let key = storageKey(for: qualityBaseKey)
            guard let raw = UserDefaults.standard.string(forKey: key),
                  let value = FlythroughQuality(rawValue: raw) else {
                return .balanced
            }
            return value
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey(for: qualityBaseKey))
        }
    }

    /// 영상 타이틀 — 지명 자동검색 또는 기록 타이틀 반영.
    nonisolated static var titleSource: FlythroughTitleSource {
        get {
            let key = storageKey(for: titleSourceBaseKey)
            guard let raw = UserDefaults.standard.string(forKey: key),
                  let value = FlythroughTitleSource(rawValue: raw) else {
                return .autoPlaceName
            }
            return value
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey(for: titleSourceBaseKey))
        }
    }
}

@MainActor
final class HikingFlythroughPreferencesObserver: ObservableObject {
    static let shared = HikingFlythroughPreferencesObserver()

    @Published private(set) var orientation: FlythroughOrientation
    @Published private(set) var mapStyle: FlythroughMapStyle
    @Published private(set) var showsPhotoMarkers: Bool
    @Published private(set) var showsDistanceMarkers: Bool
    @Published private(set) var quality: FlythroughQuality
    @Published private(set) var titleSource: FlythroughTitleSource

    private init() {
        orientation = HikingFlythroughPreferences.orientation
        mapStyle = HikingFlythroughPreferences.mapStyle
        showsPhotoMarkers = HikingFlythroughPreferences.showsPhotoMarkers
        showsDistanceMarkers = HikingFlythroughPreferences.showsDistanceMarkers
        quality = HikingFlythroughPreferences.quality
        titleSource = HikingFlythroughPreferences.titleSource
    }

    func syncFromStorage() {
        orientation = HikingFlythroughPreferences.orientation
        mapStyle = HikingFlythroughPreferences.mapStyle
        showsPhotoMarkers = HikingFlythroughPreferences.showsPhotoMarkers
        showsDistanceMarkers = HikingFlythroughPreferences.showsDistanceMarkers
        quality = HikingFlythroughPreferences.quality
        titleSource = HikingFlythroughPreferences.titleSource
    }

    func setOrientation(_ value: FlythroughOrientation) {
        guard orientation != value else { return }
        HikingFlythroughPreferences.orientation = value
        orientation = value
    }

    func setMapStyle(_ value: FlythroughMapStyle) {
        guard mapStyle != value else { return }
        HikingFlythroughPreferences.mapStyle = value
        mapStyle = value
    }

    func setShowsPhotoMarkers(_ value: Bool) {
        guard showsPhotoMarkers != value else { return }
        HikingFlythroughPreferences.showsPhotoMarkers = value
        showsPhotoMarkers = value
    }

    func setShowsDistanceMarkers(_ value: Bool) {
        guard showsDistanceMarkers != value else { return }
        HikingFlythroughPreferences.showsDistanceMarkers = value
        showsDistanceMarkers = value
    }

    func setQuality(_ value: FlythroughQuality) {
        guard quality != value else { return }
        HikingFlythroughPreferences.quality = value
        quality = value
    }

    func setTitleSource(_ value: FlythroughTitleSource) {
        guard titleSource != value else { return }
        HikingFlythroughPreferences.titleSource = value
        titleSource = value
    }
}

#endif
