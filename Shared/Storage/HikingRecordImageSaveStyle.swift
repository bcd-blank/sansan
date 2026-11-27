//
//  HikingRecordImageSaveStyle.swift
//  Shared
//

#if os(iOS)

import Combine
import Foundation

/// 사진 저장·공유 이미지 구성.
///
/// Storage raw values stay stable for migration:
/// - `card` → Data Card (was 기록 카드)
/// - `summary` → Simple Grey (was 요약)
/// - `simpleColor` → Simple Color (new)
enum HikingRecordImageSaveStyle: String, CaseIterable, Identifiable, Sendable {
    /// 지도와 정보 카드를 세로로 쌓은 기록 카드.
    case card
    /// 회색 지도 위에 흰 정보 카드를 올린 한 장 (기존 요약).
    case summary
    /// 컬러 지도 위에 리퀴드 글래스 정보 카드를 올린 한 장.
    case simpleColor

    var id: String { rawValue }

    /// Settings pager order: Data Card | Simple Grey | Simple Color.
    static var pagerOrder: [HikingRecordImageSaveStyle] {
        [.card, .summary, .simpleColor]
    }

    var label: String {
        switch self {
        case .card: "Data Card"
        case .summary: "Simple Grey"
        case .simpleColor: "Simple Color"
        }
    }

    var footer: String {
        switch self {
        case .card:
            "지도와 시작·거리·칼로리 등 정보 카드를 한 장의 기록으로 저장합니다."
        case .summary:
            "회색 지도 위에 정보 카드 내용을 올려 한 장의 지도 이미지로 저장합니다."
        case .simpleColor:
            "컬러 지도 위에 반투명 글래스 정보 카드를 올려 한 장의 지도 이미지로 저장합니다."
        }
    }

    /// Offscreen MKMapSnapshotter + ImageRenderer path (no live detail map wait).
    var usesOffscreenSummaryRenderer: Bool {
        switch self {
        case .summary, .simpleColor: true
        case .card: false
        }
    }
}

@MainActor
final class HikingRecordImageSaveStyleObserver: ObservableObject {
    static let shared = HikingRecordImageSaveStyleObserver()

    @Published private(set) var style: HikingRecordImageSaveStyle

    private init() {
        style = HikingRecordImageSavePreferences.style
    }

    func syncFromStorage() {
        style = HikingRecordImageSavePreferences.style
    }

    func setStyle(_ newStyle: HikingRecordImageSaveStyle) {
        guard style != newStyle else { return }
        HikingRecordImageSavePreferences.style = newStyle
        style = newStyle
    }
}

enum HikingRecordImageSavePreferences {
    nonisolated private static let baseKey = "sansan.hikingRecordImageSaveStyle"

    nonisolated private static var storageKey: String {
        guard let userID = UserDataPaths.currentUserID else { return baseKey }
        return "\(baseKey).\(userID)"
    }

    nonisolated static var style: HikingRecordImageSaveStyle {
        get {
            guard let raw = UserDefaults.standard.string(forKey: storageKey),
                  let style = HikingRecordImageSaveStyle(rawValue: raw) else {
                return .card
            }
            return style
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey)
        }
    }
}

#endif
