//
//  AppThemePreferences.swift
//  sansan
//
//  앱 전역 화면 테마(일반/다크/시스템) 영구 저장. 일반설정에서 변경.
//

#if os(iOS)

import Combine
import Foundation
import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "시스템 설정"
        case .light: return "일반 모드"
        case .dark: return "다크 모드"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum AppThemePreferences {
    nonisolated private static let baseKey = AppExportAppearance.themeBaseKey

    nonisolated private static func storageKey() -> String {
        AppExportAppearance.storageKey()
    }

    nonisolated static var theme: AppTheme {
        get {
            guard let raw = UserDefaults.standard.string(forKey: storageKey()),
                  let value = AppTheme(rawValue: raw) else {
                return .system
            }
            return value
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey())
        }
    }

    /// 활성 사용자 기준 저장된 테마. `currentUserID`가 없으면 읽지 않습니다.
    nonisolated static func themeForActiveUser() -> AppTheme? {
        guard let userID = UserDataPaths.currentUserID else { return nil }
        guard let raw = UserDefaults.standard.string(forKey: "\(baseKey).\(userID)"),
              let value = AppTheme(rawValue: raw) else {
            return nil
        }
        return value
    }
}

@MainActor
final class AppThemePreferencesObserver: ObservableObject {
    static let shared = AppThemePreferencesObserver()

    @Published private(set) var theme: AppTheme

    private init() {
        theme = AppThemePreferences.themeForActiveUser() ?? AppThemePreferences.theme
    }

    func syncFromStorage() {
        theme = AppThemePreferences.themeForActiveUser() ?? AppThemePreferences.theme
    }

    func setTheme(_ value: AppTheme) {
        guard theme != value else { return }
        AppThemePreferences.theme = value
        theme = value
    }
}

#endif
