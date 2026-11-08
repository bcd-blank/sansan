//
//  KmVoiceGuidancePreferences.swift
//  Shared
//
//  일반설정 「1km 음성 안내」 — 기본값 ON.
//

#if os(iOS)

import Combine
import Foundation

enum KmVoiceGuidancePreferences {
    nonisolated private static let enabledBaseKey = "sansan.kmVoiceGuidance.isEnabled"

    nonisolated private static func storageKey(for baseKey: String) -> String {
        guard let userID = UserDataPaths.currentUserID else { return baseKey }
        return "\(baseKey).\(userID)"
    }

    /// 기록 중 1km마다 음성 안내. 키가 없으면 기본 ON.
    nonisolated static var isEnabled: Bool {
        get {
            let key = storageKey(for: enabledBaseKey)
            if UserDefaults.standard.object(forKey: key) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: key)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: storageKey(for: enabledBaseKey))
        }
    }
}

@MainActor
final class KmVoiceGuidancePreferencesObserver: ObservableObject {
    static let shared = KmVoiceGuidancePreferencesObserver()

    @Published private(set) var isEnabled: Bool

    private init() {
        isEnabled = KmVoiceGuidancePreferences.isEnabled
    }

    func syncFromStorage() {
        isEnabled = KmVoiceGuidancePreferences.isEnabled
    }

    func setEnabled(_ isOn: Bool) {
        guard isEnabled != isOn else { return }
        KmVoiceGuidancePreferences.isEnabled = isOn
        isEnabled = isOn
    }
}

#endif
