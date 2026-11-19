//
//  HikingShareExportPreferences.swift
//  Shared
//

#if os(iOS)

import Combine
import Foundation

/// 공유·사진 저장 이미지에만 적용되는 오버레이 옵션.
/// 기록 상세 지도 표시(`HikingRecordRouteMapView`)와 별개입니다.
struct HikingShareMapExportOptions: Equatable, Sendable {
    var showsDistanceMarkers: Bool
    var showsTimeMarkers: Bool
    var showsWeatherLabel: Bool
    var showsPhotoMarkers: Bool
    var showsPinnedThumbnails: Bool

    nonisolated init(
        showsDistanceMarkers: Bool = true,
        showsTimeMarkers: Bool = true,
        showsWeatherLabel: Bool = true,
        showsPhotoMarkers: Bool = true,
        showsPinnedThumbnails: Bool = true
    ) {
        self.showsDistanceMarkers = showsDistanceMarkers
        self.showsTimeMarkers = showsTimeMarkers
        self.showsWeatherLabel = showsWeatherLabel
        self.showsPhotoMarkers = showsPhotoMarkers
        self.showsPinnedThumbnails = showsPinnedThumbnails
    }
}

extension HikingShareMapExportOptions: Codable {
    private enum CodingKeys: String, CodingKey {
        case showsDistanceMarkers
        case showsTimeMarkers
        case showsWeatherLabel
        case showsPhotoMarkers
        case showsPinnedThumbnails
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showsDistanceMarkers = try container.decodeIfPresent(Bool.self, forKey: .showsDistanceMarkers) ?? true
        showsTimeMarkers = try container.decodeIfPresent(Bool.self, forKey: .showsTimeMarkers) ?? true
        showsWeatherLabel = try container.decodeIfPresent(Bool.self, forKey: .showsWeatherLabel) ?? true
        showsPhotoMarkers = try container.decodeIfPresent(Bool.self, forKey: .showsPhotoMarkers) ?? true
        showsPinnedThumbnails = try container.decodeIfPresent(Bool.self, forKey: .showsPinnedThumbnails) ?? true
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(showsDistanceMarkers, forKey: .showsDistanceMarkers)
        try container.encode(showsTimeMarkers, forKey: .showsTimeMarkers)
        try container.encode(showsWeatherLabel, forKey: .showsWeatherLabel)
        try container.encode(showsPhotoMarkers, forKey: .showsPhotoMarkers)
        try container.encode(showsPinnedThumbnails, forKey: .showsPinnedThumbnails)
    }
}

/// 일반설정 「저장 · 공유 지도」 섹션 UI 동기화용. 기록 상세 지도에는 사용하지 않습니다.
@MainActor
final class HikingShareExportPreferencesObserver: ObservableObject {
    static let shared = HikingShareExportPreferencesObserver()

    @Published private(set) var mapOptions: HikingShareMapExportOptions

    private init() {
        mapOptions = HikingShareExportPreferences.mapOptions
    }

    func syncFromStorage() {
        mapOptions = HikingShareExportPreferences.mapOptions
    }

    func setMapOptions(_ newOptions: HikingShareMapExportOptions) {
        guard mapOptions != newOptions else { return }
        HikingShareExportPreferences.mapOptions = newOptions
        mapOptions = newOptions
        HikingRecordStore.shared.clearAllRouteImageCaches()
    }
}

enum HikingShareExportPreferences {
    nonisolated private static let optionsBaseKey = "sansan.hikingShareMapExportOptions"

    /// JW: 저장·공유 이미지에서 사진 위치 마커를 끈다. 코드·UserDefaults 값은 유지하고 읽기만 off.
    /// 기록 상세 지도(`HikingRecordRouteMapView`)에는 적용하지 않는다.
    nonisolated static let isSharePhotoMarkersEnabled = false
    /// JW: 저장·공유 이미지에서 고정 사진 썸네일을 끈다. 코드·UserDefaults 값은 유지하고 읽기만 off.
    nonisolated static let isSharePinnedThumbnailsEnabled = false

    nonisolated private static var optionsKey: String {
        guard let userID = UserDataPaths.currentUserID else { return optionsBaseKey }
        return "\(optionsBaseKey).\(userID)"
    }

    nonisolated static var mapOptions: HikingShareMapExportOptions {
        get {
            var options: HikingShareMapExportOptions
            if let data = UserDefaults.standard.data(forKey: optionsKey) {
                options = (try? JSONDecoder().decode(HikingShareMapExportOptions.self, from: data))
                    ?? HikingShareMapExportOptions()
                if !storedOptionsIncludeDistanceMarkers(data) {
                    options.showsDistanceMarkers = HikingMapDisplayPreferences.legacyShowsDistanceMarkers
                }
            } else {
                options = HikingShareMapExportOptions(
                    showsDistanceMarkers: HikingMapDisplayPreferences.legacyShowsDistanceMarkers
                )
            }
            return applyingSharePhotoFeatureFlags(options)
        }
        set {
            // Keep previously stored photo/thumbnail bits when feature flags force runtime off,
            // so an old "on" preference is not rewritten/deleted.
            var toStore = newValue
            if let data = UserDefaults.standard.data(forKey: optionsKey),
               let existing = try? JSONDecoder().decode(HikingShareMapExportOptions.self, from: data) {
                if !isSharePhotoMarkersEnabled {
                    toStore.showsPhotoMarkers = existing.showsPhotoMarkers
                }
                if !isSharePinnedThumbnailsEnabled {
                    toStore.showsPinnedThumbnails = existing.showsPinnedThumbnails
                }
            }
            guard let data = try? JSONEncoder().encode(toStore) else { return }
            UserDefaults.standard.set(data, forKey: optionsKey)
        }
    }

    /// Share/save entry points call this so explicit `true` options cannot bypass the flags.
    nonisolated static func applyingSharePhotoFeatureFlags(
        _ options: HikingShareMapExportOptions
    ) -> HikingShareMapExportOptions {
        var result = options
        if !isSharePhotoMarkersEnabled {
            result.showsPhotoMarkers = false
        }
        if !isSharePinnedThumbnailsEnabled {
            result.showsPinnedThumbnails = false
        }
        return result
    }

    nonisolated private static func storedOptionsIncludeDistanceMarkers(_ data: Data) -> Bool {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return false
        }
        return object[JSONCodingKeys.showsDistanceMarkers.rawValue] != nil
    }

    private enum JSONCodingKeys: String {
        case showsDistanceMarkers
    }
}

#endif
