//
//  HikingSessionMetrics.swift
//  Shared
//

import CoreLocation
import Foundation

/// GPS 포인트에서 이동 거리·고도 상승을 계산하는 공통 로직.
enum HikingSessionMetrics {
    /// 연속 포인트 사이 이동으로 인정할 최소 수평 거리(m). 정지 상태 GPS 흔들림 제거.
    nonisolated static let minimumDistanceSegment: CLLocationDistance = 2
    /// 인간이 1초에 오를 수 있는 최대 고도(m/s). 이를 넘는 상승은 한도까지만 반영합니다.
    nonisolated static let maximumVerticalClimbRateMetersPerSecond: Double = 0.6
    /// 인간이 1초에 내릴 수 있는 최대 고도(m/s). 하강은 상승보다 빠를 수 있어 여유를 둡니다.
    nonisolated static let maximumVerticalDescentRateMetersPerSecond: Double = 1.2
    /// 고도 변화율 계산에 쓸 최소 시간 간격(초). 동일 시각 중복 포인트는 건너뜁니다.
    nonisolated static let minimumElevationRateInterval: TimeInterval = 0.1
    /// GPS 고도를 저장·누적할 때 인정할 최소 수평 이동(m). 정지·미세 흔들림의 수직 드리프트를 무시합니다.
    nonisolated static let minimumHorizontalForAltitudeUpdate: CLLocationDistance = 1
    /// 수평 이동 대비 허용 최대 경사(0.7 ≈ 35°). 가파른 등산 계단은 통과시키고
    /// 정지 직후 짧은 이동에 실린 큰 수직 스파이크만 잘라냅니다.
    nonisolated static let maximumPlausibleGrade: Double = 0.7
    /// 스무딩된 고도 변화가 이 속도(m/s)를 넘으면 GPX 트랙 텔레포트 등 비정상 구간으로 보고 제외합니다.
    nonisolated static let elevationTeleportRateMetersPerSecond: Double = 5
    /// 누적 상승·하강으로 인정할 최소 고도 변화(m). 기준 고도에서 이만큼 확실히 벗어나기 전까지의
    /// 잔여 흔들림(초당 ±0.3m 수준 GPS 노이즈)은 전부 무시합니다.
    nonisolated static let elevationCommitThresholdMeters: Double = 2
    /// GPS 수직 정확도가 이보다 나쁘면 직전 고도를 유지합니다.
    nonisolated static let acceptableVerticalAccuracy: Double = 15
    /// 고도 프로필 차트 표시용 이동 평균 윈도(포인트 수). 2패스로 적용해 GPS 수직 노이즈(초당 ±0.3m)를
    /// 충분히 평탄화하면서 전체 지형 형태는 유지합니다.
    nonisolated static let elevationProfileSmoothingWindow: Int = 21
    /// 심박 프로필 차트 표시용 이동 평균 윈도(샘플 수). 박동 간 노이즈를 완화해 추세를 보여줍니다.
    nonisolated static let heartRateProfileSmoothingWindow: Int = 7
    /// 누적 상승·하강 계산용 이동 평균 윈도(포인트 수).
    nonisolated static let elevationGainSmoothingWindow: Int = 15

    /// 지도·스냅샷 표시용 경로 좌표. 거리·고도 계산과 무관하게 표시 전용으로 약한 이동 평균을 적용해
    /// 한두 포인트가 옆으로 튀어 생기는 작은 꼬임을 완화합니다(거리 계산은 원본 포인트 기준 그대로).
    nonisolated static let routeDisplaySmoothingWindow = 5

    /// 이동 평균 스무딩이 원본 포인트에서 좌표를 옮길 수 있는 최대 거리(m).
    /// 미세한 옆 튐은 평탄화하되, 코너에서 이웃 평균이 경로를 안쪽(건물 위)으로 크게 잘라먹지 않도록
    /// 표시 좌표가 실제 GPS 포인트에서 이 거리 이상 벗어나지 않게 제한합니다.
    nonisolated static let routeDisplayMaxSmoothingShift: CLLocationDistance = 2.5

