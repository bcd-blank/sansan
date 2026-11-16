//
//  MountainSummitRouteFilter.swift
//  Shared
//

import CoreLocation
import Foundation

enum MountainSummitRouteFilter {
    /// 경로 선분에서 이 거리 이내 정상만 표시합니다.
    nonisolated static let proximityMeters: CLLocationDistance = 800
    /// 긴 능선 구간에서 지도가 복잡해지지 않도록 상한.
    nonisolated static let maxDisplayedSummits = 40
    /// 거리 계산용 경로 단순화 상한 — GPS 포인트가 많을 때 메인 스레드 부하를 줄입니다.
    nonisolated private static let polylineSimplificationLimit = 96

    nonisolated private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: [MountainSummit]] = [:]

    nonisolated static func summits(near coordinates: [CLLocationCoordinate2D]) -> [MountainSummit] {
        guard coordinates.count >= 2 else { return [] }

        let cacheKey = routeCacheKey(for: coordinates)
        lock.lock()
        if let cached = cache[cacheKey] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let result = computeSummits(near: coordinates)

        lock.lock()
        cache[cacheKey] = result
        if cache.count > 24 {
            cache.removeAll(keepingCapacity: true)
            cache[cacheKey] = result
        }
        lock.unlock()

        return result
    }

    nonisolated private static func computeSummits(near coordinates: [CLLocationCoordinate2D]) -> [MountainSummit] {
        let simplifiedRoute = simplifiedPolyline(
            from: coordinates,
            maxPoints: polylineSimplificationLimit
        )
        let bounds = expandedBounds(for: simplifiedRoute, marginMeters: proximityMeters + 200)
        let candidates = MountainSummitCatalog.allSummits.filter { summit in
            summit.latitude >= bounds.minLatitude
                && summit.latitude <= bounds.maxLatitude
                && summit.longitude >= bounds.minLongitude
                && summit.longitude <= bounds.maxLongitude
        }

        var matches: [(MountainSummit, CLLocationDistance)] = []
        matches.reserveCapacity(min(candidates.count, 64))

        for summit in candidates {
            let distance = minimumDistanceMeters(
                from: summit.coordinate,
                toPolyline: simplifiedRoute
            )
            if distance <= proximityMeters {
                matches.append((summit, distance))
            }
        }

        matches.sort { $0.1 < $1.1 }
        return matches.prefix(maxDisplayedSummits).map(\.0)
    }

    nonisolated private static func simplifiedPolyline(
        from coordinates: [CLLocationCoordinate2D],
        maxPoints: Int
    ) -> [CLLocationCoordinate2D] {
        guard coordinates.count > maxPoints, maxPoints >= 2 else { return coordinates }

        var simplified: [CLLocationCoordinate2D] = [coordinates[0]]
        let stride = Double(coordinates.count - 1) / Double(maxPoints - 1)

        if maxPoints > 2 {
            for index in 1..<(maxPoints - 1) {
                let sourceIndex = min(Int((Double(index) * stride).rounded()), coordinates.count - 1)
                simplified.append(coordinates[sourceIndex])
            }
        }

        simplified.append(coordinates[coordinates.count - 1])
        return simplified
    }

    nonisolated private static func routeCacheKey(for coordinates: [CLLocationCoordinate2D]) -> String {
        guard let first = coordinates.first, let last = coordinates.last else { return "empty" }
        return "\(coordinates.count)|\(quantized(first.latitude))|\(quantized(first.longitude))|\(quantized(last.latitude))|\(quantized(last.longitude))"
    }

    nonisolated private static func quantized(_ value: Double) -> Int {
        Int((value * 10_000).rounded())
    }

    nonisolated private static func expandedBounds(
        for coordinates: [CLLocationCoordinate2D],
        marginMeters: CLLocationDistance
    ) -> (minLatitude: Double, maxLatitude: Double, minLongitude: Double, maxLongitude: Double) {
        var minLatitude = coordinates[0].latitude
        var maxLatitude = coordinates[0].latitude
        var minLongitude = coordinates[0].longitude
        var maxLongitude = coordinates[0].longitude

        for coordinate in coordinates {
            minLatitude = min(minLatitude, coordinate.latitude)
            maxLatitude = max(maxLatitude, coordinate.latitude)
            minLongitude = min(minLongitude, coordinate.longitude)
            maxLongitude = max(maxLongitude, coordinate.longitude)
        }

        let marginDegrees = metersToLatitudeDegrees(marginMeters)
        let centerLatitude = (minLatitude + maxLatitude) / 2
        let longitudeMargin = metersToLongitudeDegrees(marginMeters, atLatitude: centerLatitude)

        return (
            minLatitude: minLatitude - marginDegrees,
            maxLatitude: maxLatitude + marginDegrees,
            minLongitude: minLongitude - longitudeMargin,
            maxLongitude: maxLongitude + longitudeMargin
        )
    }

    nonisolated private static func minimumDistanceMeters(
        from point: CLLocationCoordinate2D,
        toPolyline coordinates: [CLLocationCoordinate2D]
    ) -> CLLocationDistance {
        let location = CLLocation(latitude: point.latitude, longitude: point.longitude)
        var minimum = CLLocationDistance.greatestFiniteMagnitude

        for index in 0..<(coordinates.count - 1) {
            let start = coordinates[index]
            let end = coordinates[index + 1]
            let distance = distanceMeters(
                from: location,
                toSegmentStart: start,
                end: end
            )
            minimum = min(minimum, distance)
        }

        return minimum
    }

    nonisolated private static func distanceMeters(
        from location: CLLocation,
        toSegmentStart start: CLLocationCoordinate2D,
        end: CLLocationCoordinate2D
    ) -> CLLocationDistance {
        let startLocation = CLLocation(latitude: start.latitude, longitude: start.longitude)
        let endLocation = CLLocation(latitude: end.latitude, longitude: end.longitude)

        let segmentLength = startLocation.distance(from: endLocation)
        let toStart = location.distance(from: startLocation)
        let toEnd = location.distance(from: endLocation)

        guard segmentLength > 0.5 else { return toStart }

        if toEnd * toEnd >= segmentLength * segmentLength + toStart * toStart {
            return toStart
        }
        if toStart * toStart >= segmentLength * segmentLength + toEnd * toEnd {
            return toEnd
        }

        let semiperimeter = (segmentLength + toStart + toEnd) / 2
        let areaSquared = semiperimeter
            * (semiperimeter - segmentLength)
            * (semiperimeter - toStart)
            * (semiperimeter - toEnd)
        guard areaSquared > 0 else { return min(toStart, toEnd) }

        return 2 * sqrt(areaSquared) / segmentLength
    }

    nonisolated private static func metersToLatitudeDegrees(_ meters: CLLocationDistance) -> Double {
        meters / 111_320
    }

    nonisolated private static func metersToLongitudeDegrees(
        _ meters: CLLocationDistance,
        atLatitude latitude: Double
    ) -> Double {
        let cosine = max(cos(latitude * .pi / 180), 0.2)
        return meters / (111_320 * cosine)
    }
}
