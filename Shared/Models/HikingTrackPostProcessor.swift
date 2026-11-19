//
//  HikingTrackPostProcessor.swift
//  Shared
//
//  기록 종료 시 GPS 트랙 사후 보정(이상치 제거 → 정확도 가중 스무딩).
//  Xcode: Shared/Models 타겟 멤버십 → sansan, sansan Watch App
//

import CoreLocation
import Foundation

/// 기록 종료 후 위치 생산 기기에서 한 번 적용하는 GPS 트랙 사후 보정.
/// 각 포인트의 `id`·`timestamp`·`horizontalAccuracy`는 유지하고 좌표·고도만 조정합니다
/// — 사진·마커의 거리 매핑이 포인트 ID·시각에 의존하기 때문입니다.
nonisolated enum HikingTrackPostProcessor {
    /// 이보다 수평 정확도가 나쁜 포인트는 제거합니다(m). 정확도가 없는 구버전 포인트는 유지합니다.
    nonisolated static let maxHorizontalAccuracy: Double = 75
    /// 직전 유지 포인트 대비 이 속도(m/s)를 넘으면 그 시간에 사람이 낼 수 없는 이동으로 보고 제거합니다.
    /// 3.5m/s ≈ 12.6km/h — 능선 하산 돌발 가속은 통과시키고, GPS 텔레포트(시속 수십 km)는 잘라냅니다.
    nonisolated static let maxPlausibleSpeedMetersPerSecond: Double = 3.5
    /// 속도 이상치 판정을 적용할 최대 시간 간격(초) — 이보다 긴 공백은 일시정지로 보고 포인트를 유지합니다.
    nonisolated static let speedOutlierMaxGap: TimeInterval = 60
    /// 전후 점으로 스파이크를 볼 최대 시간(초). 실제 헤어핀은 A→C가 이보다 길어서 남습니다.
    nonisolated static let spikeLookaheadMaxGap: TimeInterval = 12
    /// A→B→C 우회가 직선 A→C보다 이 배율 이상이면 옆 튐으로 봅니다.
    nonisolated static let spikeMinDetourRatio: Double = 1.8
    /// 우회 여유 거리(m). 이보다 작은 꺾임은 실제 작은 커브로 둡니다.
    nonisolated static let spikeMinExtraMeters: CLLocationDistance = 8
    /// 스파이크로 볼 최소 회전각(도). 완만한 커브는 남깁니다.
    nonisolated static let spikeMinTurnDegrees: Double = 90
    /// A와 C가 이보다 가까울 때만 B를 삭제합니다. 멀면 A–C 직선으로 지름길이 생기므로
    /// 삭제 대신 그 시간에 도달 가능한 위치로 보정한 점을 남깁니다.
    nonisolated static let spikeMaxDirectMeters: CLLocationDistance = 20
    /// 방금 보정점을 남긴 뒤, 실제 GPS로 따라잡기 허용 속도(m/s, ≈21.6km/h).
    nonisolated static let catchUpMaxSpeedMetersPerSecond: Double = 6
    /// 스무딩 이동 평균 윈도(포인트 수, 중심 기준).
    nonisolated static let smoothingWindow = 5
    /// 이보다 긴 시간 공백은 구간 경계로 보고 스무딩 윈도가 넘지 않게 합니다(초).
    nonisolated static let segmentBoundaryGap: TimeInterval = 120
    /// 가중치 계산용 기본 정확도(m) — `horizontalAccuracy`가 없는 포인트에 적용합니다.
    nonisolated static let defaultAccuracyForWeight: Double = 15
    /// 가중치 계산용 정확도 하한(m) — 고정밀 포인트로의 지나친 편중을 막습니다.
    nonisolated static let minimumAccuracyForWeight: Double = 5

    /// 짧은 스파이크 삭제·MAP 보정 후 정확도 가중 이동 평균을 적용합니다.
    nonisolated static func process(_ points: [HikingPoint]) -> [HikingPoint] {
        guard points.count >= 3 else { return points }
        let sorted = points.sorted { $0.timestamp < $1.timestamp }
        let filtered = removingOutliers(from: sorted)
        return smoothed(filtered)
    }

    // MARK: - 1패스: 이상치 제거

    /// 짧은 왕복 스파이크만 삭제하고, 그 외 불가능한 점프는 가우시안 MAP 보정점을 남깁니다.
    /// A–C가 멀 때 B를 지우면 경로가 직선 지름길이 되므로 삭제하지 않습니다.
    nonisolated static func removingOutliers(from sorted: [HikingPoint]) -> [HikingPoint] {
        var kept: [HikingPoint] = []
        kept.reserveCapacity(sorted.count)
        var lastWasCorrected = false

        for index in sorted.indices {
            let point = sorted[index]
            if let accuracy = point.horizontalAccuracy, accuracy > maxHorizontalAccuracy {
                continue
            }
            guard let previous = kept.last else {
                kept.append(point)
                lastWasCorrected = false
                continue
            }
            let next = nextAccuratePoint(in: sorted, after: index)
            switch resolveOutlier(
                previous: previous,
                candidate: point,
                next: next,
                lastWasCorrected: lastWasCorrected
            ) {
            case .keep:
                kept.append(point)
                lastWasCorrected = false
            case .drop:
                lastWasCorrected = false
            case .correct:
                let prior = kept.count >= 2 ? kept[kept.count - 2] : nil
                kept.append(
                    HikingGPSStatisticalCorrection.correctedPoint(
                        previous: previous,
                        prior: prior,
                        candidate: point,
                        maxSpeedMetersPerSecond: maxPlausibleSpeedMetersPerSecond
                    )
                )
                lastWasCorrected = true
            }
        }
        return kept
    }

    /// 실시간 저장용 — 다음 점이 없으면 속도만 보고, 짧은 왕복 스파이크는 종료 보정에서 처리합니다.
    nonisolated static func shouldDropCandidate(
        previous: HikingPoint,
        candidate: HikingPoint,
        next: HikingPoint?
    ) -> Bool {
        resolveOutlier(
            previous: previous,
            candidate: candidate,
            next: next,
            lastWasCorrected: false
        ) == .drop
    }

    /// 직전 채택점부터 후보까지, 그 시간에 사람이 이동할 수 없는 속도면 true.
    nonisolated static func isImplausibleSpeed(from previous: HikingPoint, to candidate: HikingPoint) -> Bool {
        let gap = abs(candidate.timestamp.timeIntervalSince(previous.timestamp))
        guard gap > 0, gap <= speedOutlierMaxGap else { return false }
        let segment = HikingSessionMetrics.segmentDistance(from: previous, to: candidate)
        return segment / gap > maxPlausibleSpeedMetersPerSecond
    }

    nonisolated private enum OutlierResolution: Equatable, Sendable {
        case keep
        case drop
        case correct
    }

    nonisolated private static func resolveOutlier(
        previous: HikingPoint,
        candidate: HikingPoint,
        next: HikingPoint?,
        lastWasCorrected: Bool
    ) -> OutlierResolution {
        let closeReturnSpike = next.map {
            isLookaheadSpike(previous: previous, candidate: candidate, next: $0)
        } ?? false

        if closeReturnSpike {
            return .drop
        }

        if isImplausibleSpeed(from: previous, to: candidate) {
            if lastWasCorrected, canCatchUp(from: previous, to: candidate) {
                return .keep
            }
            return .correct
        }

        return .keep
    }

    /// 보정으로 뒤처진 뒤, 실제 GPS가 같은 방향으로 다시 잡히면 한 번은 원본을 받아 따라갑니다.
    nonisolated private static func canCatchUp(from previous: HikingPoint, to candidate: HikingPoint) -> Bool {
        let gap = abs(candidate.timestamp.timeIntervalSince(previous.timestamp))
        guard gap > 0, gap <= speedOutlierMaxGap else { return false }
        let segment = HikingSessionMetrics.segmentDistance(from: previous, to: candidate)
        return segment / gap <= catchUpMaxSpeedMetersPerSecond
    }

    /// A→B→C가 짧은 시간에 크게 우회하며 꺾이고, A와 C가 가까우면 B를 GPS 옆 튐으로 봅니다.
    /// C가 멀면 삭제 시 A–C가 지름길이 되므로 스파이크로 보지 않습니다.
    nonisolated private static func isLookaheadSpike(
        previous: HikingPoint,
        candidate: HikingPoint,
        next: HikingPoint
    ) -> Bool {
        let window = next.timestamp.timeIntervalSince(previous.timestamp)
        guard window > 0, window <= spikeLookaheadMaxGap else { return false }

        let outbound = HikingSessionMetrics.segmentDistance(from: previous, to: candidate)
        let inbound = HikingSessionMetrics.segmentDistance(from: candidate, to: next)
        let direct = HikingSessionMetrics.segmentDistance(from: previous, to: next)
        guard direct > 0, direct <= spikeMaxDirectMeters else { return false }

        let extra = outbound + inbound - direct
        let detourRatio = (outbound + inbound) / direct
        let turn = turnAngleDegrees(
            bearingDegrees(from: previous, to: candidate),
            bearingDegrees(from: candidate, to: next)
        )
        return extra >= spikeMinExtraMeters
            && detourRatio >= spikeMinDetourRatio
            && turn >= spikeMinTurnDegrees
    }

    nonisolated private static func nextAccuratePoint(in sorted: [HikingPoint], after index: Int) -> HikingPoint? {
        var look = index + 1
        while look < sorted.count {
            let point = sorted[look]
            if let accuracy = point.horizontalAccuracy, accuracy > maxHorizontalAccuracy {
                look += 1
                continue
            }
            return point
        }
        return nil
    }

    nonisolated private static func bearingDegrees(from start: HikingPoint, to end: HikingPoint) -> Double {
        let lat1 = start.latitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let deltaLon = (end.longitude - start.longitude) * .pi / 180
        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        return atan2(y, x) * 180 / .pi
    }

    nonisolated private static func turnAngleDegrees(_ first: Double, _ second: Double) -> Double {
        var diff = abs(first - second).truncatingRemainder(dividingBy: 360)
        if diff > 180 { diff = 360 - diff }
        return diff
    }

    // MARK: - 2패스: 정확도 가중 스무딩

    /// 중심 가중 이동 평균 — 정확도가 좋은 포인트일수록 큰 가중치로 위도·경도·고도를 평탄화합니다.
    /// `segmentBoundaryGap`을 넘는 공백(일시정지 등)은 구간 경계로 보고 윈도가 넘지 않게 합니다.
    nonisolated private static func smoothed(_ points: [HikingPoint]) -> [HikingPoint] {
        guard points.count >= 3 else { return points }

        // 각 포인트가 속한 구간 인덱스 — 시간 공백 기준으로 나눕니다.
        var segmentIndex = [Int](repeating: 0, count: points.count)
        var currentSegment = 0
        for index in 1..<points.count {
            let gap = points[index].timestamp.timeIntervalSince(points[index - 1].timestamp)
            if gap > segmentBoundaryGap {
                currentSegment += 1
            }
            segmentIndex[index] = currentSegment
        }

        let weights = points.map { point in
            1.0 / max(point.horizontalAccuracy ?? defaultAccuracyForWeight, minimumAccuracyForWeight)
        }
        let radius = max(smoothingWindow / 2, 1)

        return points.indices.map { index in
            var latitudeSum = 0.0
            var longitudeSum = 0.0
            var altitudeSum = 0.0
            var weightSum = 0.0

            let start = max(index - radius, 0)
            let end = min(index + radius, points.count - 1)
            for neighbor in start...end where segmentIndex[neighbor] == segmentIndex[index] {
                let weight = weights[neighbor]
                latitudeSum += points[neighbor].latitude * weight
                longitudeSum += points[neighbor].longitude * weight
                altitudeSum += points[neighbor].altitude * weight
                weightSum += weight
            }
            guard weightSum > 0 else { return points[index] }

            let original = points[index]
            return HikingPoint(
                id: original.id,
                latitude: latitudeSum / weightSum,
                longitude: longitudeSum / weightSum,
                altitude: altitudeSum / weightSum,
                timestamp: original.timestamp,
                horizontalAccuracy: original.horizontalAccuracy
            )
        }
    }
}