    /// 표시 경로에서 제자리 GPS 드리프트로 생기는 꼬임을 줄이기 위한 노이즈 반경(m).
    /// 마지막으로 채택한 점에서 이 반경 안에 머무는 점들은 같은 자리로 보고 표시에서 건너뜁니다.
    /// (거리·고도 계산에는 영향 없음 — 원본 포인트는 그대로 보존됩니다.)
    nonisolated static let routeDisplayStationaryRadius: CLLocationDistance = 5

    /// 실제 코너(방향 전환)로 보고 평균에서 제외할 회전각 임계값(도).
    /// 도시 격자처럼 직선을 걷다 직각으로 꺾이는 길은 코너를 평균으로 깎으면 경로가 왜곡되므로,
    /// 이 각도 이상으로 방향이 꺾이는 점은 원본 그대로 유지하고 그 코너를 넘어서 평균하지 않습니다.
    nonisolated static let routeDisplayCornerAngleThreshold: Double = 24

    /// 노이즈 트랙 판정 — 연속 세그먼트가 100° 이상 꺾이는(사실상 되돌아가는) 비율이
    /// 이 값 이상이면 숲·계곡 GPS 다중경로로 좌우 튐이 심한 트랙으로 봅니다.
    /// 실측: 정상 트랙 0.5~2%, 다중경로 트랙 15% 이상.
    nonisolated static let noisyTrackReversalRatioThreshold: Double = 0.06
    /// 반전 비율 계산에 포함할 최소 세그먼트 길이(m). 미세 흔들림은 제외합니다.
    nonisolated static let noisyTrackMinimumSegmentMeters: CLLocationDistance = 3
    /// 반전으로 판정할 최소 회전각(도).
    nonisolated static let noisyTrackReversalAngleDegrees: Double = 100
    /// 노이즈 트랙 전용 스무딩 이동 한도(m). 좌우 ±10m 수준 다중경로 튐을 펴려면
    /// 평균 좌표가 원본에서 그만큼 움직일 수 있어야 합니다.
    nonisolated static let noisyRouteMaxSmoothingShift: CLLocationDistance = 10

    nonisolated static func routeCoordinates(from points: [HikingPoint]) -> [CLLocationCoordinate2D] {
        let ordered = points.sorted { $0.timestamp < $1.timestamp }.map(\.coordinate)
        let collapsed = collapsedStationaryDrift(ordered, radius: routeDisplayStationaryRadius)
        if reversalRatio(of: collapsed) >= noisyTrackReversalRatioThreshold {
            // 다중경로 지그재그 트랙: 큰 꺾임도 노이즈이므로 코너 고정 없이 강하게 평균합니다.
            return smoothedRouteCoordinates(
                collapsed,
                window: routeDisplaySmoothingWindow,
                maxShift: noisyRouteMaxSmoothingShift,
                cornerAngleThreshold: nil
            )
        }
        return smoothedRouteCoordinates(
            collapsed,
            window: routeDisplaySmoothingWindow,
            maxShift: routeDisplayMaxSmoothingShift,
            cornerAngleThreshold: routeDisplayCornerAngleThreshold
        )
    }

    /// 세그먼트(각 `noisyTrackMinimumSegmentMeters` 이상)가 급반전하는 비율.
    nonisolated private static func reversalRatio(of coordinates: [CLLocationCoordinate2D]) -> Double {
        guard coordinates.count >= 16 else { return 0 }
        var reversals = 0
        var measurable = 0
        for index in 1..<(coordinates.count - 1) {
            let previous = CLLocation(
                latitude: coordinates[index - 1].latitude,
                longitude: coordinates[index - 1].longitude
            )
            let current = CLLocation(
                latitude: coordinates[index].latitude,
                longitude: coordinates[index].longitude
            )
            let next = CLLocation(
                latitude: coordinates[index + 1].latitude,
                longitude: coordinates[index + 1].longitude
            )
            guard current.distance(from: previous) >= noisyTrackMinimumSegmentMeters,
                  next.distance(from: current) >= noisyTrackMinimumSegmentMeters else { continue }
            measurable += 1
            let inBearing = bearingDegrees(from: coordinates[index - 1], to: coordinates[index])
            let outBearing = bearingDegrees(from: coordinates[index], to: coordinates[index + 1])
            if turnAngleDegrees(inBearing, outBearing) >= noisyTrackReversalAngleDegrees {
                reversals += 1
            }
        }
        guard measurable >= 8 else { return 0 }
        return Double(reversals) / Double(measurable)
    }

