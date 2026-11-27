import XCTest
@testable import sansan
import CoreGraphics
import CoreLocation
import MapKit

final class RouteCornerSmoothingTests: XCTestCase {
    func testAlongPtIsOnePercentOfMinSide() {
        XCTAssertEqual(RouteCornerSmoothing.alongPt(mapWidth: 390, mapHeight: 420), 3.9, accuracy: 1e-9)
        XCTAssertEqual(RouteCornerSmoothing.alongPt(mapWidth: 400, mapHeight: 200), 2.0, accuracy: 1e-9)
    }

    func testResampleGaussCatmullRoundsCornerAndKeepsEnds() {
        let points: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 40, y: 0),
            CGPoint(x: 40, y: 40)
        ]
        let smoothed = RouteCornerSmoothing.smoothPoints(points, maxAlong: 8)
        XCTAssertGreaterThan(smoothed.count, points.count)
        XCTAssertEqual(smoothed.first!.x, 0, accuracy: 1e-6)
        XCTAssertEqual(smoothed.first!.y, 0, accuracy: 1e-6)
        XCTAssertEqual(smoothed.last!.x, 40, accuracy: 1e-6)
        XCTAssertEqual(smoothed.last!.y, 40, accuracy: 1e-6)
        // Apex (40,0) must be pulled inward by Gaussian+Catmull.
        XCTAssertFalse(smoothed.contains { hypot($0.x - 40, $0.y - 0) < 0.5 })
    }

    func testShortStretchSkipsSmooth() {
        // Length 20 < 3·t_m (=24) → raw.
        let points: [CGPoint] = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 10, y: 0),
            CGPoint(x: 20, y: 0)
        ]
        let smoothed = RouteCornerSmoothing.smoothPoints(points, maxAlong: 8)
        XCTAssertEqual(smoothed.count, points.count)
        XCTAssertEqual(smoothed[1].x, 10, accuracy: 1e-9)
    }

    func testColinearStaysOnLine() {
        let points: [CGPoint] = (0..<8).map { CGPoint(x: CGFloat($0) * 10, y: 0) }
        let smoothed = RouteCornerSmoothing.smoothPoints(points, maxAlong: 4)
        XCTAssertEqual(smoothed.first, points.first)
        XCTAssertEqual(smoothed.last, points.last)
        for p in smoothed {
            XCTAssertEqual(p.y, 0, accuracy: 1e-5)
        }
    }

    func testGamajiSmoothDiffersFromRawAtFitL() {
        let fixture = UITestMountainPathFixtures.gamajicheon
        let coords: [CLLocationCoordinate2D] = fixture.points.map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
        }
        let region = HikingMapRegion.fitting(
            coordinates: coords,
            viewSize: CGSize(width: 390, height: 420)
        )
        let mpp = RouteCornerSmoothing.metersPerPoint(
            latitude: region.center.latitude,
            visibleMapRect: region.mapRect,
            boundsWidth: 390
        )
        let L = RouteCornerSmoothing.alongPt(mapWidth: 390, mapHeight: 420)
        let tM = RouteCornerSmoothing.maxAlongMeters(metersPerPoint: mpp, alongPt: L)
        XCTAssertGreaterThan(tM, 5) // fit ≈ 15m class
        let smoothed = RouteCornerSmoothing.smoothCoordinates(
            coords,
            metersPerPoint: mpp,
            alongPt: L
        )
        XCTAssertEqual(smoothed.first!.latitude, coords.first!.latitude, accuracy: 1e-9)
        XCTAssertEqual(smoothed.last!.latitude, coords.last!.latitude, accuracy: 1e-9)
        XCTAssertNotEqual(smoothed.count, coords.count)
        let mid = coords[coords.count / 2]
        let midLoc = CLLocation(latitude: mid.latitude, longitude: mid.longitude)
        let nearest = smoothed.map {
            midLoc.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
        }.min() ?? 0
        let apex = coords[232]
        let apexLoc = CLLocation(latitude: apex.latitude, longitude: apex.longitude)
        let apexCut = smoothed.map {
            apexLoc.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
        }.min() ?? 0
        XCTAssertGreaterThan(apexCut, 0.5, "v3 must pull sharp tip inward")
        XCTAssertLessThan(nearest, 30)
        // Max deviation raw→smooth ≤ 3·t_m.
        var maxDev = 0.0
        for c in coords {
            let loc = CLLocation(latitude: c.latitude, longitude: c.longitude)
            let d = smoothed.map {
                loc.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
            }.min() ?? 0
            maxDev = max(maxDev, d)
        }
        XCTAssertLessThanOrEqual(maxDev, 3 * tM + 1e-6)
    }

    func testStretchOnSmoothedKeepsLayers() {
        let fixture = UITestMountainPathFixtures.gamajicheon
        let coords: [CLLocationCoordinate2D] = fixture.points.map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
        }
        let region = HikingMapRegion.fitting(
            coordinates: coords,
            viewSize: CGSize(width: 390, height: 420)
        )
        let smoothed = RouteCornerSmoothing.smoothCoordinates(
            coords,
            fittingRegion: region,
            mapWidth: 390,
            mapHeight: 420
        )
        let stretches = RouteSelfCrossing.chronologicalCoordinateStretches(in: smoothed)
        XCTAssertFalse(stretches.isEmpty || stretches.allSatisfy { $0.count < 2 })
    }
}
