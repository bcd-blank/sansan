//
//  HikingGPSStatisticalCorrection.swift
//  Shared
//
//  이상치 GPS를 버릴 때 남기는 보정점 — 가우시안 MAP(칼만 위치 갱신) + Huber 로버스트 가중.
//  Xcode: Shared/Models 타깃 멤버십 → sansan, sansan Watch App
//

import CoreLocation
import Foundation

/// 관측(GPS)과 운동 모형(직전 위치·속도)을 가우시안 MAP으로 결합합니다.
///
/// 예측: `x̂⁻ = x_{t-1} + v_{t-1} Δt`,  `P⁻ = P_{t-1} + σ_a² Δt⁴ / 4`
/// 관측: `z ~ N(x, R)`, `R = max(hAcc, 8m)²`
/// 이노베이션 게이트: `d² = ||z − x̂⁻||² / (P⁻ + R)`. `d²`가 χ²₂ 95%(5.991)를 넘으면
/// Huber 가중 `w = min(1, c / d)`으로 칼만 게인을 줄입니다.
/// 갱신: `K = w · P⁻ / (P⁻ + R)`, `x̂ = x̂⁻ + K (z − x̂⁻)`
/// 마지막에 `||x̂ − x_{t-1}|| ≤ v_max Δt` 원판으로 투영해 운동학 제약(가능 집합)을 겁니다.
nonisolated enum HikingGPSStatisticalCorrection {
    /// 관측 분산 하한(m). 산악 GPS가 5m로 낙관 보고해도 이보다 믿지는 않습니다.
    nonisolated static let minimumObservationSigma: Double = 8
    /// 이산 백색 가속 잡음(m/s²). 보행 가감속에 해당하는 프로세스 노이즈입니다.
    nonisolated static let processNoiseAcceleration: Double = 0.4
    /// 2자유도 χ² 분포 95% 분위수 — 이노베이션 마할라노비스 게이트.
    nonisolated static let chiSquareGate95: Double = 5.991
    /// Huber M-추정 상수. 게이트를 넘긴 이노베이션의 칼만 게인을 `c / d`로 줄입니다.
    nonisolated static let huberThreshold: Double = 2.5
    /// 위치 분산 초기값(m²).
    nonisolated static let defaultPositionVariance: Double = 64

    /// `previous`에서 `candidate` 시각의 MAP 위치. `prior`는 속도 추정용 그 이전 점입니다.
    nonisolated static func correctedPoint(
        previous: HikingPoint,
        prior: HikingPoint?,
        candidate: HikingPoint,
        maxSpeedMetersPerSecond: Double
    ) -> HikingPoint {
        let dt = max(abs(candidate.timestamp.timeIntervalSince(previous.timestamp)), 0.1)
        let frame = LocalENU(origin: previous)
        let previousEN = frame.eastNorth(of: previous)
        let observation = frame.eastNorth(of: candidate)

        let velocity = cappedVelocity(
            prior: prior,
            previous: previous,
            frame: frame,
            maxSpeed: maxSpeedMetersPerSecond
        )
        let predicted = (
            east: previousEN.east + velocity.east * dt,
            north: previousEN.north + velocity.north * dt
        )

        let priorSigma = max(
            previous.horizontalAccuracy ?? sqrt(defaultPositionVariance),
            minimumObservationSigma
        )
        let processVariance =
            processNoiseAcceleration * processNoiseAcceleration * pow(dt, 4) / 4
        let predictedVariance = priorSigma * priorSigma + processVariance

        let observationSigma = max(
            candidate.horizontalAccuracy ?? minimumObservationSigma,
            minimumObservationSigma
        )
        let observationVariance = observationSigma * observationSigma
        let innovationVariance = predictedVariance + observationVariance

        let innovationEast = observation.east - predicted.east
        let innovationNorth = observation.north - predicted.north
        let innovationMeters = hypot(innovationEast, innovationNorth)
        let mahalanobisSquared = (innovationMeters * innovationMeters) / max(innovationVariance, 1e-6)
        let mahalanobis = sqrt(mahalanobisSquared)

        let huberWeight: Double
        if mahalanobisSquared <= chiSquareGate95 {
            huberWeight = 1
        } else {
            huberWeight = min(1, huberThreshold / max(mahalanobis, 1e-6))
        }

        let kalmanGain = huberWeight * predictedVariance / max(innovationVariance, 1e-6)
        var estimate = (
            east: predicted.east + kalmanGain * innovationEast,
            north: predicted.north + kalmanGain * innovationNorth
        )

        estimate = projectedOntoSpeedDisk(
            from: previousEN,
            toward: estimate,
            maxDistance: maxSpeedMetersPerSecond * dt
        )

        return frame.point(
            east: estimate.east,
            north: estimate.north,
            template: candidate,
            altitude: previous.altitude
        )
    }

    /// 직전 두 점으로 속도를 구하고 `maxSpeed`로 자릅니다.
    nonisolated private static func cappedVelocity(
        prior: HikingPoint?,
        previous: HikingPoint,
        frame: LocalENU,
        maxSpeed: Double
    ) -> (east: Double, north: Double) {
        guard let prior else { return (0, 0) }
        let dt = previous.timestamp.timeIntervalSince(prior.timestamp)
        guard dt > 0.05 else { return (0, 0) }
        let priorEN = frame.eastNorth(of: prior)
        let previousEN = frame.eastNorth(of: previous)
        var east = (previousEN.east - priorEN.east) / dt
        var north = (previousEN.north - priorEN.north) / dt
        let speed = hypot(east, north)
        if speed > maxSpeed, speed > 0 {
            let scale = maxSpeed / speed
            east *= scale
            north *= scale
        }
        return (east, north)
    }

    /// MAP 해가 가능 속도 원판 밖이면 원판 경계로 투영합니다(제약 MAP).
    nonisolated private static func projectedOntoSpeedDisk(
        from origin: (east: Double, north: Double),
        toward estimate: (east: Double, north: Double),
        maxDistance: Double
    ) -> (east: Double, north: Double) {
        let east = estimate.east - origin.east
        let north = estimate.north - origin.north
        let distance = hypot(east, north)
        guard distance > maxDistance, distance > 0 else { return estimate }
        let scale = maxDistance / distance
        return (origin.east + east * scale, origin.north + north * scale)
    }
}

/// 짧은 구간용 동-북 로컬 접평면(미터).
nonisolated private struct LocalENU: Sendable {
    let originLatitude: Double
    let originLongitude: Double
    private let metersPerDegreeLatitude = 111_320.0

    init(origin: HikingPoint) {
        originLatitude = origin.latitude
        originLongitude = origin.longitude
    }

    func eastNorth(of point: HikingPoint) -> (east: Double, north: Double) {
        let metersPerDegreeLongitude = metersPerDegreeLatitude * cos(originLatitude * .pi / 180)
        return (
            east: (point.longitude - originLongitude) * metersPerDegreeLongitude,
            north: (point.latitude - originLatitude) * metersPerDegreeLatitude
        )
    }

    func point(
        east: Double,
        north: Double,
        template: HikingPoint,
        altitude: Double
    ) -> HikingPoint {
        let metersPerDegreeLongitude = metersPerDegreeLatitude * cos(originLatitude * .pi / 180)
        return HikingPoint(
            id: template.id,
            latitude: originLatitude + north / metersPerDegreeLatitude,
            longitude: originLongitude + east / metersPerDegreeLongitude,
            altitude: altitude,
            timestamp: template.timestamp,
            horizontalAccuracy: template.horizontalAccuracy
        )
    }
}
