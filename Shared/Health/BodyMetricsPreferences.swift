//
//  BodyMetricsPreferences.swift
//  Shared
//
//  칼로리 추정에 사용하는 사용자 체중(kg) 환경설정 — 아이폰 단독 기록의 추정식 입력값.
//  워치 기록은 HealthKit 실측 활성 칼로리를 사용하므로 체중이 필요 없습니다.
//

import Combine
import Foundation

enum BodyMetricsPreferences {
    nonisolated private static let bodyMassBaseKey = "sansan.bodyMetrics.bodyMassKilograms"

    /// 체중 미설정 시 추정에 사용하는 기본값(kg).
    nonisolated static let defaultBodyMassKilograms: Double = 65

    nonisolated private static func storageKey(for baseKey: String) -> String {
#if os(iOS)
        guard let userID = UserDataPaths.currentUserID else { return baseKey }
        return "\(baseKey).\(userID)"
#else
        return baseKey
#endif
    }

    /// 사용자가 설정한 체중(kg). 미설정(0 이하)이면 nil.
    nonisolated static var bodyMassKilograms: Double? {
        get {
            let value = UserDefaults.standard.double(forKey: storageKey(for: bodyMassBaseKey))
            return value > 0 ? value : nil
        }
        set {
            if let newValue, newValue > 0 {
                UserDefaults.standard.set(newValue, forKey: storageKey(for: bodyMassBaseKey))
            } else {
                UserDefaults.standard.removeObject(forKey: storageKey(for: bodyMassBaseKey))
            }
        }
    }

    /// 추정에 사용할 체중 — 미설정이면 기본값.
    nonisolated static var effectiveBodyMassKilograms: Double {
        bodyMassKilograms ?? defaultBodyMassKilograms
    }
}

#if os(iOS)

@MainActor
final class BodyMetricsPreferencesObserver: ObservableObject {
    static let shared = BodyMetricsPreferencesObserver()

    @Published private(set) var bodyMassKilograms: Double?

    private init() {
        bodyMassKilograms = BodyMetricsPreferences.bodyMassKilograms
    }

    func syncFromStorage() {
        bodyMassKilograms = BodyMetricsPreferences.bodyMassKilograms
    }

    func setBodyMass(_ kilograms: Double?) {
        let normalized = (kilograms ?? 0) > 0 ? kilograms : nil
        guard normalized != bodyMassKilograms else { return }
        BodyMetricsPreferences.bodyMassKilograms = normalized
        bodyMassKilograms = normalized
    }
}

#endif