    /// 일시정지~재개 사이 GPS 포인트인지 여부.
    nonisolated static func isTimestampDuringPausedInterval(
        _ timestamp: Date,
        segmentBreaks: [HikingSegmentBreak]?
    ) -> Bool {
        guard let breaks = segmentBreaks, !breaks.isEmpty else { return false }
        for segmentBreak in breaks {
            guard timestamp >= segmentBreak.pauseTime else { continue }
            if let resumeTime = segmentBreak.resumeTime {
                if timestamp < resumeTime { return true }
            } else {
                return true
            }
        }
        return false
    }

    /// 일시정지 동안 수집된 GPS 포인트를 제거합니다.
    nonisolated static func pointsExcludingPausedIntervals(
        _ points: [HikingPoint],
        segmentBreaks: [HikingSegmentBreak]?
    ) -> [HikingPoint] {
        points.filter {
            !isTimestampDuringPausedInterval($0.timestamp, segmentBreaks: segmentBreaks)
        }
    }

    /// 라이브 지도용 — 일시정지 구간마다 경로선을 끊어 그립니다.
    nonisolated static func liveRouteSegments(
        from points: [HikingPoint],
        segmentBreaks: [HikingSegmentBreak]?
    ) -> [[CLLocationCoordinate2D]] {
        let filtered = pointsExcludingPausedIntervals(points, segmentBreaks: segmentBreaks)
            .sorted { $0.timestamp < $1.timestamp }
        guard filtered.count >= 2 else { return [] }

        guard let breaks = segmentBreaks?.sorted(by: { $0.pauseTime < $1.pauseTime }),
              !breaks.isEmpty else {
            let coords = routeCoordinates(from: filtered)
            return coords.count >= 2 ? [coords] : []
        }

        var segments: [[HikingPoint]] = []
        var chunk: [HikingPoint] = []

        for point in filtered {
            if let last = chunk.last,
               breaks.contains(where: { segmentBreak in
                   guard let resumeTime = segmentBreak.resumeTime else { return false }
                   return last.timestamp < resumeTime && point.timestamp >= resumeTime
               }) {
                if chunk.count >= 2 { segments.append(chunk) }
                chunk = [point]
            } else {
                chunk.append(point)
            }
        }
        if chunk.count >= 2 { segments.append(chunk) }

        return segments.compactMap { segment in
            let coords = routeCoordinates(from: segment)
            return coords.count >= 2 ? coords : nil
        }
    }

    /// 마지막 채택점에서 일정 반경 이상 벗어난 점만 남겨 정지 중 드리프트 꼬임을 제거합니다.
    /// 시작·종료 좌표는 항상 보존합니다.
    nonisolated private static func collapsedStationaryDrift(
        _ coordinates: [CLLocationCoordinate2D],
        radius: CLLocationDistance
    ) -> [CLLocationCoordinate2D] {
        guard coordinates.count >= 3 else { return coordinates }
        var result: [CLLocationCoordinate2D] = [coordinates[0]]
        var anchor = CLLocation(latitude: coordinates[0].latitude, longitude: coordinates[0].longitude)
        for index in 1..<(coordinates.count - 1) {
            let candidate = CLLocation(
                latitude: coordinates[index].latitude,
                longitude: coordinates[index].longitude
            )
            if candidate.distance(from: anchor) >= radius {
                result.append(coordinates[index])
                anchor = candidate
            }
        }
        result.append(coordinates[coordinates.count - 1])
        return result
    }

