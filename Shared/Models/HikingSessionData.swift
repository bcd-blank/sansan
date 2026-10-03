//
//  HikingSessionData.swift
//  Shared
//
//  iPhone · Apple Watch 공통 세션 스냅샷 모델.
//  Xcode: Shared/Models 타겟 멤버십 → sansan, sansan Watch App
//

import CoreLocation
import Foundation

/// 일시정지 → 재개 구간 표시용 마킹.
/// 일시정지 순간의 좌표(`pause*`)와 재개 순간의 좌표(`resume*`)를 함께 보관해
/// 지도에서 같은 지점이면 한 마커에 두 색을, 다른 지점이면 각각 마커를 그립니다.
nonisolated struct HikingSegmentBreak: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    var pauseLatitude: Double
    var pauseLongitude: Double
    var pauseTime: Date
    var resumeLatitude: Double?
    var resumeLongitude: Double?
    var resumeTime: Date?

    nonisolated init(
        id: UUID = UUID(),
        pauseLatitude: Double,
        pauseLongitude: Double,
        pauseTime: Date,
        resumeLatitude: Double? = nil,
        resumeLongitude: Double? = nil,
        resumeTime: Date? = nil
    ) {
        self.id = id
        self.pauseLatitude = pauseLatitude
        self.pauseLongitude = pauseLongitude
        self.pauseTime = pauseTime
        self.resumeLatitude = resumeLatitude
        self.resumeLongitude = resumeLongitude
        self.resumeTime = resumeTime
    }

    nonisolated var pauseCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: pauseLatitude, longitude: pauseLongitude)
    }

    nonisolated var resumeCoordinate: CLLocationCoordinate2D? {
        guard let resumeLatitude, let resumeLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: resumeLatitude, longitude: resumeLongitude)
    }
}

