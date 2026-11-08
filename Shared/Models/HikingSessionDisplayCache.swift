//
//  HikingSessionDisplayCache.swift
//  Shared
//
//  저장된 기록 표시용 — 기록 종료·GPX 가져오기 시 한 번 계산해 JSON에 함께 저장합니다.
//  GPS 필터링 없이 원본 포인트를 시간순 그대로 사용합니다.
//

import CoreLocation
import Foundation

/// 고도 프로필 차트 샘플(거리 축 기준).
nonisolated struct HikingElevationChartSample: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let distanceMeters: Double
    let altitude: Double
}

/// 심박수 프로필 차트 샘플(거리 축 기준).
nonisolated struct HikingHeartRateChartSample: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let distanceMeters: Double
    let bpm: Double
}

/// 지도 폴리라인용 좌표.
nonisolated struct HikingDisplayCoordinate: Codable, Hashable, Sendable {
    let latitude: Double
    let longitude: Double

    nonisolated var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum HikingSessionDisplayCacheBuilder {
    /// v3: 누적 거리 anchor 방식 수정(저속 보행 거리 유실 해결) 반영.
    /// v4: 고도 2패스 스무딩(윈도 21)·심박 스무딩 적용으로 프로필 차트 재계산.
    /// v5: 표시 경로 좌표에 약한 이동 평균(옆 튐 완화) 적용.
    /// v6: 표시 경로에 정지 드리프트 압축(노이즈 반경 5m) 적용 — 휴식·정상 체류 시 경로 꼬임 완화.
    /// v7: 이동 평균 스무딩 이동량을 2.5m로 제한 — 코너에서 경로가 건물 위로 잘려 들어가는 현상 방지.
    /// v8: 급반전 비율 기반 노이즈 트랙 판정 추가 — 숲·계곡 다중경로 지그재그 트랙은 코너 고정 없이
    ///     이동 한도 10m로 강하게 평균해 경로 엉킴·직선 튐을 완화.
    nonisolated static let cacheVersion = 8
    nonisolated static let maxElevationProfileSamples = 400
    nonisolated static let maxHeartRateProfileSamples = 400
    nonisolated static let maxDisplayRouteCoordinates = 2_000

    struct Built: Sendable {
        let elevationGainMeters: Double?
        let elevationProfile: [HikingElevationChartSample]?
        let heartRateProfile: [HikingHeartRateChartSample]?
        let displayRouteCoordinates: [HikingDisplayCoordinate]?
        let kilometerMarkers: [RouteKilometerMarkerPlacement]?
        let nearbySummits: [MountainSummit]?
    }

    nonisolated static func build(
        points: [HikingPoint],
        heartRateSamples: [HikingHeartRateSample]
    ) -> Built {
        guard points.count >= 2 else {
            return Built(
                elevationGainMeters: nil,
                elevationProfile: nil,
                heartRateProfile: nil,
                displayRouteCoordinates: nil,
                kilometerMarkers: nil,
                nearbySummits: nil
            )
        }

        let elevationGainMeters = HikingSessionMetrics.cumulativeElevationGain(from: points)

        let rawElevation = HikingSessionMetrics.elevationProfileSamples(from: points, smoothForDisplay: true)
        let elevationProfile = downsample(rawElevation, maxCount: maxElevationProfileSamples).map { sample in
            HikingElevationChartSample(
                id: sample.id,
                distanceMeters: sample.distanceMeters,
                altitude: sample.altitude
            )
        }

        let rawHeartRate = HikingSessionMetrics.heartRateProfileSamples(
            from: points,
            heartRateSamples: heartRateSamples
        )
        let heartRateProfile: [HikingHeartRateChartSample]?
        if rawHeartRate.isEmpty {
            heartRateProfile = nil
        } else {
            heartRateProfile = downsample(rawHeartRate, maxCount: maxHeartRateProfileSamples).map { sample in
                HikingHeartRateChartSample(
                    id: sample.id,
                    distanceMeters: sample.distanceMeters,
                    bpm: sample.bpm
                )
            }
        }

        let routeCoordinates = HikingSessionMetrics.routeCoordinates(from: points)
        let simplifiedCoordinates = downsample(
            routeCoordinates,
            maxCount: maxDisplayRouteCoordinates
        )
        let displayRouteCoordinates = simplifiedCoordinates.map {
            HikingDisplayCoordinate(latitude: $0.latitude, longitude: $0.longitude)
        }

        let kilometerMarkers = HikingSessionMetrics.kilometerMarkerPlacements(from: points)
        let nearbySummits = MountainSummitRouteFilter.summits(near: simplifiedCoordinates)

        return Built(
            elevationGainMeters: elevationGainMeters,
            elevationProfile: elevationProfile,
            heartRateProfile: heartRateProfile,
            displayRouteCoordinates: displayRouteCoordinates,
            kilometerMarkers: kilometerMarkers,
            nearbySummits: nearbySummits
        )
    }

    nonisolated private static func downsample<T>(
        _ samples: [T],
        maxCount: Int
    ) -> [T] {
        guard samples.count > maxCount, maxCount >= 2 else { return samples }

        var simplified: [T] = [samples[0]]
        let stride = Double(samples.count - 1) / Double(maxCount - 1)

        if maxCount > 2 {
            for index in 1..<(maxCount - 1) {
                let sourceIndex = min(Int((Double(index) * stride).rounded()), samples.count - 1)
                simplified.append(samples[sourceIndex])
            }
        }

        simplified.append(samples[samples.count - 1])
        return simplified
    }
}