    /// 끝점·코너는 원본 그대로 두고, 코너 사이 직선 구간의 내부 점만 이웃과 평균합니다.
    /// 평균 윈도는 인접한 코너를 넘지 않으므로 직각 코너가 안쪽으로 깎이지 않고,
    /// 직선 위에서 한두 점이 옆으로 튀는 지그재그 노이즈만 평탄화됩니다.
    /// `cornerAngleThreshold`가 nil이면 코너 고정 없이 전 구간을 평균합니다(노이즈 트랙 전용).
    nonisolated private static func smoothedRouteCoordinates(
        _ coordinates: [CLLocationCoordinate2D],
        window: Int,
        maxShift: CLLocationDistance,
        cornerAngleThreshold: Double?
    ) -> [CLLocationCoordinate2D] {
        guard coordinates.count >= 3, window >= 3 else { return coordinates }
        let radius = max(window / 2, 1)
        let lastIndex = coordinates.count - 1

        // 1) 실제 코너 탐지 — 노이즈 1점 튐이 아니라 lookahead 구간에 걸쳐 유지되는 방향 전환만 코너로 봅니다.
        let corners: [Bool]
        if let cornerAngleThreshold {
            corners = cornerFlags(
                coordinates,
                lookahead: radius,
                angleThreshold: cornerAngleThreshold
            )
        } else {
            corners = [Bool](repeating: false, count: coordinates.count)
        }

        // 2) 각 점에서 좌·우로 가장 가까운 경계(코너 또는 끝점) 인덱스를 미리 계산.
        var leftBound = [Int](repeating: 0, count: coordinates.count)
        var lastBoundary = 0
        for index in coordinates.indices {
            if index == 0 || index == lastIndex || corners[index] { lastBoundary = index }
            leftBound[index] = lastBoundary
        }
        var rightBound = [Int](repeating: lastIndex, count: coordinates.count)
        var nextBoundary = lastIndex
        for index in stride(from: lastIndex, through: 0, by: -1) {
            if index == 0 || index == lastIndex || corners[index] { nextBoundary = index }
            rightBound[index] = nextBoundary
        }

        // 3) 코너 사이 직선 구간 안에서만 평균.
        return coordinates.indices.map { index in
            if index == 0 || index == lastIndex || corners[index] { return coordinates[index] }
            let start = max(index - radius, leftBound[index])
            let end = min(index + radius, rightBound[index])
            guard end > start else { return coordinates[index] }
            var latitude = 0.0
            var longitude = 0.0
            for i in start...end {
                latitude += coordinates[i].latitude
                longitude += coordinates[i].longitude
            }
            let count = Double(end - start + 1)
            let averaged = CLLocationCoordinate2D(latitude: latitude / count, longitude: longitude / count)
            return clamped(
                averaged,
                toward: coordinates[index],
                maxShift: maxShift
            )
        }
    }

    /// 각 내부 점이 실제 코너인지 표시합니다. lookahead 만큼 떨어진 점 기준의 진입·진출 방위 차이를
    /// 사용해, 단일 점 노이즈로 생기는 큰 각도 변화(앞뒤로 상쇄됨)는 코너로 오인하지 않습니다.
    nonisolated private static func cornerFlags(
        _ coordinates: [CLLocationCoordinate2D],
        lookahead: Int,
        angleThreshold: Double
    ) -> [Bool] {
        var flags = [Bool](repeating: false, count: coordinates.count)
        guard coordinates.count >= 3 else { return flags }
        let span = max(lookahead, 1)
        let lastIndex = coordinates.count - 1
        for index in 1..<lastIndex {
            let back = max(0, index - span)
            let forward = min(lastIndex, index + span)
            guard back < index, forward > index else { continue }
            let inBearing = bearingDegrees(from: coordinates[back], to: coordinates[index])
            let outBearing = bearingDegrees(from: coordinates[index], to: coordinates[forward])
            if turnAngleDegrees(inBearing, outBearing) >= angleThreshold {
                flags[index] = true
            }
        }
        return flags
    }