/// 기록 세션의 라이브/동기화 스냅샷.
nonisolated struct HikingSessionData: Codable, Hashable, Sendable {
    var sessionID: UUID
    var state: HikingSessionState

    /// 기록 시작 시각(일시정지 제외한 경과 시간 계산 기준).
    var startedAt: Date?
    /// 누적 이동 거리(미터).
    var totalDistance: Double
    /// 경과 시간(초).
    var elapsedTime: TimeInterval
    /// 현재 페이스(분/km). 거리가 부족하면 nil.
    var currentPace: Double?
    /// 현재 고도(미터).
    var currentAltitude: Double
    /// 수집된 GPS 포인트(시간순).
    var points: [HikingPoint]
    /// 기록 중 촬영한 사진(이미지 파일은 iPhone 로컬 저장).
    var photos: [HikingTrailPhoto]
    /// 심박수 측정 샘플(시간순).
    var heartRateSamples: [HikingHeartRateSample]
    /// 최근 심박수(bpm). 샘플이 없으면 nil.
    var currentHeartRate: Double?
    /// 기록 구간 누적 걸음수(Core Motion). 미수집·미지원이면 nil.
    var stepCount: Int?
    /// 활성 칼로리(kcal). 워치는 HealthKit 실측, 아이폰 단독은 추정값. 미수집이면 nil.
    var activeEnergyKilocalories: Double?
    /// 일시정지/재개 구간 마킹(구버전 데이터는 nil).
    var segmentBreaks: [HikingSegmentBreak]?
    /// 저장·목록 표시용 누적 상승 고도(미터). `finalizeForPersistence()`에서 채웁니다.
    var elevationGainMeters: Double?
    /// 저장 시 계산한 고도 프로필 차트 샘플.
    var elevationProfile: [HikingElevationChartSample]?
    /// 저장 시 계산한 심박수 프로필 차트 샘플.
    var heartRateProfile: [HikingHeartRateChartSample]?
    /// 저장 시 계산한 지도 폴리라인 좌표.
    var displayRouteCoordinates: [HikingDisplayCoordinate]?
    /// 저장 시 계산한 km 마커.
    var kilometerMarkers: [RouteKilometerMarkerPlacement]?
    /// 저장 시 계산한 인근 정상.
    var nearbySummits: [MountainSummit]?
    /// `displayRouteCoordinates` 등 표시 캐시 생성 버전.
    var displayCacheVersion: Int?
    var lastUpdated: Date

    nonisolated init(
        sessionID: UUID = UUID(),
        state: HikingSessionState = .idle,
        startedAt: Date? = nil,
        totalDistance: Double = 0,
        elapsedTime: TimeInterval = 0,
        currentPace: Double? = nil,
        currentAltitude: Double = 0,
        points: [HikingPoint] = [],
        photos: [HikingTrailPhoto] = [],
        heartRateSamples: [HikingHeartRateSample] = [],
        currentHeartRate: Double? = nil,
        stepCount: Int? = nil,
        activeEnergyKilocalories: Double? = nil,
        segmentBreaks: [HikingSegmentBreak]? = nil,
        elevationGainMeters: Double? = nil,
        elevationProfile: [HikingElevationChartSample]? = nil,
        heartRateProfile: [HikingHeartRateChartSample]? = nil,
        displayRouteCoordinates: [HikingDisplayCoordinate]? = nil,
        kilometerMarkers: [RouteKilometerMarkerPlacement]? = nil,
        nearbySummits: [MountainSummit]? = nil,
        displayCacheVersion: Int? = nil,
        lastUpdated: Date = Date()
    ) {
        self.sessionID = sessionID
        self.state = state
        self.startedAt = startedAt
        self.totalDistance = totalDistance
        self.elapsedTime = elapsedTime
        self.currentPace = currentPace
        self.currentAltitude = currentAltitude
        self.points = points
        self.photos = photos
        self.heartRateSamples = heartRateSamples
        self.currentHeartRate = currentHeartRate
        self.stepCount = stepCount
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.segmentBreaks = segmentBreaks
        self.elevationGainMeters = elevationGainMeters
        self.elevationProfile = elevationProfile
        self.heartRateProfile = heartRateProfile
        self.displayRouteCoordinates = displayRouteCoordinates
        self.kilometerMarkers = kilometerMarkers
        self.nearbySummits = nearbySummits
        self.displayCacheVersion = displayCacheVersion
        self.lastUpdated = lastUpdated
    }

    static let empty = HikingSessionData()

    /// 심박수 샘플 평균(bpm). 없으면 nil.
    var averageHeartRate: Double? {
        guard !heartRateSamples.isEmpty else { return nil }
        let total = heartRateSamples.reduce(0.0) { $0 + $1.bpm }
        return total / Double(heartRateSamples.count)
    }

    /// 저장·표시용 시작 시각.
    nonisolated var effectiveStartedAt: Date? {
        startedAt ?? points.min(by: { $0.timestamp < $1.timestamp })?.timestamp
    }

    /// 저장·표시용 종료 시각 — 기록 종료 시점(동기화 시각이 아님).
    var effectiveEndedAt: Date {
        if let started = effectiveStartedAt, elapsedTime > 0 {
            return started.addingTimeInterval(elapsedTime)
        }
        if let lastPoint = points.max(by: { $0.timestamp < $1.timestamp }) {
            return lastPoint.timestamp
        }
        return lastUpdated
    }

    /// 저장된 표시 캐시가 최신 버전으로 준비됐는지.
    nonisolated var hasPersistedDisplayCache: Bool {
        guard displayCacheVersion == HikingSessionDisplayCacheBuilder.cacheVersion,
              let storedCoordinates = displayRouteCoordinates,
              storedCoordinates.count >= 2 else {
            return false
        }
        return true
    }

    /// GPS 포인트 기준 누적 상승 고도(미터).
    var cumulativeElevationGain: Double {
        elevationGainMeters ?? HikingSessionMetrics.cumulativeElevationGain(from: points)
    }

    /// GPS 포인트에서 재계산한 수평 이동 거리(미터).
    nonisolated var distanceFromPoints: Double {
        HikingSessionMetrics.horizontalDistance(from: points)
    }

    /// 저장 직전 거리·시작 시각·표시용 캐시를 포인트 기준으로 맞춥니다.
    /// 거리는 실시간 누적값과 포인트 재계산값 중 큰 쪽 — 잘린 스냅샷(일부 포인트만 도착)이
    /// 실시간 누적 거리를 덮어쓰지 않도록 합니다.
    nonisolated mutating func finalizeForPersistence() {
        if startedAt == nil {
            startedAt = effectiveStartedAt
        }
        let reconciled = distanceFromPoints
        if reconciled > totalDistance {
            totalDistance = reconciled
        }
        applyDisplayCache(
            HikingSessionDisplayCacheBuilder.build(
                points: points,
                heartRateSamples: heartRateSamples
            )
        )
    }

    /// 동일 세션의 두 스냅샷을 ID 기준으로 합집합 병합합니다 — 부분 전송 후 전체 전송이
    /// 도착했을 때(또는 그 반대) 어느 쪽 데이터도 잃지 않도록 합니다.
    func mergingSameSession(with other: HikingSessionData) -> HikingSessionData {
        var merged = self

        let existingPointIDs = Set(points.map(\.id))
        merged.points.append(contentsOf: other.points.filter { !existingPointIDs.contains($0.id) })
        merged.points.sort { $0.timestamp < $1.timestamp }

        let existingPhotoIDs = Set(photos.map(\.id))
        merged.photos.append(contentsOf: other.photos.filter { !existingPhotoIDs.contains($0.id) })
        merged.photos.sort { $0.timestamp < $1.timestamp }

        let existingSampleIDs = Set(heartRateSamples.map(\.id))
        merged.heartRateSamples.append(
            contentsOf: other.heartRateSamples.filter { !existingSampleIDs.contains($0.id) }
        )
        merged.heartRateSamples.sort { $0.timestamp < $1.timestamp }

        let mergedBreaks = (segmentBreaks ?? []) + (other.segmentBreaks ?? [])
        if !mergedBreaks.isEmpty {
            var seen = Set<UUID>()
            merged.segmentBreaks = mergedBreaks
                .filter { seen.insert($0.id).inserted }
                .sorted { $0.pauseTime < $1.pauseTime }
        }

        merged.elapsedTime = max(elapsedTime, other.elapsedTime)
        merged.totalDistance = max(totalDistance, other.totalDistance)
        switch (stepCount, other.stepCount) {
        case (let lhs?, let rhs?):
            merged.stepCount = max(lhs, rhs)
        case (nil, let rhs?):
            merged.stepCount = rhs
        default:
            break
        }
        switch (activeEnergyKilocalories, other.activeEnergyKilocalories) {
        case (let lhs?, let rhs?):
            merged.activeEnergyKilocalories = max(lhs, rhs)
        case (nil, let rhs?):
            merged.activeEnergyKilocalories = rhs
        default:
            break
        }
        switch (startedAt, other.startedAt) {
        case (let lhs?, let rhs?):
            merged.startedAt = min(lhs, rhs)
        case (nil, let rhs?):
            merged.startedAt = rhs
        default:
            break
        }
        merged.lastUpdated = max(lastUpdated, other.lastUpdated)
        // 포인트 구성이 바뀌었으므로 표시 캐시는 무효화 — finalizeForPersistence()가 다시 만듭니다.
        merged.displayCacheVersion = nil
        return merged
    }

    nonisolated mutating func applyDisplayCache(_ built: HikingSessionDisplayCacheBuilder.Built) {
        elevationGainMeters = built.elevationGainMeters
        elevationProfile = built.elevationProfile
        heartRateProfile = built.heartRateProfile
        displayRouteCoordinates = built.displayRouteCoordinates
        kilometerMarkers = built.kilometerMarkers
        nearbySummits = built.nearbySummits
        displayCacheVersion = HikingSessionDisplayCacheBuilder.cacheVersion
    }
}

/// 세션 기록 상태.
nonisolated enum HikingSessionState: String, Codable, Hashable, Sendable {
    case idle
    case recording
    case paused
}
