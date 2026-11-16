//
//  HeartRatePreferences.swift
//  Shared
//

import Combine
import Foundation

enum HeartRatePreferences {
    nonisolated private static let featureEnabledBaseKey = "sansan.heartRate.isFeatureEnabled"
    nonisolated private static let monitoringEnabledBaseKey = "sansan.heartRate.isMonitoringEnabled"

    nonisolated private static func storageKey(for baseKey: String) -> String {
#if os(iOS)
        guard let userID = UserDataPaths.currentUserID else { return baseKey }
        return "\(baseKey).\(userID)"
#else
        return baseKey
#endif
    }

    /// 일반설정 — 심박수 기능·메인 카드 표시 여부.
    nonisolated static var isFeatureEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: storageKey(for: featureEnabledBaseKey)) }
        set { UserDefaults.standard.set(newValue, forKey: storageKey(for: featureEnabledBaseKey)) }
    }

    /// 메인 카드 — 기록 중 심박수 측정 on/off.
    nonisolated static var isMonitoringEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: storageKey(for: monitoringEnabledBaseKey)) }
        set { UserDefaults.standard.set(newValue, forKey: storageKey(for: monitoringEnabledBaseKey)) }
    }
}

#if os(iOS)

@MainActor
final class HeartRatePreferencesObserver: ObservableObject {
    static let shared = HeartRatePreferencesObserver()

    @Published private(set) var isFeatureEnabled: Bool
    @Published private(set) var isMonitoringEnabled: Bool

    private init() {
        isFeatureEnabled = HeartRatePreferences.isFeatureEnabled
        isMonitoringEnabled = HeartRatePreferences.isMonitoringEnabled
    }

    func syncFromStorage() {
        isFeatureEnabled = HeartRatePreferences.isFeatureEnabled
        isMonitoringEnabled = HeartRatePreferences.isMonitoringEnabled
    }

    func setFeatureEnabled(_ isOn: Bool) {
        guard isFeatureEnabled != isOn else { return }
        HeartRatePreferences.isFeatureEnabled = isOn
        isFeatureEnabled = isOn
    }

    func setMonitoringEnabled(_ isOn: Bool) {
        guard isMonitoringEnabled != isOn else { return }
        HeartRatePreferences.isMonitoringEnabled = isOn
        isMonitoringEnabled = isOn
    }
}

#endif
