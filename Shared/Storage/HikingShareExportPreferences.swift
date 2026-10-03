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
    var showsPhotoMarkers: Bool
    var showsPinnedThumbnails: Bool

    nonisolated init(
        showsDistanceMarkers: Bool = true,
        showsPhotoMarkers: Bool = true,
        showsPinnedThumbnails: Bool = true
    ) {
        self.showsDistanceMarkers = showsDistanceMarkers
        self.showsPhotoMarkers = showsPhotoMarkers
        self.showsPinnedThumbnails = showsPinnedThumbnails
    }
}

extension HikingShareMapExportOptions: Codable {
    private enum CodingKeys: String, CodingKey {
        case showsDistanceMarkers
        case showsPhotoMarkers
        case showsPinnedThumbnails
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showsDistanceMarkers = try container.decodeIfPresent(Bool.self, forKey: .showsDistanceMarkers) ?? true
        showsPhotoMarkers = try container.decodeIfPresent(Bool.self, forKey: .showsPhotoMarkers) ?? true
        showsPinnedThumbnails = try container.decodeIfPresent(Bool.self, forKey: .showsPinnedThumbnails) ?? true
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(showsDistanceMarkers, forKey: .showsDistanceMarkers)
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

    nonisolated private static var optionsKey: String {
        guard let userID = UserDataPaths.currentUserID else { return optionsBaseKey }
        return "\(optionsBaseKey).\(userID)"
    }

    nonisolated static var mapOptions: HikingShareMapExportOptions {
        get {
            guard let data = UserDefaults.standard.data(forKey: optionsKey) else {
                return HikingShareMapExportOptions(
                    showsDistanceMarkers: HikingMapDisplayPreferences.legacyShowsDistanceMarkers
                )
            }

            var options = (try? JSONDecoder().decode(HikingShareMapExportOptions.self, from: data))
                ?? HikingShareMapExportOptions()

            if !storedOptionsIncludeDistanceMarkers(data) {
                options.showsDistanceMarkers = HikingMapDisplayPreferences.legacyShowsDistanceMarkers
            }
            return options
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            UserDefaults.standard.set(data, forKey: optionsKey)
        }
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
