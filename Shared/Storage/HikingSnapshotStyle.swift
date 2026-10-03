//
//  HikingSnapshotStyle.swift
//  Shared
//

import Foundation

/// 종료 기록 이미지 스타일.
enum HikingSnapshotStyle: String, CaseIterable, Codable, Sendable {
    /// 경로 + 앱 로고.
    case mapWithStats
    /// 지도와 경로만 (미니멀).
    case routeOnly

    /// 일반설정 스타일 선택 — 추후 구독 기능으로 유료화 예정.
    static var isUserStyleSelectionEnabled: Bool { false }

    /// 선택 UI가 꺼져 있을 때 적용되는 기본 스타일.
    static var lockedStyle: HikingSnapshotStyle { .mapWithStats }

    var displayName: String {
        switch self {
        case .mapWithStats: "경로 + 로고"
        case .routeOnly: "경로만"
        }
    }

    var optionDescription: String {
        switch self {
        case .mapWithStats:
            "지도 위에 등산 경로와 출발·도착 지점을 표시하고, 좌측 하단에 앱 로고를 넣습니다."
        case .routeOnly:
            "지도와 경로, 출발·도착 지점만 표시합니다. 로고는 넣지 않습니다."
        }
    }

    /// 일반설정 정보 안내용 전체 설명.
    static var settingsHelpMessage: String {
        """
        등산을 종료할 때 자동으로 저장되는 경로 PNG, 기록 목록 썸네일, 기록 상세 지도에 적용됩니다.

        \(HikingSnapshotStyle.mapWithStats.displayName): \(HikingSnapshotStyle.mapWithStats.optionDescription)

        \(HikingSnapshotStyle.routeOnly.displayName): \(HikingSnapshotStyle.routeOnly.optionDescription)

        설정을 바꾸면 목록 썸네일의 로고 표시가 바로 바뀌고, 저장된 경로 PNG도 백그라운드에서 다시 그려집니다.
        """
    }
}

#if os(iOS)

import Combine

enum HikingSnapshotPreferences {
    nonisolated private static let baseKey = "sansan.hikingSnapshotStyle"

    nonisolated private static var styleKey: String {
        guard let userID = UserDataPaths.currentUserID else { return baseKey }
        return "\(baseKey).\(userID)"
    }

    static var style: HikingSnapshotStyle {
        get {
            guard HikingSnapshotStyle.isUserStyleSelectionEnabled else {
                return HikingSnapshotStyle.lockedStyle
            }
            guard
                let raw = UserDefaults.standard.string(forKey: styleKey),
                let value = HikingSnapshotStyle(rawValue: raw)
            else { return HikingSnapshotStyle.lockedStyle }
            return value
        }
        set {
            guard HikingSnapshotStyle.isUserStyleSelectionEnabled else { return }
            UserDefaults.standard.set(newValue.rawValue, forKey: styleKey)
            HikingSnapshotPreferencesObserver.shared.syncFromStorage()
        }
    }
}

/// 경로 이미지 스타일 변경 시 썸네일·설정 UI가 바로 갱신되도록 합니다.
@MainActor
final class HikingSnapshotPreferencesObserver: ObservableObject {
    static let shared = HikingSnapshotPreferencesObserver()

    @Published private(set) var style: HikingSnapshotStyle

    private init() {
        style = HikingSnapshotPreferences.style
    }

    func syncFromStorage() {
        style = HikingSnapshotPreferences.style
    }

    @discardableResult
    func setStyle(_ newStyle: HikingSnapshotStyle) -> Bool {
        guard HikingSnapshotStyle.isUserStyleSelectionEnabled else { return false }
        guard style != newStyle else { return false }
        HikingSnapshotPreferences.style = newStyle
        return true
    }
}

extension HikingSnapshotStyle {
    var showsBrandLogo: Bool { self == .mapWithStats }
}

#endif
