//
//  HikingTrailPhotoCoordinateLayout.swift
//  Shared
//
//  지도 마커 겹침 방지 — 저장 좌표는 유지하고 표시 좌표만 분리.
//

import Foundation

#if canImport(CoreLocation)
import CoreLocation

enum HikingTrailPhotoCoordinateLayout {
    /// 지도에서 마커가 겹치지 않도록 하는 최소 간격(미터).
    static let minSeparationMeters: Double = 8

    /// 사진 ID → 지도 표시용 좌표 (클러스터는 앵커 좌표 공유).
    static func displayCoordinates(for photos: [HikingTrailPhoto]) -> [UUID: CLLocationCoordinate2D] {
        var result: [UUID: CLLocationCoordinate2D] = [:]
        for placement in TrailPhotoMapMarkerPlacementBuilder.placements(for: photos) {
            for photo in placement.photos {
                result[photo.id] = placement.coordinate
            }
        }
        return result
    }

    static func distanceMeters(
        _ a: CLLocationCoordinate2D,
        _ b: CLLocationCoordinate2D
    ) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    static func geographicBearing(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) -> Double {
        let lat1 = start.latitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let deltaLongitude = (end.longitude - start.longitude) * .pi / 180
        let y = sin(deltaLongitude) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLongitude)
        var degrees = atan2(y, x) * 180 / .pi
        if degrees < 0 {
            degrees += 360
        }
        return degrees
    }

    static func offsetCoordinate(
        from coordinate: CLLocationCoordinate2D,
        meters: Double,
        bearingDegrees: Double
    ) -> CLLocationCoordinate2D {
        let earthRadius = 6_371_000.0
        let bearing = bearingDegrees * .pi / 180
        let lat1 = coordinate.latitude * .pi / 180
        let lon1 = coordinate.longitude * .pi / 180
        let angular = meters / earthRadius

        let lat2 = asin(
            sin(lat1) * cos(angular) + cos(lat1) * sin(angular) * cos(bearing)
        )
        let lon2 = lon1 + atan2(
            sin(bearing) * sin(angular) * cos(lat1),
            cos(angular) - sin(lat1) * sin(lat2)
        )

        return CLLocationCoordinate2D(
            latitude: lat2 * 180 / .pi,
            longitude: lon2 * 180 / .pi
        )
    }
}
#endif
