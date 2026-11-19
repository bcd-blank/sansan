//
//  HikingRecordRouteDisplayPreparer.swift
//  Shared
//

import CoreLocation
import Foundation

/// 기록 상세 지도 표시용 경로 데이터 — 메인 스레드 블로킹을 피하기 위해 백그라운드에서 준비합니다.
enum HikingRecordRouteDisplayPreparer {
    struct DisplayData: Sendable {
        let coordinates: [CLLocationCoordinate2D]
        let kilometerMarkers: [RouteKilometerMarkerPlacement]
        let nearbySummits: [MountainSummit]
    }

    static func prepare(points: [HikingPoint], includeSummits: Bool) async -> DisplayData {
        // Never `waitUntilReady` here — catalog load can take seconds and blocked
        // detail open (3–9s). Use whatever summits are already loaded; caller may
        // refresh when the catalog finishes.
        return await Task.detached(priority: .userInitiated) {
            let coordinates = HikingSessionMetrics.routeCoordinates(from: points)
            let kilometerMarkers = HikingSessionMetrics.kilometerMarkerPlacements(from: points)
            let summits = includeSummits
                ? MountainSummitRouteFilter.summits(near: coordinates)
                : []
            return DisplayData(
                coordinates: coordinates,
                kilometerMarkers: kilometerMarkers,
                nearbySummits: summits
            )
        }.value
    }
}
