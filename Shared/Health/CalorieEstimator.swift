//
//  CalorieEstimator.swift
//  Shared
//
//  순수 칼로리 추정 — 워치 HealthKit 실측 활성 칼로리가 없을 때(아이폰 단독 기록) 사용합니다.
//  거리·상승고도·시간·체중으로 수평 보행(ACSM) + 수직 등반 에너지를 합산해 추정합니다.
//  부작용이 없어 단독 테스트·복원이 쉽습니다.
//

import Foundation

enum CalorieEstimator {
    /// 보행 속도 상한(m/min) — 비정상 GPS로 인한 과대 추정 방지(약 8 km/h).
    private static let maxWalkingSpeedMetersPerMinute: Double = 133
    /// 산소 1L 당 에너지(kcal).
    private static let kcalPerLiterOxygen: Double = 5
    /// 등반 효율(인체 기계 효율, 약 22%).
    private static let climbingEfficiency: Double = 0.22
    private static let gravity: Double = 9.81
    private static let joulesPerKilocalorie: Double = 4184

    /// 활성 칼로리(kcal) 추정. 입력이 불충분하면 0.
    static func estimateActiveKilocalories(
        distanceMeters: Double,
        elevationGainMeters: Double,
        durationSeconds: TimeInterval,
        bodyMassKilograms: Double
    ) -> Double {
        guard durationSeconds > 0, bodyMassKilograms > 0 else { return 0 }

        let durationMinutes = durationSeconds / 60
        let safeDistance = max(0, distanceMeters)
        let rawSpeed = safeDistance / durationMinutes
        let speedMetersPerMinute = min(max(0, rawSpeed), maxWalkingSpeedMetersPerMinute)

        // ACSM 보행 총 VO2(ml/kg/min) = 수평 성분 + 안정 대사.
        let walkingVO2 = 0.1 * speedMetersPerMinute + 3.5
        let walkingKilocaloriesPerMinute = walkingVO2 * bodyMassKilograms / 1000 * kcalPerLiterOxygen
        let walkingKilocalories = walkingKilocaloriesPerMinute * durationMinutes

        // 수직 등반 에너지: m·g·h를 효율로 보정.
        let gain = max(0, elevationGainMeters)
        let verticalJoules = bodyMassKilograms * gravity * gain / climbingEfficiency
        let verticalKilocalories = verticalJoules / joulesPerKilocalorie

        return walkingKilocalories + verticalKilocalories
    }
}
