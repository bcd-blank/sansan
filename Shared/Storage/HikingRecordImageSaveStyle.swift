//
//  HikingRecordImageSaveStyle.swift
//  Shared
//

#if os(iOS)

import Combine
import Foundation

/// 사진 저장·공유 이미지 구성.
enum HikingRecordImageSaveStyle: String, CaseIterable, Identifiable, Sendable {
    /// 지도와 정보 카드를 세로로 쌓은 기록 카드.
    case card
    /// 전체 지도 위에 정보 카드 내용을 텍스트로만 올린 한 장.
    case summary

    var id: String { rawValue }

    var label: String {
        switch self {
        case .card: "기록 카드"
        case .summary: "요약"
        }
    }

    var footer: String {
        switch self {
        case .card:
            "지도와 시작·거리·칼로리 등 정보 카드를 한 장의 기록으로 저장합니다."
        case .summary:
            "전체 지도 위에 정보 카드의 내용을 텍스트로만 올려 한 장의 지도 이미지로 저장합니다."
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