    /// 두 좌표 사이의 초기 방위(도, -180...180).
    nonisolated private static func bearingDegrees(
        from a: CLLocationCoordinate2D,
        to b: CLLocationCoordinate2D
    ) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let deltaLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        return atan2(y, x) * 180 / .pi
    }

    /// 두 방위 사이의 최소 회전각(0...180도).
    nonisolated private static func turnAngleDegrees(_ first: Double, _ second: Double) -> Double {
        var diff = abs(first - second).truncatingRemainder(dividingBy: 360)
        if diff > 180 { diff = 360 - diff }
        return diff
    }

    /// 스무딩된 좌표가 원본에서 `maxShift`(m)를 넘게 벗어나면 원본 쪽으로 끌어당겨 제한합니다.
    nonisolated private static func clamped(
        _ smoothed: CLLocationCoordinate2D,
        toward original: CLLocationCoordinate2D,
        maxShift: CLLocationDistance
    ) -> CLLocationCoordinate2D {
        let shift = CLLocation(latitude: smoothed.latitude, longitude: smoothed.longitude)
            .distance(from: CLLocation(latitude: original.latitude, longitude: original.longitude))
        guard shift > maxShift, shift > 0 else { return smoothed }
        let ratio = maxShift / shift
        return CLLocationCoordinate2D(
            latitude: original.latitude + (smoothed.latitude - original.latitude) * ratio,
            longitude: original.longitude + (smoothed.longitude - original.longitude) * ratio
        )
    }

    /// 저장된 표시 캐시가 있으면 우선 사용하고, 없으면 포인트에서 계산합니다.
    nonisolated static func resolvedDisplayRouteCoordinates(from session: HikingSessionData) -> [CLLocationCoordinate2D] {
        if session.hasPersistedDisplayCache,
           let stored = session.displayRouteCoordinates {
            return stored.map(\.coordinate)
        }
        return routeCoordinates(from: session.points)
    }

    /// 시간순 포인트의 수평 이동 거리 합(미터).
    /// anchor(마지막으로 거리에 반영한 지점) 기준 누적 — 연속 포인트 간격이 2m 미만인 저속 보행도
    /// 정확히 합산하고, 정지 상태에서 2m 미만으로 흔들리는 GPS 노이즈만 제외합니다.
    nonisolated static func horizontalDistance(from points: [HikingPoint]) -> Double {
        horizontalDistanceWithAnchor(from: points).total
    }

    /// 이동으로 인정할 최소 변위 — GPS 노이즈 반경(수평 정확도)보다 작은 변위는 제자리 흔들림으로 봅니다.
    nonisolated static func distanceAnchorThreshold(for point: HikingPoint) -> CLLocationDistance {
        max(minimumDistanceSegment, point.horizontalAccuracy ?? 0)
    }

    /// 누적 거리와 마지막 anchor 포인트 — 실시간 증분 누적을 이어가기 위한 시드.
    nonisolated static func horizontalDistanceWithAnchor(
        from points: [HikingPoint]
    ) -> (total: Double, anchor: HikingPoint?) {
        guard !points.isEmpty else { return (0, nil) }
        let sorted = points.sorted { $0.timestamp < $1.timestamp }
        var anchor = sorted[0]
        var total: CLLocationDistance = 0

        for point in sorted.dropFirst() {
            let segment = segmentDistance(from: anchor, to: point)
            if segment >= distanceAnchorThreshold(for: point) {
                total += segment
                anchor = point
            }
        }
        return (total, anchor)
    }

    /// 시간순 정렬된 포인트 각각의 anchor 기준 누적 거리(미터).
    nonisolated static func cumulativeDistances(forSorted sorted: [HikingPoint]) -> [CLLocationDistance] {
        guard !sorted.isEmpty else { return [] }
        var distances: [CLLocationDistance] = [0]
        distances.reserveCapacity(sorted.count)
        var anchor = sorted[0]
        var cumulative: CLLocationDistance = 0

        for point in sorted.dropFirst() {
            let segment = segmentDistance(from: anchor, to: point)
            if segment >= distanceAnchorThreshold(for: point) {
                cumulative += segment
                anchor = point
            }
            distances.append(cumulative)
        }
        return distances
    }

    /// GPS 고도에 경사·속도 한도를 적용해 저장할 값을 결정합니다.
    /// 한도를 넘는 변화는 거부하지 않고 한도까지만 반영(clamp)합니다 — 거부 방식은 가파른 오르막에서
    /// 직전 고도와의 차이가 계속 커져 고도가 영영 갱신되지 않는 문제가 있습니다.
    nonisolated static func storedAltitude(
        proposed: Double,
        previousAltitude: Double,
        horizontalMeters: CLLocationDistance,
        elapsedSeconds: TimeInterval
    ) -> Double {
        guard horizontalMeters >= minimumHorizontalForAltitudeUpdate else {
            return previousAltitude
        }

        let delta = proposed - previousAltitude
        let elapsed = max(elapsedSeconds, minimumElevationRateInterval)
        let gradeCap = horizontalMeters * maximumPlausibleGrade
        let maxClimb = min(maximumVerticalClimbRateMetersPerSecond * elapsed, gradeCap)
        let maxDescent = min(maximumVerticalDescentRateMetersPerSecond * elapsed, gradeCap)

        return previousAltitude + min(max(delta, -maxDescent), maxClimb)
    }

    /// 스무딩된 고도가 기준점에서 `elevationCommitThresholdMeters` 이상 확실히 벗어났을 때만
    /// 상승·하강으로 누적합니다(래칫 방식). 임계값 미만의 GPS 흔들림은 전부 무시되고,
    /// 기준점 이후 이동 거리에 비해 비정상적으로 큰 고도 변화(정지 중 드리프트)는 버립니다.
    nonisolated static func elevationChanges(from points: [HikingPoint]) -> (gain: Double, loss: Double) {
        guard points.count >= 2 else { return (0, 0) }

        let sorted = points.sorted { $0.timestamp < $1.timestamp }
        let smoothed = smoothAltitudes(from: sorted, window: elevationGainSmoothingWindow)
        var gain = 0.0
        var loss = 0.0
        var reference = smoothed[0]
        var movedSinceReference: CLLocationDistance = 0

        for index in 1..<sorted.count {
            let elapsed = sorted[index].timestamp.timeIntervalSince(sorted[index - 1].timestamp)
            movedSinceReference += segmentDistance(from: sorted[index - 1], to: sorted[index])

            // 텔레포트(GPX 가져오기 등 비정상 점프) — 기준만 옮기고 누적하지 않습니다.
            if elapsed >= minimumElevationRateInterval,
               abs(smoothed[index] - smoothed[index - 1]) > elevationTeleportRateMetersPerSecond * elapsed {
                reference = smoothed[index]
                movedSinceReference = 0
                continue
            }

            let delta = smoothed[index] - reference
            guard abs(delta) >= elevationCommitThresholdMeters else { continue }

            if abs(delta) <= movedSinceReference * maximumPlausibleGrade {
                if delta > 0 {
                    gain += delta
                } else {
                    loss += -delta
                }
            }
            reference = smoothed[index]
            movedSinceReference = 0
        }
        return (gain, loss)
    }

    nonisolated private static func smoothAltitudes(from points: [HikingPoint], window: Int) -> [Double] {
        guard points.count >= 3 else { return points.map(\.altitude) }

        let radius = max(window / 2, 1)
        return points.indices.map { index in
            let start = max(index - radius, 0)
            let end = min(index + radius, points.count - 1)
            let neighbors = points[start...end]
            return neighbors.map(\.altitude).reduce(0, +) / Double(neighbors.count)
        }
    }

    /// 누적 상승 고도(m).
    nonisolated static func cumulativeElevationGain(from points: [HikingPoint]) -> Double {
        elevationChanges(from: points).gain
    }

    /// 지정 거리(m)까지의 누적 상승 고도(m). 영상 HUD 등 진행률 기준 표시용.
    nonisolated static func cumulativeElevationGain(
        from points: [HikingPoint],
        upToDistance targetDistance: Double
    ) -> Double {
        guard targetDistance > 0 else { return 0 }
        let truncated = truncatedPoints(upToDistance: targetDistance, from: points)
        guard truncated.count >= 2 else { return 0 }
        return cumulativeElevationGain(from: truncated)
    }

    /// 경로 누적 거리(m)까지의 GPS 샘플. 마지막 구간은 보간해 포함합니다.
    nonisolated static func truncatedPoints(
        upToDistance targetDistance: Double,
        from points: [HikingPoint]
    ) -> [HikingPoint] {
        guard targetDistance > 0 else { return [] }

        let sorted = points.sorted { $0.timestamp < $1.timestamp }
        guard sorted.count >= 2 else { return sorted }

        let cumulative = cumulativeDistances(forSorted: sorted)
        guard let total = cumulative.last, total > 0 else { return Array(sorted.prefix(1)) }
        if targetDistance >= total { return sorted }

        var result: [HikingPoint] = []
        for index in sorted.indices {
            if cumulative[index] <= targetDistance {
                result.append(sorted[index])
                continue
            }

            guard index > 0 else { break }
            let lower = index - 1
            if cumulative[lower] >= targetDistance { break }

            let span = cumulative[index] - cumulative[lower]
            let t = span > 0 ? (targetDistance - cumulative[lower]) / span : 0
            let from = sorted[lower]
            let to = sorted[index]
            let elapsed = to.timestamp.timeIntervalSince(from.timestamp)
            result.append(
                HikingPoint(
                    latitude: from.latitude + (to.latitude - from.latitude) * t,
                    longitude: from.longitude + (to.longitude - from.longitude) * t,
                    altitude: from.altitude + (to.altitude - from.altitude) * t,
                    timestamp: from.timestamp.addingTimeInterval(elapsed * t)
                )
            )
            break
        }

        return result
    }

    /// 누적 하강 고도(m).
    nonisolated static func cumulativeElevationLoss(from points: [HikingPoint]) -> Double {
        elevationChanges(from: points).loss
    }

    /// 경로 누적 거리(미터) 기준 고도 프로필 샘플 — 차트 X축용.
    nonisolated static func elevationProfileSamples(
        from points: [HikingPoint],
        smoothForDisplay: Bool = true
    ) -> [(id: UUID, distanceMeters: Double, altitude: Double)] {
        guard !points.isEmpty else { return [] }

        let sorted = points.sorted { $0.timestamp < $1.timestamp }
        let distances = cumulativeDistances(forSorted: sorted)
        let samples = sorted.indices.map { index in
            (id: sorted[index].id, distanceMeters: distances[index], altitude: sorted[index].altitude)
        }

        guard smoothForDisplay, samples.count >= 3 else { return samples }
        return smoothElevationProfileSamples(samples, window: elevationProfileSmoothingWindow)
    }

    nonisolated private static func smoothElevationProfileSamples(
        _ samples: [(id: UUID, distanceMeters: Double, altitude: Double)],
        window: Int
    ) -> [(id: UUID, distanceMeters: Double, altitude: Double)] {
        // 이동 평균 2패스 ≈ 가우시안 — 1패스보다 잔여 톱니를 크게 줄입니다.
        let firstPass = movingAverageAltitudes(samples.map(\.altitude), window: window)
        let secondPass = movingAverageAltitudes(firstPass, window: window)
        return samples.indices.map { index in
            (id: samples[index].id, distanceMeters: samples[index].distanceMeters, altitude: secondPass[index])
        }
    }

    nonisolated private static func movingAverageAltitudes(_ values: [Double], window: Int) -> [Double] {
        guard values.count >= 3 else { return values }
        let radius = max(window / 2, 1)
        return values.indices.map { index in
            let start = max(index - radius, 0)
            let end = min(index + radius, values.count - 1)
            var sum = 0.0
            for i in start...end { sum += values[i] }
            return sum / Double(end - start + 1)
        }
    }

    /// 경로 누적 거리(미터) 기준 심박수 프로필 샘플 — 고도 프로필 차트 X축과 동일.
    nonisolated static func heartRateProfileSamples(
        from points: [HikingPoint],
        heartRateSamples: [HikingHeartRateSample]
    ) -> [(id: UUID, distanceMeters: Double, bpm: Double)] {
        guard points.count >= 2, !heartRateSamples.isEmpty else { return [] }

        let timeline = distanceTimeline(from: points)
        guard let firstTimestamp = timeline.first?.timestamp,
              let lastTimestamp = timeline.last?.timestamp else { return [] }

        let mapped = heartRateSamples
            .sorted { $0.timestamp < $1.timestamp }
            .compactMap { sample -> (id: UUID, distanceMeters: Double, bpm: Double)? in
                guard sample.timestamp >= firstTimestamp,
                      sample.timestamp <= lastTimestamp else { return nil }
                let distance = distanceMeters(at: sample.timestamp, along: timeline)
                return (id: sample.id, distanceMeters: distance, bpm: sample.bpm)
            }

        return smoothHeartRateProfileSamples(mapped, window: heartRateProfileSmoothingWindow)
    }

    /// 심박 프로필 표시용 이동 평균 — 박동 간 노이즈를 줄여 추세선을 안정적으로 보여줍니다.
    nonisolated private static func smoothHeartRateProfileSamples(
        _ samples: [(id: UUID, distanceMeters: Double, bpm: Double)],
        window: Int
    ) -> [(id: UUID, distanceMeters: Double, bpm: Double)] {
        guard samples.count >= 3 else { return samples }
        let radius = max(window / 2, 1)
        return samples.indices.map { index in
            let start = max(index - radius, 0)
            let end = min(index + radius, samples.count - 1)
            var sum = 0.0
            for i in start...end { sum += samples[i].bpm }
            return (
                id: samples[index].id,
                distanceMeters: samples[index].distanceMeters,
                bpm: sum / Double(end - start + 1)
            )
        }
    }

    /// 경로 누적 거리 1km, 2km… 지점 좌표 (기록 상세 지도 라벨용).
    nonisolated static func kilometerMarkerPlacements(from points: [HikingPoint]) -> [RouteKilometerMarkerPlacement] {
        guard points.count >= 2 else { return [] }

        let sorted = points.sorted { $0.timestamp < $1.timestamp }
        let distances = cumulativeDistances(forSorted: sorted)
        var nextKilometer = 1
        var markers: [RouteKilometerMarkerPlacement] = []

        for index in 1..<sorted.count {
            let start = sorted[index - 1]
            let end = sorted[index]
            let segmentStart = distances[index - 1]
            let segmentEnd = distances[index]
            let segment = segmentEnd - segmentStart
            guard segment > 0 else { continue }

            while Double(nextKilometer) * 1_000 <= segmentEnd {
                let targetMeters = Double(nextKilometer) * 1_000
                if targetMeters > segmentStart {
                    let ratio = (targetMeters - segmentStart) / segment
                    let latitude = start.latitude + (end.latitude - start.latitude) * ratio
                    let longitude = start.longitude + (end.longitude - start.longitude) * ratio
                    markers.append(
                        RouteKilometerMarkerPlacement(
                            kilometer: nextKilometer,
                            latitude: latitude,
                            longitude: longitude
                        )
                    )
                }
                nextKilometer += 1
            }
        }

        return markers
    }

    nonisolated private static func distanceTimeline(
        from points: [HikingPoint]
    ) -> [(timestamp: Date, distanceMeters: Double)] {
        let sorted = points.sorted { $0.timestamp < $1.timestamp }
        let distances = cumulativeDistances(forSorted: sorted)
        return sorted.indices.map { (sorted[$0].timestamp, distances[$0]) }
    }

    nonisolated private static func distanceMeters(
        at timestamp: Date,
        along timeline: [(timestamp: Date, distanceMeters: Double)]
    ) -> Double {
        guard let first = timeline.first else { return 0 }
        if timestamp <= first.timestamp { return first.distanceMeters }
        if let last = timeline.last, timestamp >= last.timestamp { return last.distanceMeters }

        for index in 1..<timeline.count {
            let end = timeline[index]
            if timestamp <= end.timestamp {
                let start = timeline[index - 1]
                let duration = end.timestamp.timeIntervalSince(start.timestamp)
                guard duration > 0 else { return end.distanceMeters }
                let ratio = timestamp.timeIntervalSince(start.timestamp) / duration
                return start.distanceMeters + (end.distanceMeters - start.distanceMeters) * ratio
            }
        }
        return timeline.last?.distanceMeters ?? 0
    }

    nonisolated static func segmentDistance(from start: HikingPoint, to end: HikingPoint) -> CLLocationDistance {
        let startLocation = CLLocation(latitude: start.latitude, longitude: start.longitude)
        let endLocation = CLLocation(latitude: end.latitude, longitude: end.longitude)
        return endLocation.distance(from: startLocation)
    }
}

/// 경로상 1km 단위 거리 라벨 위치.
nonisolated struct RouteKilometerMarkerPlacement: Identifiable, Hashable, Sendable, Codable {
    let kilometer: Int
    let latitude: Double
    let longitude: Double

    var id: Int { kilometer }

    nonisolated var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var labelText: String { "\(kilometer)km" }

    /// 홀수 km는 오른쪽, 짝수 km는 왼쪽 — 라벨이 서로 겹치지 않도록 번갈아 배치.
    var placesLabelOnLeadingSide: Bool { kilometer.isMultiple(of: 2) }
}
